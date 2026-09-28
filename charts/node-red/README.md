# Node-RED Helm Chart

[Node-RED](https://nodered.org) 是低代码的流式编程工具。本 chart 跑**官方镜像**
`nodered/node-red`，不构建自定义镜像；应用专属的东西（settings.js、额外的 palette
节点）由 chart 在启动时叠加。

镜像 tag 默认取 `Chart.yaml` 的 `appVersion`（`5.0.7-24` = Node-RED 5.0.7 + Node 24 +
alpine）。上游同时发布 `5.0.7`、`5.0.7-24`、`5.0.7-debian`、`-minimal` 等变体，
`image.tag` 可改。官方镜像不预装任何额外 contrib 节点（只有 node-red 与
node-red-admin），要什么由 `nodeRed.extraNodes` 装。

共享的 values 结构（`image`、`service`、`workload`、`persistence`、`ingress`、
`resources` 等）见[仓库根 README](../../README.md#values-schema)，本文件只列本 chart
专属的部分。

## 安装

```bash
helm repo add eslizn https://eslizn.github.io/helm-charts
helm install node-red eslizn/node-red -n node-red --create-namespace
```

## 本 chart 专属参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `nodeRed.userDir` | `/data` | Node-RED 的用户目录：flows、credentials、palette 节点都在这里。官方镜像用 `/data` |
| `nodeRed.settings` | 空 | 内联的 `settings.js` 全文，渲染成 ConfigMap 挂进去 |
| `nodeRed.existingSettingsConfigMap` / `settingsKey` | 空 / `settings.js` | 用已有的 ConfigMap 提供 settings.js |
| `nodeRed.extraNodes` | `[]` | 额外 palette 节点的 npm spec 列表，启动时装进 `<userDir>/node_modules` |
| `env` | `{}` | 非密钥环境变量 map → ConfigMap → `envFrom` |
| `secret.create` / `data` / `existingSecret` | `false` / `{}` / 空 | 密钥 → Secret → `envFrom`。默认什么都不建 |
| `persistence.mountPath` | `/data` | **必须等于 `nodeRed.userDir`**，不等则 chart 直接报错 |

## 用户目录必须有卷（`extraNodes` 的硬约束）

`extraNodes` 由一个 **initContainer** 装进 `<userDir>/node_modules` —— 那里既是
Node-RED 扫描节点的位置，也是 settings.js 里 `require()` 的解析起点。但
**initContainer 的可写层与主容器不共享**，所以这个目录必须是一个两边都挂的卷：

- `persistence.enabled=true`（默认）→ 用 PVC，装一次就缓存住，重启是秒级；
- `persistence.enabled=false` + 有 `extraNodes` → chart 自动补一个 `emptyDir`，
  **每次启动都重装**（装 20~30 个包约 2 分钟）；
- `extraNodes` 为空 → 不需要额外的卷，用容器自己的可写层。

装了标记文件 `.node-red-nodes-<specs 的哈希>`：specs 不变就跳过安装，改了才重装。

用非 local-path 的 StorageClass 时，卷根目录可能是 root 所有，而官方镜像以
**uid 1000** 运行，写不进去会让 initContainer 失败。此时加：

```yaml
podSecurityContext:
  fsGroup: 1000
  fsGroupChangePolicy: OnRootMismatch   # 否则每次启动都会递归 chown 整个 node_modules
```

装了 20~30 个包之后 `node_modules` 有几百 MB、几万个文件，`fsGroupChangePolicy`
这一行不是可选项。

`persistence.subPath` 也支持：installer 会挂**同一个 subPath**（否则它会装到卷根、
而 Node-RED 读子目录，静默失效）。

## settings.js 的三种给法

1. **不挂（默认）**：跑 Node-RED 自带默认值 —— 注意这意味着**编辑器没有任何认证**，
   别在集群外暴露。
2. **内联**：`nodeRed.settings` 放全文（git 里有），chart 渲染成 ConfigMap 并以
   subPath 只读挂到 `<userDir>/settings.js`。
3. **已有 ConfigMap**：`nodeRed.existingSettingsConfigMap=<名字>`，自己用
   SealedSecrets / External Secrets 管理。

两种挂法都不需要传 `--settings`：Node-RED 默认就读 `<userDir>/settings.js`。

顺带一条别踩的坑：**官方镜像的 entrypoint 里写死了 `--userDir /data`**
（`node … red.js --userDir /data $FLOWS "$@"`）。所以 `nodeRed.userDir` 一般不用改，
而覆盖 `workload.command` 会绕过这个 entrypoint、连带丢掉 `--userDir`，
结果是 Node-RED 去读一个什么都没挂的目录。要追加参数请用 `workload.args`
（它被拼在 `"$@"` 位置，安全）。

## 改配置什么时候生效

subPath 挂载的 ConfigMap 不随 ConfigMap 更新而刷新，`envFrom` 的值也只在进程启动时读一次。
所以 chart 给 Pod 模板打了一个注解：

```
checksum/node-red-config: <settings + env + secret 的哈希>
```

改 `nodeRed.settings`、`env`、`secret.*` 中任何一项都会让这个哈希变、Pod 模板变、触发滚动重启
—— 否则在 ArgoCD 下会出现"改了 values 但 ConfigMap 变了、Pod 没动、Node-RED 还在跑旧配置"。
`extraNodes` 的变更同理：装节点的 marker 名（含 specs 与镜像）就写在 initContainer 的参数里，
specs 或镜像一变，哈希变、Pod 滚动、initContainer 重装。

## 数据与持久化

默认开启持久化（1Gi），因为 flows 与 credentials 就存在 `<userDir>` 里。
`persistence.enabled=false` 时这些内容随 Pod 消失。挂一个全新卷到 `/data` 会**遮住
镜像自带的 `/data`**（里面是初始的 flows.json 与 lib/），Node-RED 会按空目录重新
生成 —— 这是官方镜像挂卷的标准形态，不是故障。

卷是 RWO：`replicaCount > 1` 会因卷争用失败，除非改成 RWX 并接受多实例共享状态。

## Helm test

`helm test` 只断言 HTTP 层有响应。之所以不用 `common.testConnection`：那个是裸
`wget <svc>:<port>`，非 2xx 就算失败，而 Node-RED 一旦在 settings.js 里配了
`adminAuth`，访问 `/` 会返回 302（或 401）。

## 探针

默认**不启用**存活/就绪探针。要开就按端口名写，`containerPort` 改了也自洽：

```yaml
workload:
  livenessProbe:
    httpGet: {path: /, port: http}
    initialDelaySeconds: 30
  readinessProbe:
    httpGet: {path: /, port: http}
```

之所以不默认开：Node-RED 的 HTTP 面是可配置的。settings.js 里配了 `adminAuth` 时，
未登录访问 `/` 通常是 **302（探针可过）**；但若你的认证策略返回 **401**，或者把
`httpAdminRoot` 改到了别的路径 / 关掉编辑器，默认探针就会让 Pod 陷入重启循环。
先在集群里确认一次再开。

## 已知限制

- 不管理 flows 本身：flow 的导入导出走编辑器、`<userDir>/flows.json` 或你自己的
  存储方案。要让 flows 进 Git，得自己用 ConfigMap/Secret 挂 `flows.json` 并配
  `credentialSecret`。
- `nodeRed.settings` 是原样文本，chart 不解释它的内容 —— `require()` 了哪些模块、
  要哪些环境变量，都由你自己保证（缺模块会让 Node-RED 起不来，不是降级）。
- `extraNodes` 用 npm 装机，npm 11 起默认不执行包的 install script，依赖原生构建的
  节点可能装完仍不可用，需要时在 `workload.initContainers` 里自己接管安装。
- `extraNodes` 只支持 npm 能解析的 spec（registry 包、git URL、已有 registry 上的包）。
  `file:` 形式的本地包需要源码同时出现在两个容器里，本 chart 没有提供"两边都挂"的卷键
  —— 有这需求时用 `workload.volumes/volumeMounts` 给主容器挂，并在 installer 装之前
  用 `workload.initContainers` 把源码铺好（installer 跑在它们之后）。
- `workload.kind` 只能是 `Deployment`（chart 只渲染 `common.deployment`）。写成别的会
  直接被 `fail` 拦下 —— 不拦的话它不但被忽略，还会让 PVC 不再被挂载（common 库认为
  StatefulSet 走 claimTemplate）。
- `replicaCount > 1` 与 `extraNodes` 配合有问题：两个 Pod 会并发往同一个 RWO 卷里装。
  Node-RED 本来就是单副本形态。

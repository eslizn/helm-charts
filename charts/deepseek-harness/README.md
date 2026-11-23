# DeepSeek Harness Helm Chart

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）是
DeepSeek 的开源 agent harness，采用「一切皆插件」的架构。本 chart 通过官方 Web UI
提供浏览器访问，并把它的状态持久化。

上游没有 Docker 镜像，官方安装方式是 npm 包 `@deepseek-ai/dsh`，所以镜像在本仓库
自建，构建上下文在 [`image/`](image)。镜像 tag 默认取 `Chart.yaml` 的 `appVersion`
（`0.2.2-rc.5`），该值必须与 `image/Dockerfile` 的 `DSH_VERSION` 一致。

共享的 values 结构（`image`、`service`、`workload`、`persistence`、`ingress`、
`resources` 等）见[仓库根 README](../../README.md#values-schema)，本文件只列本 chart
专属的部分。

## 安装

```bash
helm repo add eslizn https://eslizn.github.io/helm-charts
helm install deepseek-harness eslizn/deepseek-harness -n dsh --create-namespace
```

默认值会：

- 创建一个单副本 StatefulSet；
- 创建一个 10Gi 的 RWO PVC，`$DSH_HOME`、`/workspace` 和 `/home/dsh/.agents` 用三个
  subPath 共享它；
- 不创建 Ingress。

首次访问需要从日志里取带一次性 token 的启动 URL：

```bash
kubectl -n dsh logs statefulset/deepseek-harness | grep 'dsh web: http'
```

浏览器打开打印的 URL 一次，dsh 会换发一个 30 天有效的签名 cookie，之后可以直接访问
不带 token 的地址。token 只打印在进程日志里，属于凭据，不要转发给无关的人。

## 访问方式

### Ingress（推荐）

```yaml
ingress:
  enabled: true
  className: traefik
  hosts:
    - host: dsh.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: dsh-tls
      hosts:
        - dsh.example.com
```

chart 会自动：

- 把每个 `ingress.hosts[].host` 加进 `--trusted-host`；
- 在 path 为 `/` 时，按 `ingress.tls` 推导
  `dsh.web.publicUrl`（上例为 `https://dsh.example.com/`）。

dsh 的 `/api` 有 Host/Origin 检查；`--public-url` 只负责「对外宣告地址」，不授予
信任。两者都必须正确，否则浏览器能打开首页，但 API/WebSocket 会 403。

**非根路径**：例如 ingress path 为 `/dsh` 时，必须显式设置

```yaml
dsh:
  web:
    publicUrl: https://dsh.example.com/dsh/
```

并让代理把 `/dsh` 前缀 strip 掉（Traefik 用 StripPrefix middleware，nginx 用
rewrite 注解）。chart 无法知道代理是否做了这件事，所以不会自动推导非根路径。

**多 host / 通配符**：`publicUrl` 只能有一个，chart 用第一个 host 推导；trusted
hosts 会包含所有 `ingress.hosts` 条目。dsh 的 Host/Origin 检查只做精确匹配（或
host:port 的无端口匹配），不支持 `*.example.com`，所以通配符 Ingress 还需要把实际
访问的 host 写进 `dsh.web.trustedHosts`。

**WebSocket / 上传**：Web UI 依赖 `/api/remote.mux` 的 WebSocket。Traefik 默认支持；
nginx ingress 建议加：

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
```

### kubectl port-forward

```bash
kubectl -n dsh port-forward svc/deepseek-harness 3080:3080
```

dsh 拒绝绑定 `0.0.0.0`，只监听 Pod IP；而 kubelet 的 port-forward 是拨 Pod 内的
localhost。镜像里的 entrypoint 因此额外在 `127.0.0.1:3080` 起了一个极小的 TCP
转发，专门给 port-forward 用。打开时把日志里打印 URL 的主机部分换成
`127.0.0.1:3080`，保留 `?token=...`：

```
http://127.0.0.1:3080/?token=...
```

Service/Ingress 和探针都直接走 Pod IP，不经过这个转发。

### 直接暴露 Service / LoadBalancer

dsh 只接受 loopback、自己的绑定地址或 `--trusted-host` 里的 authority。把
LoadBalancer 的 hostname（或 `host:port`）写进 `dsh.web.trustedHosts`，否则
`/api` 会返回 403。内置 token 只保护 UI/API，不保护端口本身，建议仍然放在
TLS 和访问控制后面。

## 持久化

默认一个 PVC 承载全部状态，用两个 subPath 分开：

| subPath | 挂载点 | 内容 |
|---------|--------|------|
| `dsh` | `/home/dsh/.dsh` | 配置、`.credentials.yaml`、`profiles/`（插件与 profile 设置）、`sessions/`、`storages/`、日志与缓存 |
| `workspace` | `/workspace` | agent 的工作目录 |
| `agents` | `/home/dsh/.agents` | 共享 agent 根（`DSH_AGENTS_HOME`）：用户级 `AGENTS.md`、`skills/` |

一个 initContainer 在主容器启动前创建这些 subPath；它和主容器一样以非 root
（uid/gid 10001）运行。卷根目录必须对这个 uid/fsGroup 可写，chart 默认设置
`podSecurityContext.fsGroup: 10001`。如果存储类不执行 fsGroup（例如某些 NFS），
initContainer 会失败并打印明确提示。

可选组合：

```yaml
persistence:
  enabled: false          # 全部临时：配置、插件、会话、工作区都随 Pod 重启丢失

# 或：只持久化 $DSH_HOME，工作区和 agents 临时
dsh:
  workspace:
    persistent: false
  agents:
    persistent: false
```

`persistence.size` 同时覆盖配置、工作区和 agents home，默认 `10Gi`。PVC 由 chart
单独创建，名称是 Helm fullname（通常是 release + chart），**不是** StatefulSet 的
claim template —— 后者会把 chart 版本
写进不可变的 `volumeClaimTemplates` 标签里，下一次 chart 版本升级就可能被 API server
拒绝。独立 PVC 同时带来：

- `persistence.existingClaim` 可以直接挂已有 PVC，此时不创建 PVC；
- `persistence.create=false` 表示自带 PVC，必须同时设置 `existingClaim`；
- `persistence.keep` 默认 `true`，给 PVC 加 `helm.sh/resource-policy: keep`，
  `helm uninstall` 后保留；设为 `false` 则随 release 删除；
- `persistence.annotations` 会加到 PVC 上（`keep` 会设置/覆盖
  `helm.sh/resource-policy`）；
- 调大 `persistence.size` 会更新 PVC 的 request，需要 StorageClass 支持在线扩容；
  Kubernetes 不支持缩容。`accessModes` 和 `storageClassName` 创建后不可变，改这些
  需要重建 PVC。
- 卸载后重装同名 release 时，`keep=true` 留下的 PVC 会让 Helm 的创建冲突：要么先
  删除 PVC，要么设 `persistence.create=false` 和
  `persistence.existingClaim=<fullname>` 复用它。

`~/.agents`（共享的 `AGENTS.md`/`skills`，由 `DSH_AGENTS_HOME` 控制）不在
`$DSH_HOME` 内，但默认也走同一个 PVC 的 `agents` subPath。要把它换成别的共享卷时，
设 `dsh.agents.persistent=false`，再用 `workload.volumeMounts` 挂载到
`dsh.agents.home`。

## 配置

### 模型与凭据

两种方式任选：

1. 打开 Web UI → **Settings → Models**，填 DeepSeek API key 或自定义
   OpenAI-compatible endpoint。凭据写进 `$DSH_HOME/.credentials.yaml`，PVC 持久化
   后跨重启保留。
2. 安装时通过 Secret 注入 `DEEPSEEK_API_KEY`：

```yaml
secret:
  existingSecret: deepseek-credentials   # 已在同一 namespace 建好
# 或
secret:
  create: true
  data:
    DEEPSEEK_API_KEY: sk-...
```

`env` 是普通配置 map，渲染成 ConfigMap 后 `envFrom`；`workload.env` /
`workload.envFrom` 是原始的 EnvVar 列表，继续可用。chart 自己的保留变量
（`POD_IP`、`DSH_HOME`、`DSH_WORKSPACE`、`DSH_WEB_PORT`、`DSH_PUBLIC_URL`、
`DSH_TRUSTED_HOSTS`）会覆盖同名的用户值；请用对应的 values 字段而不是手工覆盖。

### 权限模式

`dsh.permissionMode` 映射到 `DSH_PERMISSION_MODE`，默认留空 = 上游默认
`workspace-write`（写工作区、审批 ask）。Web UI 里可以按会话切换。`workspace-write`
的 bash 沙箱依赖容器内可用的 **bwrap 或 Landlock**；如果集群的 seccomp/内核不允许，
bash 工具会 fail closed（明确报 `SANDBOX_UNAVAILABLE`）。此时可以：

```yaml
dsh:
  permissionMode: danger-full-access
```

容器本身就是隔离边界；但这等于不再限制 agent 在容器内的写操作和命令审批。

### 其他

- `workload.args` 会追加到 entrypoint 生成的 `dsh --profile web` 参数之后，例如
  额外的 `--trusted-host`。entrypoint 负责 `--profile`、`--no-open`、`--host`、
  `--port`；不要重复 `--profile`（launcher 只接受一次），`--host`/`--port` 等普通
  选项重复时以后面的值为准。
- `dsh.agents.home` 默认 `/home/dsh/.agents`，映射到 `DSH_AGENTS_HOME`；
  `dsh.agents.persistent`（默认 `true`）控制它是否作为 PVC 的 `agents` subPath。
- `serviceAccount.automount` 默认 `false`：harness 不需要 Kubernetes API，而它的
  bash 工具能执行任意命令。确实要让 agent 操作集群时再显式打开并配 RBAC。
- `resources` 默认空；DSH 跑模型工具链时内存占用不低，建议至少给
  `requests.cpu`/`memory`，按使用量设 limits。
- 不支持 `replicaCount > 1` 或 HPA：每个 dsh 进程有自己的 cookie 签名密钥、插件目录
  和会话库，多副本会变成多个互不相通的状态。chart 在渲染阶段直接报错。

## 镜像

```bash
make images.deepseek-harness          # tag = Chart.yaml appVersion，推 amd64+arm64
make images.deepseek-harness TAG=...  # 只覆盖 tag，通常不需要
```

镜像内容：

- `node:24.22.3-bookworm-slim`；
- 官方 npm 包 `@deepseek-ai/dsh@0.2.2-rc.5` + `pnpm@10.34.9`（`dsh plugin` 依赖
  外部 pnpm）；
- `git`、`curl`、`ca-certificates`、`tini`；
- 非 root uid/gid `10001`，`HOME=/home/dsh`，`DSH_HOME=/home/dsh/.dsh`，
  `DSH_AGENTS_HOME=/home/dsh/.agents`，`WORKDIR=/workspace`。

npm 11 默认会拦截依赖的 install script（`node-pty`、`koffi`、
`dsh-subprocess-local` 等）。Dockerfile 在 builder 阶段对 pinned 的官方包使用
`--dangerously-allow-all-scripts`，否则 PTY/原生 helper 可能缺失；这段只发生在构建
阶段，runtime 不执行任何安装脚本。

要更多工具（Python、编译链、ssh 客户端等）就在 `image/Dockerfile` 里加；改完仍然
要在同一个 commit 里 bump `Chart.yaml` 的 `version`（chart-releaser 会把 image/...
截断回 chart 目录来判断变更），只改镜像内容不需要改 `appVersion`，但需要清理节点上
同 tag 的旧镜像缓存（见仓库 README）。

升级 dsh 版本时要一起改三处：

1. `image/Dockerfile` 的 `DSH_VERSION`；
2. `Chart.yaml` 的 `appVersion`（镜像 tag 跟它走）；
3. `Chart.yaml` 的 `version`（chart 发布版本）。

npm 镜像慢可以在本地构建时覆盖 `NPM_REGISTRY`：

```bash
docker buildx build \
  --build-arg NPM_REGISTRY=https://registry.npmmirror.com/ \
  -f charts/deepseek-harness/image/Dockerfile \
  -t docker.io/eslizn/deepseek-harness:0.2.2-rc.5 \
  charts/deepseek-harness/image
```

`make images.deepseek-harness` 走的是同一个 Dockerfile 默认值，但 Makefile 目标没有
透传 build-arg；需要换 registry 时用上面的命令手动构建。

## 限制与风险

- **Developer preview**：0.2.2-rc.5 是预发布版本，上游明确会有 breaking change；
  升级前先看上游 release note。
- **单副本**：见上。多副本、HPA 会 render 失败。
- **TLS 在 Ingress 终止时 cookie 不带 `Secure`**：dsh 的 cookie 只根据它自己的监听
  协议决定 `Secure`，而容器内是 HTTP。HTTPS 经过 Ingress 仍然可用，只是 cookie
  少了这一层属性；不要在不可信网络上直接暴露 HTTP。
- **token 在日志里**：能读 Pod 日志的人可以换取 UI cookie；请限制日志访问。
- **Ingress 端口本身没有认证**：dsh 的 token 保护 UI/API，不保护监听端口。务必用
  TLS + 网络策略/外部认证限制来源。
- **沙箱依赖内核/运行时**：见 `dsh.permissionMode` 一节。
- **PVC 保留**：`persistence.keep=true`（默认）时，`helm uninstall` 不删除 PVC，
  这是有意的数据保护；确认不再需要后再手动删除。设 `keep=false` 可让 Helm 随 release
  删除 PVC。
- **PVC 扩容**：`persistence.size` 会更新已有 PVC 的 request，但 StorageClass 必须
  支持扩容，且 Kubernetes 不支持缩容。

# PicoClaw Helm Chart

[PicoClaw](https://github.com/sipeed/picoclaw) 是 Sipeed 用 Go 写的超轻量个人 AI 助手
（宣称 $10 硬件、<10MB 内存即可运行）。本 chart 部署官方 **launcher** 镜像，一个 Pod
里同时跑 Web 控制台与网关：

| 组件 | 容器端口 | Service | 说明 |
|------|---------|---------|------|
| Web 控制台 | 18800 | `<release>` | 浏览器里配置 Provider / Channel、启停网关 |
| 网关 | 18790 | `<release>-gateway` | 渠道连接与 `/health` 健康端点 |

镜像来自 `docker.io/sipeed/picoclaw`，上游每个版本同时发布 `<版本>` 与
`<版本>-launcher` 两个 tag，本 chart 默认用后者（`image.tag` 可改）。

共享的 values 结构（`image`、`service`、`workload`、`persistence`、`ingress`、
`resources` 等）见[仓库根 README](../../README.md#values-schema)，本文件只列本 chart
专属的部分。

## 安装

```bash
helm repo add eslizn https://eslizn.github.io/helm-charts
helm install picoclaw eslizn/picoclaw -n picoclaw --create-namespace
```

## 本 chart 专属参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `image.tag` | `v0.3.1-launcher` | 换成 `v0.3.1` 是纯网关/agent 镜像，行为不同，见下方「运行模式」 |
| `gateway.host` | `0.0.0.0` | 网关绑定地址。launcher 默认绑 127.0.0.1，那样 `<release>-gateway` 就不可达，所以由 chart 注入 `PICOCLAW_GATEWAY_HOST` |
| `launcher.token` | 空 | 控制台固定 token。留空则每次启动随机生成并打印到日志（每次重启地址都会变） |
| `launcher.existingSecret` / `tokenKey` | 空 / `token` | 用已有 Secret 提供 token，而不是写在 values 里 |
| `config.create` | `false` | 由 values 渲染一个装着 `config.json` 的 Secret |
| `config.existingSecret` / `key` | 空 / `config.json` | 挂载已有 Secret 里的配置 |
| `config.data` | `{}` | `config.create=true` 时渲染成 `config.json` 的内容 |
| `persistence.enabled` / `size` / `mountPath` | `true` / `1Gi` / `/root/.picoclaw` | 数据目录，见下 |

## config.json 的三种给法

1. **UI 优先（默认）**：不挂任何配置，浏览器里填 Provider/Channel，结果写到 PVC 上的
   `/root/.picoclaw/config.json`。最省事，代价是配置不在 Git 里。
2. **chart 渲染**：`config.create=true` + `config.data`（对象，渲染成 JSON），chart 建一个
   Secret 并以 subPath 挂到 `<mountPath>/config.json`。注意 API key 会明文出现在 values 里。
3. **已有 Secret**：`config.existingSecret=<名字>`，自己用 sealed-secrets / External Secrets 管理。

后两种同时适用于持久化关闭的场景（配置仍会挂进去，只是 workspace 变成临时的）。

注意：挂载进来的 `config.json` 是**只读**的，会遮住 PVC 上同名文件。因此用第 2/3 种方式时，
Web 控制台里改配置无法落盘保存 —— 此时 values/Secret 才是配置的唯一来源，要改配置就改
values 后 `helm upgrade`。

## 数据目录

`persistence.mountPath`（默认 `/root/.picoclaw`）里是 `config.json`、agent `workspace/`、
`.security.yml` 与会话状态，所以默认开启持久化（1Gi）。`persistence.enabled=false` 时
这些内容随 Pod 消失。

## 探针

默认**不启用**存活/就绪探针。上游镜像自带的 HEALTHCHECK 是
`wget --spider http://localhost:18790/health`，可以在 values 里接上：

```yaml
workload:
  livenessProbe:
    httpGet: {path: /health, port: gateway}
    initialDelaySeconds: 10
  readinessProbe:
    httpGet: {path: /health, port: gateway}
```

之所以不默认打开：无法在没有集群的情况下确认网关在「尚未配置任何 provider」时也会
监听 18790，若不会监听，默认探针会让 Pod 陷入重启循环。你部署后可以先确认
`kubectl exec ... -- wget -qO- localhost:18790/health` 是否成功，再决定是否启用。

## 运行模式

默认是 launcher（Web UI + 网关）。若要用纯网关模式，把 `image.tag` 换成 `v0.3.1`：
该镜像的 entrypoint 在 `config.json` 与 `workspace/` 都不存在时会执行 `picoclaw onboard`
然后**退出**（k8s 里表现为反复重启），因此必须同时用上面的第 2 或第 3 种方式提供
`config.json`。

## 已知限制

- 上游自述处于早期快速迭代、v1.0 前不建议生产使用；本 chart 只是把它包装成 k8s 资源。
- 镜像以 root 运行并写入 `/root/.picoclaw`，因此 `securityContext` 默认为空，未做非 root 改造。
- 持久化用 RWO 卷 + 单副本：`replicaCount > 1` 会因卷争用失败，除非改成 RWX 并接受多实例共享状态。
- Helm test 只检查网关的 `/health`；控制台页面需要 token，不适合做无凭据探测。

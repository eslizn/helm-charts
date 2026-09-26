# OpenClaw Helm Chart

以 StatefulSet 部署 OpenClaw 网关，镜像来自自建仓库 `docker.io/eslizn/openclaw`。

共享的 values 结构（`image`、`service`、`workload`、`persistence`、`ingress`、
`resources` 等）见[仓库根 README](../../README.md#values-schema)，本文件只列本
chart 专属的部分。

## 安装

```bash
helm repo add eslizn https://eslizn.github.io/helm-charts
helm install openclaw eslizn/openclaw -n openclaw --create-namespace
```

## 主要参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `image.repository` / `image.tag` | `docker.io/eslizn/openclaw` / `latest` | 自建镜像 |
| `workload.kind` | `StatefulSet` | 工作负载类型 |
| `workload.serviceName` | 空（回退到 fullname） | StatefulSet 的 governing service，即主 Service 名 |
| `workload.podManagementPolicy` | `OrderedReady` | Pod 管理策略 |
| `workload.updateStrategy.type` | `RollingUpdate` | 更新策略 |
| `service.main.port` / `targetPort` | `80` / `18789` | 主 Service，容器监听 18789 |
| `ingress.enabled` | `true` | 默认开启 Traefik Ingress（`openclaw.local`） |
| `persistence.enabled` | `true` | 为 `/root` 创建 10Gi 的 volumeClaimTemplate |

容器固定设置 `OPENCLAW_GATEWAY_BIND=lan`。默认未配置 liveness/readiness 探针，
需要时通过 `workload.livenessProbe` / `workload.readinessProbe` 添加。

## 升级注意

`spec.serviceName` 与 `spec.volumeClaimTemplates` 是 StatefulSet 的不可变字段。
从 0.1.x 升级到 0.2.0（serviceName 由固定字符串 `openclaw` 改为 release 相关名称）
需要重建 StatefulSet，例如：

```bash
kubectl delete statefulset --cascade=orphan openclaw
helm upgrade openclaw eslizn/openclaw -n openclaw
```

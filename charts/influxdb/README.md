# InfluxDB Helm Chart

以 StatefulSet 部署 InfluxDB 3 Core（`influxdb:3-core`），并可选择同时部署
InfluxDB 3 Explorer UI。

共享的 values 结构（`image`、`service`、`workload`、`persistence`、`ingress`、
`resources` 等）见[仓库根 README](../../README.md#values-schema)。

## 安装

```bash
helm repo add eslizn https://eslizn.github.io/helm-charts

# 仅 InfluxDB 3 Core
helm install influxdb eslizn/influxdb -n influxdb --create-namespace

# 同时部署 Explorer UI
helm install influxdb eslizn/influxdb -n influxdb --create-namespace --set explorer.enabled=true
```

## InfluxDB 3 Core

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `image.repository` / `image.tag` | `influxdb` / `3-core` | |
| `workload.command` | `[influxdb3]` | 入口命令，args 由 chart 生成 |
| `service.main` | ClusterIP `80` → `8181` | 对外服务，名称为 fullname |
| `service.headless` | headless `80` → `8181` | StatefulSet 的 governing service |
| `persistence.enabled` | `false` | 关闭时数据目录用 emptyDir，Pod 重建即丢失 |
| `persistence.mountPath` | `/data` | 开启后数据落在 `<mountPath>/influxdb`、插件落在 `<mountPath>/plugins` |

开启持久化后容器 args 会追加
`--object-store=file --data-dir=<mountPath>/influxdb --plugin-dir=<mountPath>/plugins`。

## InfluxDB 3 Explorer（`explorer`）

Explorer 是同一 chart 内的第二个组件，带自己的 selector
（`app.kubernetes.io/component=explorer`），因此有独立的一套参数：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `explorer.enabled` | `false` | 是否部署 Explorer |
| `explorer.image` | `influxdata/influxdb3-ui:latest` | |
| `explorer.service` | ClusterIP `80` → `80` | Service 名为 `<fullname>-explorer` |
| `explorer.persistence.enabled` | `true` | 两个 claim：`data`（`/db`）与 `config`（`/app-root/config`，32Mi） |
| `explorer.ingress` | 关闭 | 结构同顶层 `ingress` |

Explorer 的 StatefulSet/Service/Ingress 由 chart 内模板渲染（`templates/explorer-*.yaml`），
没有走 `charts/common`：公共库每个 chart 只渲染一个组件，两个组件需要各自独立的
selector。

## 从 1.x 升级

1.x 的 `influxdb` 与 `influxdb-explorer` 是两个独立 chart，2.0.0 起合并为一个。
两者的 selector 都由 `app: <fullname>` 改为标准的 `app.kubernetes.io/*` 标签，
StatefulSet 的 `spec.selector` 不可变，升级已有 release 需要重建：

```bash
kubectl delete statefulset --cascade=orphan <release>-influxdb
helm upgrade <release> eslizn/influxdb -n <namespace>
```

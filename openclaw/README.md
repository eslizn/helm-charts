# OpenClaw Helm Chart

OpenClaw是一个基于Kubernetes的应用程序，使用Helm chart进行部署。本chart提供了一个完整的部署方案，支持StatefulSet、持久化存储和Ingress访问。

## 功能特性

- **StatefulSet部署**：确保Pod的有序部署和稳定的网络标识
- **持久化存储**：支持数据持久化，防止数据丢失
- **Ingress支持**：内置Traefik Ingress配置
- **健康检查**：包含liveness和readiness探针
- **资源管理**：可配置CPU和内存资源限制
- **自动扩缩容**：支持HPA自动扩缩容配置

## 前置要求

- Kubernetes 1.19+
- Helm 3.2.0+
- 持久化存储类（如果启用持久化存储）

## 安装

### 添加仓库

```bash
helm repo add my-repo https://charts.example.com/
helm repo update
```

### 安装chart

使用默认配置安装：

```bash
helm install openclaw my-repo/openclaw
```

使用自定义values文件安装：

```bash
helm install openclaw my-repo/openclaw -f values.yaml
```

## 配置参数

### 基本配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `replicaCount` | Pod副本数量 | `1` |
| `image.repository` | 容器镜像仓库 | `docker.io/alpine/openclaw` |
| `image.pullPolicy` | 镜像拉取策略 | `Always` |
| `image.tag` | 镜像标签 | `latest` |

### 服务配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `service.type` | 服务类型 | `ClusterIP` |
| `service.port` | 服务端口 | `80` |
| `service.targetPort` | 容器端口 | `18789` |

### Ingress配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `ingress.enabled` | 是否启用Ingress | `true` |
| `ingress.className` | Ingress类名 | `traefik` |
| `ingress.hosts[0].host` | 域名 | `openclaw.local` |

### 持久化存储配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `persistence.enabled` | 是否启用持久化存储 | `true` |
| `persistence.storageClass` | 存储类名 | `""`（使用默认） |
| `persistence.accessModes` | 访问模式 | `[ReadWriteOnce]` |
| `persistence.size` | 存储大小 | `10Gi` |
| `persistence.mountPath` | 挂载路径 | `/home/node/.openclaw` |

### 资源限制

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `resources.requests.cpu` | CPU请求 | `500m` |
| `resources.requests.memory` | 内存请求 | `1Gi` |
| `resources.limits.cpu` | CPU限制 | `4` |
| `resources.limits.memory` | 内存限制 | `16Gi` |

### 健康检查

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `livenessProbe.httpGet.path` | 存活检查路径 | `/` |
| `livenessProbe.httpGet.port` | 存活检查端口 | `18789` |
| `readinessProbe.httpGet.path` | 就绪检查路径 | `/` |
| `readinessProbe.httpGet.port` | 就绪检查端口 | `18789` |

## 自定义配置示例

### 使用自定义values文件

创建`custom-values.yaml`文件：

```yaml
replicaCount: 2

image:
  repository: my-registry/openclaw
  tag: v1.0.0

service:
  type: LoadBalancer

persistence:
  size: 20Gi
  storageClass: "fast-ssd"

resources:
  requests:
    cpu: "1"
    memory: 2Gi
  limits:
    cpu: "2"
    memory: 4Gi
```

安装时使用自定义配置：

```bash
helm install openclaw my-repo/openclaw -f custom-values.yaml
```

### 命令行参数覆盖

```bash
helm install openclaw my-repo/openclaw \
  --set replicaCount=3 \
  --set image.tag=v1.2.0 \
  --set persistence.size=50Gi
```

## 访问应用

### 通过Ingress访问

如果启用了Ingress，可以通过配置的域名访问：

```bash
# 默认域名
http://openclaw.local
```

### 通过端口转发访问

```bash
# 获取Pod名称
kubectl get pods -l app.kubernetes.io/name=openclaw

# 端口转发
kubectl port-forward <pod-name> 8080:18789
```

然后在浏览器中访问：`http://localhost:8080`

### 通过服务访问

如果服务类型为LoadBalancer或NodePort：

```bash
# 获取服务信息
kubectl get svc openclaw
```

## 升级和卸载

### 升级chart

```bash
helm upgrade openclaw my-repo/openclaw
```

### 卸载chart

```bash
helm uninstall openclaw
```

## 故障排除

### 查看Pod状态

```bash
kubectl get pods -l app.kubernetes.io/name=openclaw
```

### 查看Pod日志

```bash
kubectl logs <pod-name>
```

### 查看服务状态

```bash
kubectl get svc openclaw
```

### 查看Ingress状态

```bash
kubectl get ingress openclaw
```

## 支持

如有问题或需要帮助，请参考：

- [Kubernetes文档](https://kubernetes.io/docs/)
- [Helm文档](https://helm.sh/docs/)

## 许可证

本项目采用标准开源许可证。
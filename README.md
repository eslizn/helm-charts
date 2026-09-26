# helm-charts

Personal Helm charts, published to GitHub Pages by [chart-releaser](https://github.com/helm/chart-releaser).

## Usage

```bash
helm repo add eslizn https://eslizn.github.io/helm-charts
helm repo update
helm search repo eslizn
```

```bash
helm install my-release eslizn/<chart> -n <namespace> --create-namespace -f my-values.yaml
```

## Charts

| Chart | Version | Description |
|-------|---------|-------------|
| [aktools](charts/aktools) | 0.2.0 | AKTools - HTTP API for A-share market data |
| [influxdb](charts/influxdb) | 2.0.0 | InfluxDB 3 Core with the optional InfluxDB 3 Explorer UI |
| [mindsdb](charts/mindsdb) | 2.0.0 | MindsDB - AI layer over your database |
| [octopus](charts/octopus) | 0.1.0 | Octopus service |
| [openclaw](charts/openclaw) | 0.2.0 | OpenClaw gateway |
| [s3](charts/s3) | 2.0.0 | CSI driver for S3-backed volumes |
| [shadowsocks](charts/shadowsocks) | 2.0.0 | shadowsocks-libev server |
| [shadowsocks-rust](charts/shadowsocks-rust) | 0.2.0 | shadowsocks-rust server |
| [xtls](charts/xtls) | 2.0.0 | Xray-core VLESS/REALITY proxy |

`charts/common` is a library chart (not installable): it holds the shared named
templates every chart includes.

## Layout

```
charts/
  common/            library chart: all shared named templates
  <chart>/           one directory per chart
    Chart.yaml       declares a file:// dependency on ../common
    values.yaml      unified schema + chart specific values
    templates/       thin shells calling the common templates
```

## Values schema

Every chart exposes the same top level keys, so a values file that works for one
chart transfers to the others. What changes per chart is the app specific
sections (`shadowsocks.*`, `kcptun.*`, `s3.*`, `xtls.options`, `mindsdb.*`,
`explorer.*`).

```yaml
replicaCount: 1
image: {repository, tag, pullPolicy}   # tag falls back to Chart.yaml appVersion
imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount: {create, automount, annotations, name}
podAnnotations: {}
podLabels: {}
podSecurityContext: {}
securityContext: {}
resources: {}
autoscaling: {enabled, minReplicas, maxReplicas, targetCPUUtilizationPercentage}
nodeSelector: {}
tolerations: []
affinity: {}

# Container level configuration
workload:
  kind: Deployment|StatefulSet|DaemonSet
  command: []          # entrypoint override
  args: []
  env: []              # raw EnvVar list
  envFrom: []
  ports: [{name, containerPort, protocol, hostPort}]
  livenessProbe: {}
  readinessProbe: {}
  volumes: []          # extra volumes
  volumeMounts: []     # extra mounts
  initContainers: []   # raw container list
  extraContainers: []  # raw container list (sidecars)
  dnsPolicy: ""
  runtimeClassName: ""

# Named services: "main" renders as <fullname>, other keys as <fullname>-<key>
service:
  main: {enabled, type, port, targetPort, portName, protocol, nodePort, headless, annotations, labels, ports, extraPorts}

ingress: {enabled, className, annotations, hosts, tls, service, port}

persistence:           # Deployment/DaemonSet mount a PVC; StatefulSet renders a claim template
  {enabled, storageClass, accessModes, size, mountPath, subPath, existingClaim, create, volumeName}
```

Charts that derive ports or configuration from their own values (for example
`shadowsocks-rust.servers`) compute them in the chart's template and pass them to
the common template as overrides:

```gotemplate
{{- include "common.deployment" (dict "ctx" $ "ports" $ports "env" $env) }}
```

## Local development

```bash
helm dependency build charts/<chart>      # vendor charts/common into the chart
helm lint charts/<chart> --strict
helm template test charts/<chart>
```

The vendored `charts/<chart>/charts/*.tgz` is gitignored: run
`helm dependency build` before linting or packaging a chart.

## Releasing

`chart-releaser` publishes a chart when its `Chart.yaml` version changes on
`master`:

1. change the chart and bump `version` (breaking change -> major, otherwise patch),
2. commit and push to `master` (the `Release Charts` workflow packages every
   chart, uploads the new versions, and updates the `gh-pages` index).

The `Lint Charts` workflow runs `helm lint --strict`, `helm template` and
`helm package` on every push and pull request.

## Version history notes

- **2026-09** - all charts moved into `charts/` and onto the shared
  `charts/common` library; `service` became a named-service map, `persistent`
  was renamed to `persistence`, and the `helm create` placeholder `appVersion`
  was dropped. This is a breaking values change for every chart (major version
  bump). Upgrading an existing release may require recreating immutable fields
  (`spec.selector` on the influxdb StatefulSet, `spec.serviceName` on openclaw).
- **2026-09** - `influxdb-explorer` was merged into `influxdb` as the optional
  `explorer.enabled` component, and `postgres` was removed from the repository
  (its already published versions stay installable from the repository index).

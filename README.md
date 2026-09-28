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

| Chart | Version | App version | Description |
|-------|---------|-------------|-------------|
| [aktools](charts/aktools) | 0.2.1 | 0.0.91 | AKTools - HTTP API for A-share market data |
| [mindsdb](charts/mindsdb) | 2.0.2 | v26.1.0 | MindsDB - AI layer over your database |
| [node-red](charts/node-red) | 0.1.1 | 5.0.7-24 | Node-RED - low-code programming for event-driven applications |
| [shadowsocks](charts/shadowsocks) | 2.0.1 | v3.3.5 | shadowsocks-libev server |
| [shadowsocks-rust](charts/shadowsocks-rust) | 0.2.1 | v1.25.0 | shadowsocks-rust server |
| [xtls](charts/xtls) | 2.0.1 | 26.3.27 | Xray-core VLESS/REALITY proxy |

`Version` is the chart artifact version (bumped on every chart change, the
number `chart-releaser` publishes under), `App version` is the upstream release
the chart deploys - it is the image tag the chart pins, so the two only move
together when a release changes both.

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
sections (`shadowsocks.*`, `kcptun.*`, `xtls.options`, `mindsdb.*`,
`nodeRed.*`).

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

- **2026-09-29** - `mindsdb` 2.0.2: the chart now appends its own environment
  variables (the persistence `MINDSDB_STORAGE_DIR`/`MINDSDB_CONFIG_FILE` pair and
  the `nvidia` runtime class ones) to `workload.env` instead of building that
  list from scratch. Passing `env` to `common.deployment` replaces the values'
  list entirely, so until 2.0.1 anything set in `workload.env` was silently
  dropped whenever persistence was enabled - `MINDSDB_USERNAME`/`MINDSDB_PASSWORD`
  included, which left the HTTP API unauthenticated while it was exposed.
- **2026-09** - all charts moved into `charts/` and onto the shared
  `charts/common` library; `service` became a named-service map, `persistent`
  was renamed to `persistence`, and the `helm create` placeholder `appVersion`
  was dropped. This is a breaking values change for every chart (major version
  bump). Upgrading an existing release may require recreating immutable fields
  (for example `spec.selector` on the influxdb StatefulSet).
- **2026-09** - `influxdb-explorer` was merged into `influxdb` as the optional
  `explorer.enabled` component, and `postgres` was removed from the repository
  (its already published versions stay installable from the repository index).
- **2026-09** - `octopus`, `openclaw` and `picoclaw` were removed from the
  repository (their already published versions stay installable from the
  repository index).
- **2026-09** - `influxdb` and `s3` were removed in favour of the charts their
  vendors publish: `influxdata/influxdb3-core` (InfluxDB 3 Core only - the
  Explorer UI has no official chart) and `csi-s3` from
  `https://yandex-cloud.github.io/k8s-csi-s3/charts`. Where a chart stays, its
  `appVersion` now tracks the upstream release and `image.tag` is pinned to the
  matching image tag instead of `latest`/`3-core`. `aktools` publishes to PyPI
  only, so its image is built from the upstream Dockerfile with the same version
  pinned and pushed to `eslizn/aktools` (build command in the chart values).

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
| [aktools](charts/aktools) | 0.2.6 | 0.1.7 | AKTools - HTTP API for A-share market data |
| [futuopend](charts/futuopend) | 0.1.2 | 10.12.7208 | Futu OpenD - Futu OpenAPI gateway, one instance per account |
| [mindsdb](charts/mindsdb) | 2.0.3 | v26.1.0 | MindsDB - AI layer over your database |
| [node-red](charts/node-red) | 0.1.3 | 5.0.9-24 | Node-RED - low-code programming for event-driven applications |
| [shadowsocks](charts/shadowsocks) | 2.0.2 | v3.3.5 | shadowsocks-libev server |
| [shadowsocks-rust](charts/shadowsocks-rust) | 0.2.2 | v1.25.0 | shadowsocks-rust server |
| [xtls](charts/xtls) | 2.0.4 | 26.11.9 | Xray-core VLESS/REALITY proxy |

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
    image/           build context, only where the chart builds its own image
```

`Makefile` at the repository root is the entry point for those builds.

## Values schema

Every chart exposes the same top level keys, so a values file that works for one
chart transfers to the others. What changes per chart is the app specific
sections (`shadowsocks.*`, `kcptun.*`, `xtls.options`, `xtls.origin`,
`mindsdb.*`, `nodeRed.*`, `futuopend.*`) plus, for a chart that runs one
instance per item rather than one per release, the list that drives it -
`futuopend.accounts` renders one Deployment/Service/PVC/Secret set per account.

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

## Building images

Most charts run an upstream image and build nothing. A chart that ships a
self-built image keeps its build context in `charts/<chart>/image/` and is built
from the repository root:

```bash
make images.<chart>             # tag defaults to the chart's appVersion
make images.<chart> TAG=<tag>   # override the tag
```

The tag has to match the chart's `Chart.yaml` `appVersion`: `image.tag` is
empty in `values.yaml` and `common.imageRef` falls back to `appVersion`. Both
platforms are built (`linux/amd64,linux/arm64`) because the cluster is amd64 +
arm64 mixed. A chart whose upstream artifact exists for one architecture only
overrides that per chart - `PLATFORMS.futuopend := linux/amd64` in the
`Makefile`, because Futu ships the OpenD binary for x86-64 only and an arm64
variant would be an amd64 binary under an arm64 label, failing with `exec
format error` on an arm64 node. `charts/<chart>/.helmignore` has to exclude
`image/`, or `helm package` ships the build context inside the released chart.

Pushing over a tag that is already deployed rolls nothing: the rendered
manifest is unchanged, so Argo CD sees no diff, and a node that cached the old
image under that tag will not pull again under `IfNotPresent`. After such a
push, drop the cached image on every node running it, then delete the Pod so it
is recreated and re-pulls:

```bash
kubectl debug node/<node> -it --image=busybox
# inside the debug container the host root is mounted at /host
chroot /host crictl rmi docker.io/eslizn/<image>:<tag>
```

The `Build Images` workflow runs this same target in CI on every push to
`master` that touches `charts/*/image/**`, one job per changed chart; a rebuild
with nothing changed under `image/` is started by hand with `workflow_dispatch`.
It needs the `DOCKERHUB_USERNAME` and `DOCKERHUB_PASSWORD` repository secrets.
The password field takes the account password or a personal access token;
Docker Hub rejects the account password when the account has 2FA enabled or the
organization enforces SSO, and a token is scoped and revocable where the
password is not - use a token in either case.

An image-only change still counts as a chart change to chart-releaser: it
truncates anything under `charts/<chart>/image/` to `charts/<chart>` when
deciding what to package, so the release workflow would rebuild the current
version and try to publish it again, which GitHub rejects. Bump `Chart.yaml`
`version` in the same commit as any change under `image/`.

`charts/aktools` and `charts/futuopend` are the charts that build an image
today. Both are built from an upstream artifact rather than from source:
`aktools` from PyPI, `futuopend` from Futu's download CDN, which needs no
credentials (the OpenD tarball is a public bucket) but is reachable only from
wherever Futu's CDN answers - if a CI runner cannot fetch it, build that image
locally with the same `make images.futuopend` target.

## Releasing

`chart-releaser` publishes a chart when its `Chart.yaml` version changes on
`master`:

1. change the chart and bump `version` (breaking change -> major, otherwise patch),
2. commit and push to `master` (the `Release Charts` workflow packages every
   chart, uploads the new versions, and updates the `gh-pages` index).

The `Lint Charts` workflow runs `helm lint --strict`, `helm template` and
`helm package` on every push and pull request; `Build Images` builds and pushes
the image of every chart whose `charts/*/image/**` changed. Those two run in
parallel, so an image change and its version bump landing in the same commit
can publish the chart a moment before the image it pins exists - a pull inside
that window fails and is retried by the kubelet.

## Version history notes

- **2026-11-13** - `pgone` removed from the repository (its already published
  versions stay installable from the repository index).
- **2026-11-13** - `xtls` 2.0.4: appVersion 26.3.27 -> 26.11.9 (2026-11-09).
  This spans two upstream emergency security releases: 26.10.21 removes three
  compromised root CAs and builds with Go 1.27.3; 26.10.31 disables MPTCP by
  default because of a Linux kernel IPv4 MPTCP privilege-escalation
  vulnerability. The chart's VLESS/REALITY config is unchanged: VLESS
  `settings.clients` is still accepted as an alias for `users`, the REALITY
  fields and `sockopt.acceptProxyProtocol` are unchanged, and the removed TLS
  fields (`allowInsecure`, `verifyPeerCertInNames`, `echForceQuery`) are not
  used here. 26.11.9 also adds XDRIVE transport, MASQUE, Hysteria v2 and
  Finalmask updates. Two defaults worth knowing: the uTLS fingerprint is now
  Chrome 155 (client side), and REALITY's `minClientVer` defaults to 26.3.27
  when unset - this chart leaves it empty, so no client is refused. The chart
  also now passes `-config /etc/xray/config.json` by default: the upstream
  image's CMD is `-confdir /usr/local/etc/xray/`, so the Secret mounted at
  `/etc/xray/` was previously never read unless the release set
  `workload.args` itself. A user-supplied `workload.args` still replaces the
  default list.
- **2026-11-13** - `aktools` 0.2.6: appVersion 0.0.91 -> 0.1.7. The image is
  rebuilt on python:3.14-slim-trixie, runs as uid 1000, and uses gunicorn with
  `uvicorn_worker.UvicornWorker`; `requirements.txt` is a fresh freeze
  (akshare 1.20.40, starlette 1.10.0, mcp 2.3.0). 0.1.x adds the MCP endpoint
  (`/mcp`), an optional `AKTOOLS_TOKEN` for `/api/` and `/mcp`, result caching,
  proxy/timeout settings, an interface catalog with CSV/Excel download, and
  data-source annotations. Breaking: `/api/show` and `/api/show-temp` are gone
  (404), Python is now >= 3.11.5, `akshare` is >= 1.20.39, and `mcp` is a
  required dependency. The image sets `AKTOOLS_HOST=0.0.0.0`, so `/mcp` works
  through a Service/Ingress instead of only loopback.
- **2026-11-13** - `node-red` 0.1.3: appVersion 5.0.7-24 -> 5.0.9-24.
  Maintenance releases: 5.0.8 fixes legacy CSV parsing, a WebSocket connection
  leak on every deploy, a library save race and several editor issues; 5.0.9
  fixes a comms-auth crash when `adminAuth` is not set, filter node Date
  handling, CSV/BOM and MQTT connect issues, and adds editor improvements. No
  breaking changes are listed.
- **2026-11-13** - `futuopend` 0.1.2: appVersion 10.11.7108 -> 10.12.7208.
  Futu publishes no changelog for 10.11/10.12 (the official changelog stops at
  10.10.7008), so the change set is unknown; the 10.12.7208 tarball is dated
  2026-10-29. The rebuilt binary still carries `-login_pwd_md5` and
  `-login_by_remember`, but the login path has not been re-tested against a
  real account on 10.12.7208 - do that before rolling a trading instance.
- **2026-11-04** - `xtls` 2.0.3: the REALITY fallback origin becomes an
  optional nginx sidecar in the xray Pod (`origin.*`, default off), so the
  separate `xtls-origin` Deployment/Service and its two Pods go away. The
  sidecar is single-host: `origin.host` has no default (the release values
  name the domain), and the chart requires it to be the only REALITY
  `serverNames` entry and every REALITY inbound's `dest` to be
  `127.0.0.1:<origin.port>` (9443); it fails the render otherwise instead of
  shipping a fallback that never reaches nginx. That also removes the old
  `www.xbox.com` passthrough: there is no stream/SNI map, resolver or upstream
  list any more, nginx just terminates TLS on the origin port and returns a
  page. Clients that still send `www.xbox.com` as their serverName must switch
  to the single host - the Traefik `HostSNI` rules come from `serverNames`, so
  such traffic is no longer routed to xray at all.
  Details that matter at runtime:
  - the TLS Secret is mounted `optional: true`, and nginx loads the
    certificate through a variable path: the Pod starts before cert-manager has
    issued it (a missing required Secret would block the whole xray Pod in
    `ContainerCreating`), and a renewed Secret is picked up without a restart.
  - the sidecar deliberately has **no readinessProbe** - the main container has
    none either, so a not-ready origin would take the xray replica out of the
    Service endpoints. Its TCP liveness only restarts nginx when it stops
    listening.
  - `fsGroup: 101` is merged into the Pod `securityContext` (the Secret is
    0440 and nginx runs as 101); `origin.fsGroup` overrides it, an explicit
    value in `podSecurityContext` does not.
  - the Certificate is opt-out (`origin.certificate.enabled: false`) for a
    Secret managed elsewhere, named by `origin.tlsSecretName`.
  With a release named `xtls`, resource names stay `xtls-origin` /
  `xtls-origin-tls`, so the migration can keep the existing Certificate and
  ConfigMap: remove the old Application's
  `resources-finalizer.argocd.argoproj.io` finalizer, delete the Application
  (its resources stay behind), sync the new chart so it adopts them and rolls
  xray onto the sidecar, then delete the leftover origin Deployment and
  Service. Deleting the old Application with the finalizer first prunes the
  Certificate and Service and briefly drops the fallback; running both owners
  at once is not an option either. The deployment template also now appends
  `workload.volumes`/`volumeMounts`/`extraContainers` to the chart's own
  entries; before, passing the chart's lists replaced them, so any value set
  in those fields was silently dropped.
- **2026-10-16** - `xtls` 2.0.2 / `common` 0.1.2: the Traefik -> xray hop
  ignored the Service. Traefik resolves a CRD service's endpoints itself and
  dials the pod IPs, and only kube-proxy reads `internalTrafficPolicy` /
  `trafficDistribution` - so with a replica on ap-hk-1 and one on ap-seoul-1,
  a client entering through either node was served by the other one about two
  times out of three, paying for the slow upstream link (README section 6).
  `ingress.nativeLB` (new, default `true`) makes Traefik dial the ClusterIP, so
  kube-proxy picks the replica: `trafficDistribution: PreferSameNode` then keeps
  the hop on the node the entry runs on, and falls back to the other replica
  where a node has none (ap-sh-1) - `internalTrafficPolicy: Local` would drop
  those connections instead of falling back. `common` gained the
  `trafficDistribution` passthrough, which bumps the library for every chart
  that pins it.
- **2026-10-06** - `pgone` 0.1.3: the `IngressRouteTCP` named a TCP entrypoint
  the Traefik install does not have (`pgone-tcp`; the entrypoint in this
  cluster is `postgres`), so Traefik logged `EntryPoint doesn't exist` and
  dropped the router. The port was still listening, so what a client saw was
  the connection being accepted and closed during the SSLRequest/TLS
  exchange - "remote host terminated the handshake" - with nothing in the
  Application's sync status to suggest a routing problem. The default is now
  `postgres`.
- **2026-10-06** - `pgone` 0.1.2: the image tag is the floating `latest`, not
  `Chart.yaml`'s `appVersion` (which is now only the `app.kubernetes.io/version`
  label), and `pullPolicy` is `Always` to match - a floating tag with
  `IfNotPresent` would leave a node that already cached `latest` serving it,
  which is the staleness the floating tag exists to avoid. The chart had pinned
  a commit sha while the pgone repository's `Publish Image` workflow pushed a
  later commit under both its sha and `latest`, so the chart named an image
  nobody had pushed and the pod sat in `ImagePullBackOff` - a chart and an image
  that have to be re-pinned in step are a pair that drifts.
- **2026-10-05** - new `pgone` chart (a PostgreSQL wire protocol gateway). Three
  firsts for this repository: the image is built and pushed by the pgone
  repository's own `Publish Image` workflow, so `appVersion` tracks a pgone
  commit rather than an upstream release; TLS is *terminated* at Traefik rather
  than passed through (pgone answers every SSLRequest with "N" and speaks no
  TLS, and Traefik's PostgreSQL STARTTLS handling is what lets an ordinary
  `sslmode=require` client reach it); and the certificate is rendered by the
  chart as a `Certificate`, because pgone has no Ingress for cert-manager's
  ingress-shim to watch. It routes on a TCP entrypoint (`pgone-tcp`, 5432) that
  the Traefik install has to declare first.
- **2026-10-05** - new `futuopend` chart (Futu OpenD, the gateway for the Futu
  OpenAPI). It runs **one OpenD instance per account**, so unlike every other
  chart here the workload is driven by a list: each entry of `accounts` renders
  its own Deployment, Service, PVC and Secret, named `<release>-<chart>-<account>`.
  The common library names and labels from the release, so each account is
  rendered in a synthetic context whose `nameOverride`/`fullnameOverride` carry
  the account - that is what keeps the selectors apart, and without it every
  account's Service would select every account's Pod. No change to
  `charts/common` was needed, and no CRD: plain Deployments express this.
  Correctness details worth knowing:
  - the image is **amd64 only**, because Futu publishes no arm build (the
    download endpoint has no arm slot and the binary is `x86-64`). The Makefile
    gained a per-chart `PLATFORMS.<chart>` override for it. `nodeSelector`
    defaults to `kubernetes.io/arch: amd64` so a Pod cannot land on an arm64
    node and die with `exec format error`.
  - `strategy: Recreate` and `replicas: 1` are fixed, not defaulted. The state
    PVC is ReadWriteOnce and a rolling update would either multi-attach it or
    briefly run two logins of the same account; `replicaCount > 1` fails the
    render rather than being ignored. Futu allows one top-quote-rights terminal
    per account and kicks the other.
  - `persistence` defaults to **on**: `<mountPath>/F3CNN/Device.dat` is the
    device identity, and a fresh one re-triggers device-lock (SMS) verification
    and consumes the account's device allowance. It must not be shared between
    accounts.
  - credentials: OpenD 10.10 removed account/password from `FutuOpenD.xml`, but
    the CLI flags still work - verified against the 10.11.7108 binary, which
    accepts `-login_pwd_md5` (and rejects plaintext `-login_pwd`, so only the
    MD5 is ever handled) and logs it as a live setting. The 10.12.7208 binary
    still carries the parameter; re-test the login after the bump. It goes
    through a Secret into an env var that `args` reference, so it never appears
    in the Pod spec.
    `loginByRemember` covers the fallback where a session is bootstrapped by
    hand and reused from the PVC.
  - `telnetPort` is opt-in: it is the only way to answer a device-lock
    verification from inside the cluster, but it is plaintext and
    unauthenticated.
  - deliberately **not** exposed from the shared schema: `ingress` (the API is
    raw TCP carrying protobuf, not HTTP) and `autoscaling` (a second replica is
    a second login of the same account). Both are documented in `values.yaml`.
  - the probes are TCP connects, which prove the port is open and **not** that
    the login succeeded - a failed login still leaves the port listening. The
    real log is on the PVC at `<mountPath>/log/Log/`.
- **2026-10-04** - images are built and pushed by the `Build Images` workflow
  instead of by hand: on every push to `master` that touches
  `charts/*/image/**` it runs `make images.<chart>` (the same target as a local
  build) once per changed chart. The tag stays the chart's `appVersion` - an
  `<appVersion>-<rev>` scheme was tried in the same change and dropped again,
  because the revision only bought an automatic rollout for a rebuild under a
  tag that is already deployed, and that is not worth a tag which no longer
  names the upstream release. Such a rebuild therefore still needs the node
  image cache cleared by hand (the `## Building images` section above).
- **2026-09-29** - `aktools`: the image build is now version controlled. Its
  build context lives in `charts/aktools/image/` and is built with
  `make images.aktools` from the repository root, with every dependency pinned
  in `image/requirements.txt`. The upstream Dockerfile pins nothing, and that
  is what broke the homepage: `fastapi` declares only `starlette>=0.46.0`, so
  the image had resolved `starlette` 1.x, which dropped the
  `TemplateResponse(name, context)` signature that aktools 0.0.91 still calls -
  `GET /` answered HTTP 500. The image is rebuilt under the same `0.0.91` tag,
  so putting it into service means clearing the node image cache by hand; the
  `## Building images` section above explains why and how.
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
  pinned and pushed to `eslizn/aktools`.

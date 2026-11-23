# syntax=docker/dockerfile:1

# DeepSeek Harness (dsh). DeepSeek publishes no Docker image - the official
# installation is the npm package @deepseek-ai/dsh - so the image is built here
# from that package. The version is pinned in DSH_VERSION rather than following
# `latest` at build time: the image tag has to match Chart.yaml appVersion, and
# a chart that silently switched dsh version on rebuild would be worse than one
# that needs an explicit bump.
#
# Bumping dsh means bumping DSH_VERSION, Chart.yaml appVersion and Chart.yaml
# version together, in one commit. Any change here still has to bump version in
# Chart.yaml in the same commit - chart-releaser truncates image/... back to the
# chart directory when deciding what changed. See the repository README.
#
# Build and push with `make images.deepseek-harness` from the repository root
# (the tag is Chart.yaml appVersion); the Build Images workflow runs the same
# target on every push that touches this directory.

ARG NODE_VERSION=24.22.3
ARG DSH_VERSION=0.2.2-rc.5
ARG PNPM_VERSION=10.34.9

# The builder has the platform's native toolchain in case an optional prebuilt
# binary is unavailable for linux/amd64 or linux/arm64 and npm has to compile
# it. None of this reaches the runtime stage.
FROM node:${NODE_VERSION}-bookworm-slim AS dsh

ARG DSH_VERSION
ARG PNPM_VERSION
# Override for a network where npmjs.org is slow or unreachable.
ARG NPM_REGISTRY=https://registry.npmjs.org

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      python3 \
      make \
      g++ \
 && rm -rf /var/lib/apt/lists/*

# npm 11.19 blocks dependency install scripts unless they are approved. The
# official dsh package needs them: node-pty chmods its prebuilt spawn-helper,
# dsh-subprocess-local chmods node-pty's helper, and koffi/node-pty fall back to
# a local build when no prebuilt binary matches. This is the builder stage of a
# pinned, official package, so allowing those scripts is the intended install;
# without it the PTY-backed tools can be broken at runtime.
RUN npm install --prefix /opt/dsh --no-audit --no-fund \
      --dangerously-allow-all-scripts \
      --registry="${NPM_REGISTRY}" \
      "@deepseek-ai/dsh@${DSH_VERSION}" \
      "pnpm@${PNPM_VERSION}" \
 && /opt/dsh/node_modules/.bin/dsh --version

FROM node:${NODE_VERSION}-bookworm-slim

ARG DSH_VERSION

LABEL org.opencontainers.image.title="deepseek-harness" \
      org.opencontainers.image.description="DeepSeek Harness (dsh) Web UI - self-built from the official npm package" \
      org.opencontainers.image.version="${DSH_VERSION}" \
      org.opencontainers.image.source="https://github.com/eslizn/helm-charts"

# git and curl let the agent work on repositories and fetch things; tini is the
# PID 1 that forwards signals and reaps the port-forward proxy. The upstream
# npm install needs nothing else.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      tini \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid 10001 dsh \
 && useradd --uid 10001 --gid 10001 --create-home --home-dir /home/dsh \
      --shell /bin/bash dsh \
 && mkdir -p /home/dsh/.dsh /home/dsh/.agents /workspace \
 && chown -R 10001:10001 /home/dsh /workspace

COPY --from=dsh /opt/dsh /opt/dsh
COPY --chmod=0755 dsh-entrypoint.sh /usr/local/bin/dsh-entrypoint
COPY --chmod=0755 dsh-portproxy.mjs /usr/local/bin/dsh-portproxy.mjs

ENV PATH="/opt/dsh/node_modules/.bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    HOME=/home/dsh \
    DSH_HOME=/home/dsh/.dsh \
    DSH_WORKSPACE=/workspace \
    DSH_AGENTS_HOME=/home/dsh/.agents \
    LANG=C.UTF-8

USER 10001:10001
WORKDIR /workspace

EXPOSE 3080

# The chart passes its own args (they replace CMD), so this is only what a plain
# `docker run` needs. The entrypoint derives --profile web, --no-open, --host
# and --port; extra args are appended verbatim.
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/dsh-entrypoint"]

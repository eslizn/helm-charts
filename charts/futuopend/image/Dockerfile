# Futu OpenD. Futu ships no Docker image and no Helm chart - the official FAQ
# answers "OpenD 是否有提供 Docker 镜像?" with "目前没有提供" - so the image is
# built here from their published Linux tarball.
#
# The tarball is fetched from Futu's download CDN without any authentication,
# via the "latest" redirect (https://www.futunn.com/download/fetch-lasted-link
# ?name=opend-ubuntu) which currently resolves to
# Futu_OpenD_10.11.7108_Ubuntu18.04.tar.gz. The version is pinned in OPEND_VERSION
# below rather than following the redirect: the tag has to match Chart.yaml
# appVersion, and a chart that silently switched OpenD version on rebuild would
# be worse than one that needs a bump. Bumping OpenD means bumping OPEND_VERSION
# and Chart.yaml appVersion together, in one commit that also bumps version.
#
# amd64 only, and not by choice: Futu publishes no arm build for any Linux
# flavour (the download endpoint has no arm slot - opend-ubuntu-arm/arm64/
# aarch64 all redirect to /404) and the binary in the Ubuntu tarball is
# "ELF 64-bit LSB executable, x86-64". An arm64 image is only possible by
# emulating x86-64 under QEMU, which some community images do and which costs
# roughly 2-5x - not something to put in front of a trading gateway. The
# repository Makefile carries a PLATFORMS.futuopend override for this.
#
# Build and push with `make images.futuopend` from the repository root (the tag
# is Chart.yaml appVersion); the Build Images workflow runs the same target on
# every push that touches this directory. Any change here still has to bump
# version in Chart.yaml in the same commit - chart-releaser truncates image/...
# back to the chart directory when deciding what changed. See the README.

# The tarball is ~446 MB and carries two things: a 417 MB GUI AppImage and the
# ~63 MB command-line build. Only the latter is unpacked - the AppImage would
# more than quadruple the build for a GUI that cannot run in a container.
# Extracting just the CLI directory keeps it out without downloading less.
FROM debian:bookworm-slim AS fetch

ARG OPEND_VERSION=10.11.7108

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/opend.tar.gz \
      "https://softwaredownload.futunn.com/Futu_OpenD_${OPEND_VERSION}_Ubuntu18.04.tar.gz" \
 && mkdir -p /opt/futuopend \
 && tar -xzf /tmp/opend.tar.gz -C /opt/futuopend --strip-components=2 \
      "Futu_OpenD_${OPEND_VERSION}_Ubuntu18.04/Futu_OpenD_${OPEND_VERSION}_Ubuntu18.04" \
 && rm /tmp/opend.tar.gz \
 && test -x /opt/futuopend/FutuOpenD

# The binary is built for Ubuntu 18.04 (glibc 2.27), but its highest glibc
# requirement is GLIBC_2.14 and GLIBCXX_3.4.19, and it carries its own
# libssl.so.3 / libcrypto.so.3 / libcurl.so.4 / libprotobuf.so.32 next to the
# executable, found through an $ORIGIN RPATH. So it does not need Ubuntu 18.04 -
# any glibc-distro works. Debian bookworm is the smallest supported base that
# has the rest: libstdc++6 (GLIBCXX_3.4.19), zlib1g for libprotobuf, tzdata for
# the timezone settings, and ca-certificates for the bundled libcurl's TLS to
# Futu's servers. Alpine does not work: musl is not glibc.
FROM debian:bookworm-slim

ARG OPEND_VERSION=10.11.7108

LABEL org.opencontainers.image.title="futuopend" \
      org.opencontainers.image.description="Futu OpenD for linux/amd64 - one instance per Futu account" \
      org.opencontainers.image.version="${OPEND_VERSION}" \
      org.opencontainers.image.source="https://github.com/eslizn/helm-charts"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      libstdc++6 \
      tzdata \
      zlib1g \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid 10001 futuopend \
 && useradd --uid 10001 --gid 10001 --home-dir /data --no-create-home --shell /usr/sbin/nologin futuopend \
 && mkdir -p /data \
 && chown 10001:10001 /data

COPY --from=fetch --chown=10001:10001 /opt/futuopend /opt/futuopend
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

# Non-root: the daemon needs no capability and writes only to the state
# directory. /data exists in the image so the entrypoint can fall back to it
# when no volume is mounted (and so HOME is valid); with a volume the chart's
# podSecurityContext.fsGroup makes it writable for this user.
USER 10001:10001
WORKDIR /opt/futuopend
ENV HOME=/data

EXPOSE 11111

# The chart passes its own args (they replace CMD), so these are only what a
# plain `docker run` needs to behave inside a container.
CMD ["-console=0", "-no_monitor=1", "-api_ip=0.0.0.0", "-api_port=11111", "-data_dir=/data", "-log_path=/data/log"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

{{/*
Port name for a server entry: the explicit name, or "ss-<port>" otherwise.
*/}}
{{- define "shadowsocks-rust.portName" -}}
{{- if .name -}}
{{- .name -}}
{{- else -}}
{{- printf "ss-%d" (.server_port | int) -}}
{{- end -}}
{{- end -}}

{{/*
Port the probes should use: the first server entry that listens on TCP, or 0
when every entry is udp_only. ssserver in udp_only mode binds no TCP socket, so
a tcpSocket probe against it can never succeed.
Usage: include "shadowsocks-rust.probePort" .
*/}}
{{- define "shadowsocks-rust.probePort" -}}
{{- $port := 0 -}}
{{- range .Values.servers -}}
{{- if and (eq $port 0) (ne (default "tcp_only" .mode) "udp_only") -}}
{{- $port = .server_port -}}
{{- end -}}
{{- end -}}
{{- $port -}}
{{- end -}}

{{/*
Service port of the first server entry that serves TCP, or 0 when there is none.
Used by the Helm test, which cannot reach a udp_only server.
Usage: include "shadowsocks-rust.testPort" .
*/}}
{{- define "shadowsocks-rust.testPort" -}}
{{- $port := 0 -}}
{{- range .Values.servers -}}
{{- if and (eq $port 0) (ne (default "tcp_only" .mode) "udp_only") -}}
{{- $port = default .server_port .service_port -}}
{{- end -}}
{{- end -}}
{{- $port -}}
{{- end -}}

{{/*
Init container script that downloads the v2ray and xray plugins. Runs with
`sh -c` in the busybox image, i.e. ash, so `set -e` is the only error handling
available. The architecture is detected rather than hardcoded to amd64, and the
version can be pinned through .Values.pluginVersions (empty = newest release).

Usage: include "shadowsocks-rust.pluginDownloadScript" .
*/}}
{{- define "shadowsocks-rust.pluginDownloadScript" -}}
{{- $versions := .Values.pluginVersions | default dict -}}
set -e
arch=$(uname -m)
case "$arch" in
  x86_64) arch=amd64 ;;
  aarch64) arch=arm64 ;;
  armv7l) arch=armv7 ;;
  *) echo "no ss plugin build for architecture $arch" >&2; exit 1 ;;
esac
cd /tmp

v2ray_tag="{{ $versions.v2ray | default "" }}"
if [ -z "$v2ray_tag" ]; then
  v2ray_tag=$(wget -qO- https://api.github.com/repos/shadowsocks/v2ray-plugin/releases/latest | grep -m1 tag_name | cut -d '"' -f4)
fi
wget -O v2ray.tar.gz "https://github.com/shadowsocks/v2ray-plugin/releases/download/$v2ray_tag/v2ray-plugin-linux-$arch-$v2ray_tag.tar.gz"
tar -xzf v2ray.tar.gz
mv v2ray-plugin /usr/local/bin/v2ray-plugin
chmod +x /usr/local/bin/v2ray-plugin

xray_tag="{{ $versions.xray | default "" }}"
if [ -z "$xray_tag" ]; then
  xray_tag=$(wget -qO- https://api.github.com/repos/teddysun/xray-plugin/releases/latest | grep -m1 tag_name | cut -d '"' -f4)
fi
wget -O xray.tar.gz "https://github.com/teddysun/xray-plugin/releases/download/$xray_tag/xray-plugin-linux-$arch-$xray_tag.tar.gz"
tar -xzf xray.tar.gz
mv xray-plugin /usr/local/bin/xray-plugin
chmod +x /usr/local/bin/xray-plugin
{{- end -}}

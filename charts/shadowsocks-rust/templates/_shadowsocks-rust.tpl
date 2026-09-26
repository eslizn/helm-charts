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
Init container script that downloads the v2ray and xray plugins.
*/}}
{{- define "shadowsocks-rust.pluginDownloadScript" -}}
TAG=$(wget -qO- https://api.github.com/repos/shadowsocks/v2ray-plugin/releases/latest | grep tag_name | cut -d '"' -f4)
wget https://github.com/shadowsocks/v2ray-plugin/releases/download/$TAG/v2ray-plugin-linux-amd64-$TAG.tar.gz
tar -xf *.gz
rm *.gz
mv v2ray* /usr/local/bin/v2ray-plugin
chmod +x /usr/local/bin/v2ray-plugin

TAG=$(wget -qO- https://api.github.com/repos/teddysun/xray-plugin/releases/latest | grep tag_name | cut -d '"' -f4)
wget https://github.com/teddysun/xray-plugin/releases/download/$TAG/xray-plugin-linux-amd64-$TAG.tar.gz
tar -xf *.gz
rm *.gz
mv xray* /usr/local/bin/xray-plugin
chmod +x /usr/local/bin/xray-plugin
{{- end -}}

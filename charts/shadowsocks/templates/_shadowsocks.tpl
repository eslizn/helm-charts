{{/*
Environment of the shadowsocks container.
Usage: include "shadowsocks.env" $
*/}}
{{- define "shadowsocks.env" -}}
{{- $env := list (dict "name" "METHOD" "value" .Values.shadowsocks.method) -}}
{{- with .Values.shadowsocks.password -}}
{{- if .plainText -}}
{{- $env = append $env (dict "name" "PASSWORD" "value" .plainText) -}}
{{- else if .existingSecret -}}
{{- $env = append $env (dict "name" "PASSWORD" "valueFrom" (dict "secretKeyRef" (dict "name" .existingSecret.secretName "key" .existingSecret.passwordKey))) -}}
{{- end -}}
{{- end -}}
{{- with .Values.shadowsocks.dnsServers -}}
{{- $env = append $env (dict "name" "DNS_ADDRS" "value" (join "," .)) -}}
{{- end -}}
{{- with .Values.shadowsocks.timeout -}}
{{- $env = append $env (dict "name" "TIMEOUT" "value" .) -}}
{{- end -}}
{{- toYaml $env -}}
{{- end -}}

{{/*
Command of the kcptun sidecar. Usage: include "shadowsocks.kcptunArgs" (dict "ctx" $ "target" 8388)
*/}}
{{- define "shadowsocks.kcptunArgs" -}}
{{- $kcptun := .ctx.Values.kcptun -}}
server \
{{- with $kcptun.crypt }}
--crypt {{ quote . }} \
{{- end }}
{{- with $kcptun.key }}
--key \
{{- if .existingSecret }}
"$KCPTUN_KEY" \
{{- else }}
{{ quote .plainText }} \
{{- end }}
{{- end }}
--target 127.0.0.1:{{ .target }} \
--listen :{{ $kcptun.port }}
{{- end -}}

{{/*
The kcptun sidecar container, or an empty list when disabled.
Usage: include "shadowsocks.kcptunContainer" (dict "ctx" $ "target" 8388)
*/}}
{{- define "shadowsocks.kcptunContainer" -}}
{{- $ctx := .ctx -}}
{{- $kcptun := $ctx.Values.kcptun -}}
{{- $containers := list -}}
{{- if $kcptun.enabled -}}
{{- $container := dict "name" "kcptun" "image" (include "common.imageRef" (dict "image" $kcptun.image "appVersion" "latest")) "imagePullPolicy" ($kcptun.image.pullPolicy | default "IfNotPresent") "args" (list "sh" "-exc" (include "shadowsocks.kcptunArgs" (dict "ctx" $ctx "target" .target))) "ports" (list (dict "name" "kcptun" "containerPort" $kcptun.port "protocol" "UDP")) -}}
{{- with $kcptun.key.existingSecret -}}
{{- $_ := set $container "env" (list (dict "name" "KCPTUN_KEY" "valueFrom" (dict "secretKeyRef" (dict "name" .secretName "key" .passwordKey)))) -}}
{{- end -}}
{{- with $kcptun.resources -}}
{{- $_ := set $container "resources" . -}}
{{- end -}}
{{- with $kcptun.securityContext -}}
{{- $_ := set $container "securityContext" . -}}
{{- end -}}
{{- $containers = append $containers $container -}}
{{- end -}}
{{- toYaml $containers -}}
{{- end -}}

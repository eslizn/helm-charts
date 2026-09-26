{{/*
ServiceAccount. Usage: include "common.serviceaccount" .
*/}}
{{- define "common.serviceaccount" -}}
{{- $ctx := .ctx | default . -}}
{{- $v := $ctx.Values -}}
{{- if $v.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "common.serviceAccountName" $ctx }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
  {{- with $v.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- with $v.serviceAccount.automount }}
automountServiceAccountToken: {{ . }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Ingress. Backend defaults to the "main" service of the chart; set
ingress.service to another key of .Values.service and ingress.port to override
the port.

Usage: include "common.ingress" (dict "ctx" $)
*/}}
{{- define "common.ingress" -}}
{{- $ctx := .ctx | default . -}}
{{- $v := $ctx.Values -}}
{{- $ingress := .ingress | default $v.ingress | default dict -}}
{{- if $ingress.enabled -}}
{{- $fullname := include "common.fullname" $ctx -}}
{{- $component := $ingress.service | default "main" -}}
{{- $svcName := include "common.componentName" (dict "ctx" $ctx "component" $component) -}}
{{- $svcPort := $ingress.port -}}
{{- if not $svcPort -}}
{{- $svcPort = (index ($v.service | default dict) $component | default dict).port -}}
{{- end -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .name | default $fullname }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
  {{- with $ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- with $ingress.className }}
  ingressClassName: {{ . }}
  {{- end }}
  {{- with $ingress.tls }}
  tls:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  rules:
    {{- range $ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType | default "Prefix" }}
            backend:
              service:
                name: {{ $svcName }}
                port:
                  number: {{ $svcPort }}
          {{- end }}
    {{- end }}
{{- end -}}
{{- end -}}

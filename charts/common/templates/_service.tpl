{{/*
Services. .Values.service is a map of named services; the "main" key renders as
<fullname>, every other key as <fullname>-<key>. Each entry supports:
  enabled, type, port, targetPort, portName, protocol, nodePort, headless,
  clusterIP, loadBalancerIP, externalTrafficPolicy, internalTrafficPolicy,
  annotations, labels, extraPorts (raw list appended after the primary port),
  ports (raw list that replaces the primary port entirely).

Usage: include "common.service" (dict "ctx" $ "services" $services)
*/}}
{{- define "common.service" -}}
{{- $ctx := .ctx | default . -}}
{{- $v := $ctx.Values -}}
{{- $services := .services | default $v.service | default dict -}}
{{- $fullname := include "common.fullname" $ctx -}}
{{- range $key, $svc := $services }}
{{- if ne $svc.enabled false }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ if eq $key "main" }}{{ $fullname }}{{ else }}{{ printf "%s-%s" $fullname $key | trunc 63 | trimSuffix "-" }}{{ end }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
    {{- with $svc.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with $svc.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if $svc.headless }}
  clusterIP: None
  {{- else }}
  type: {{ $svc.type | default "ClusterIP" }}
  {{- with $svc.clusterIP }}
  clusterIP: {{ . }}
  {{- end }}
  {{- if and (eq ($svc.type | default "ClusterIP") "LoadBalancer") $svc.loadBalancerIP }}
  loadBalancerIP: {{ $svc.loadBalancerIP }}
  {{- end }}
  {{- with $svc.externalTrafficPolicy }}
  externalTrafficPolicy: {{ . }}
  {{- end }}
  {{- with $svc.internalTrafficPolicy }}
  internalTrafficPolicy: {{ . }}
  {{- end }}
  {{- end }}
  ports:
    {{- if $svc.ports }}
    {{- toYaml $svc.ports | nindent 4 }}
    {{- else }}
    - name: {{ $svc.portName | default "http" }}
      port: {{ $svc.port }}
      targetPort: {{ $svc.targetPort | default $svc.port }}
      protocol: {{ $svc.protocol | default "TCP" }}
      {{- if and (eq ($svc.type | default "ClusterIP") "NodePort") $svc.nodePort }}
      nodePort: {{ $svc.nodePort }}
      {{- end }}
    {{- with $svc.extraPorts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- end }}
  selector:
    {{- include "common.selectorLabels" $ctx | nindent 4 }}
{{- end }}
{{- end }}
{{- end -}}

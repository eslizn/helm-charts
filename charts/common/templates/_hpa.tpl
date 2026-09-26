{{/*
HorizontalPodAutoscaler (autoscaling/v2). Targets the chart workload, which
must not be a DaemonSet. Usage: include "common.hpa" .
*/}}
{{- define "common.hpa" -}}
{{- $ctx := .ctx | default . -}}
{{- $v := $ctx.Values -}}
{{- $autoscaling := $v.autoscaling | default dict -}}
{{- if $autoscaling.enabled -}}
{{- $kind := .kind | default ($v.workload | default dict).kind | default "Deployment" -}}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .name | default (include "common.fullname" $ctx) }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: {{ $kind }}
    name: {{ .name | default (include "common.fullname" $ctx) }}
  minReplicas: {{ $autoscaling.minReplicas | default 1 }}
  maxReplicas: {{ $autoscaling.maxReplicas | default 100 }}
  metrics:
    {{- if $autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ $autoscaling.targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if $autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ $autoscaling.targetMemoryUtilizationPercentage }}
    {{- end }}
{{- end -}}
{{- end -}}

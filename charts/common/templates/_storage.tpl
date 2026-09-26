{{/*
Standalone PersistentVolumeClaim for workloads that mount an existing claim
instead of using volumeClaimTemplates (i.e. Deployment/DaemonSet with
persistence.enabled). Set persistence.create=false to bring your own claim and
persistence.existingClaim to mount a claim by name.

Usage: include "common.pvc" .
*/}}
{{- define "common.pvc" -}}
{{- $ctx := .ctx | default . -}}
{{- $persistence := $ctx.Values.persistence | default dict -}}
{{- if and $persistence.enabled (ne $persistence.create false) (not $persistence.existingClaim) -}}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .name | default (include "common.fullname" $ctx) }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
  {{- with $persistence.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  accessModes:
    {{- toYaml ($persistence.accessModes | default (list "ReadWriteOnce")) | nindent 4 }}
  resources:
    requests:
      storage: {{ $persistence.size | default "8Gi" }}
  {{- with $persistence.storageClass }}
  storageClassName: {{ . | quote }}
  {{- end }}
{{- end -}}
{{- end -}}

{{/*
Helm test pod that connects to the main service port.
Usage: include "common.testConnection" .
*/}}
{{- define "common.testConnection" -}}
{{- $ctx := .ctx | default . -}}
{{- $v := $ctx.Values -}}
{{- $component := .service | default "main" -}}
{{- $svcName := include "common.componentName" (dict "ctx" $ctx "component" $component) -}}
{{- $port := (index ($v.service | default dict) $component | default dict).port -}}
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "common.fullname" $ctx }}-test-connection"
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
  annotations:
    "helm.sh/hook": test
spec:
  containers:
    - name: wget
      image: {{ .image | default "busybox" }}
      command: ['wget']
      args: ['{{ $svcName }}:{{ $port }}']
  restartPolicy: Never
{{- end -}}

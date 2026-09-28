{{/*
Workload templates: common.deployment, common.statefulset and common.daemonset.
They render the same pod spec, so a chart switches workload kind by setting
workload.kind (or by calling the matching template) without touching the pod
level configuration.

Per-chart overrides (all optional) are passed alongside the context:
  {{ include "common.deployment" (dict "ctx" $ "ports" $ports "env" $env) }}
Supported overrides: name, containerName, replicaCount, serviceAccountName,
command, args, env, envFrom, ports, livenessProbe, readinessProbe,
startupProbe, volumes, volumeMounts, initContainers, extraContainers,
dnsPolicy, runtimeClassName, podAnnotations.
*/}}

{{/*
Pod template shared by all workload kinds. Usage: include "common.podTemplate" .
*/}}
{{- define "common.podTemplate" -}}
{{- $ctx := .ctx | default . -}}
{{- $v := $ctx.Values -}}
{{- $w := $v.workload | default dict -}}
{{- $persistence := $v.persistence | default dict -}}
{{- /* a Deployment/DaemonSet mounts a PVC, a StatefulSet mounts its own claim template */ -}}
{{- $claimVolume := and $persistence.enabled (ne ($w.kind | default "Deployment") "StatefulSet") -}}
{{- $mountVolume := $persistence.enabled -}}
metadata:
  {{- with .podAnnotations | default $v.podAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
    {{- with $v.podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  {{- with $v.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  serviceAccountName: {{ .serviceAccountName | default (include "common.serviceAccountName" $ctx) }}
  {{- with $v.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .dnsPolicy | default $w.dnsPolicy }}
  dnsPolicy: {{ . }}
  {{- end }}
  {{- with .runtimeClassName | default $w.runtimeClassName }}
  runtimeClassName: {{ . }}
  {{- end }}
  {{- with .initContainers | default $w.initContainers }}
  initContainers:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  containers:
    {{- include "common.container" . | nindent 4 }}
  {{- with .extraContainers | default $w.extraContainers }}
  {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- $volumes := .volumes | default $w.volumes -}}
  {{- if or $volumes $claimVolume }}
  volumes:
    {{- /* $claimVolume, not $mountVolume: a StatefulSet takes its claim from
           volumeClaimTemplates, so referencing the fullname claim here would
           point at a PVC that does not exist. */}}
    {{- if $claimVolume }}
    - name: {{ $persistence.volumeName | default "data" }}
      persistentVolumeClaim:
        claimName: {{ $persistence.existingClaim | default (include "common.fullname" $ctx) }}
    {{- end }}
    {{- with $volumes }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
  {{- with $v.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $v.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $v.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}

{{/*
Main container of a workload. Usage: include "common.container" .
*/}}
{{- define "common.container" -}}
{{- $ctx := .ctx | default . -}}
{{- $v := $ctx.Values -}}
{{- $w := $v.workload | default dict -}}
{{- $persistence := $v.persistence | default dict -}}
{{- $mountVolume := $persistence.enabled -}}
- name: {{ .containerName | default $ctx.Chart.Name }}
  {{- with $v.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  image: {{ include "common.image" $ctx | quote }}
  imagePullPolicy: {{ $v.image.pullPolicy | default "IfNotPresent" }}
  {{- with .command | default $w.command }}
  command:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .args | default $w.args }}
  args:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .env | default $w.env }}
  env:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .envFrom | default $w.envFrom }}
  envFrom:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- $ports := .ports | default $w.ports }}
  {{- with $ports }}
  ports:
    {{- range . }}
    - name: {{ .name }}
      containerPort: {{ .containerPort }}
      protocol: {{ .protocol | default "TCP" }}
      {{- with .hostPort }}
      hostPort: {{ . }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- with .livenessProbe | default $w.livenessProbe }}
  livenessProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .readinessProbe | default $w.readinessProbe }}
  readinessProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .startupProbe | default $w.startupProbe }}
  startupProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $v.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- $volumeMounts := .volumeMounts | default $w.volumeMounts -}}
  {{- if or $volumeMounts $mountVolume }}
  volumeMounts:
    {{- if $mountVolume }}
    - name: {{ $persistence.volumeName | default "data" }}
      mountPath: {{ $persistence.mountPath }}
      {{- with $persistence.subPath }}
      subPath: {{ . }}
      {{- end }}
    {{- end }}
    {{- with $volumeMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Deployment. Usage: include "common.deployment" (dict "ctx" $ ...)
*/}}
{{- define "common.deployment" -}}
{{- $ctx := .ctx | default . -}}
{{- $v := $ctx.Values -}}
{{- $autoscaling := $v.autoscaling | default dict -}}
{{- $kind := .kind | default "Deployment" -}}
apiVersion: apps/v1
kind: {{ $kind }}
metadata:
  name: {{ .name | default (include "common.fullname" $ctx) }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
spec:
  {{- if not $autoscaling.enabled }}
  replicas: {{ .replicaCount | default $v.replicaCount | default 1 }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "common.selectorLabels" $ctx | nindent 6 }}
  template:
    {{- include "common.podTemplate" . | nindent 4 }}
{{- end -}}

{{/*
StatefulSet. Usage: include "common.statefulset" (dict "ctx" $ ...)
*/}}
{{- define "common.statefulset" -}}
{{- $ctx := .ctx | default . -}}
{{- $v := $ctx.Values -}}
{{- $w := $v.workload | default dict -}}
{{- $persistence := $v.persistence | default dict -}}
{{- $autoscaling := $v.autoscaling | default dict -}}
{{- $fullname := .name | default (include "common.fullname" $ctx) -}}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
spec:
  serviceName: {{ .serviceName | default $w.serviceName | default $fullname }}
  {{- with .podManagementPolicy | default $w.podManagementPolicy }}
  podManagementPolicy: {{ . }}
  {{- end }}
  {{- with .updateStrategy | default $w.updateStrategy }}
  updateStrategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- /* omitted while autoscaling is on, like common.deployment, so an
         upgrade does not reset the replica count the HPA settled on */}}
  {{- if not $autoscaling.enabled }}
  replicas: {{ .replicaCount | default $v.replicaCount | default 1 }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "common.selectorLabels" $ctx | nindent 6 }}
  template:
    {{- include "common.podTemplate" . | nindent 4 }}
  {{- if $persistence.enabled }}
  volumeClaimTemplates:
    - metadata:
        name: {{ $persistence.volumeName | default "data" }}
        labels:
          {{- include "common.labels" $ctx | nindent 10 }}
      spec:
        accessModes:
          {{- toYaml ($persistence.accessModes | default (list "ReadWriteOnce")) | nindent 10 }}
        resources:
          requests:
            storage: {{ $persistence.size | default "8Gi" }}
        {{- with $persistence.storageClass }}
        storageClassName: {{ . | quote }}
        {{- end }}
    {{- with $persistence.extraClaimTemplates }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
DaemonSet. Usage: include "common.daemonset" (dict "ctx" $ ...)
*/}}
{{- define "common.daemonset" -}}
{{- $ctx := .ctx | default . -}}
{{- $w := $ctx.Values.workload | default dict -}}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: {{ .name | default (include "common.fullname" $ctx) }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
spec:
  {{- with .updateStrategy | default $w.updateStrategy }}
  updateStrategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "common.selectorLabels" $ctx | nindent 6 }}
  template:
    {{- include "common.podTemplate" . | nindent 4 }}
{{- end -}}

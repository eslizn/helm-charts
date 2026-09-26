{{/*
Chart private named templates. Shared behaviour lives in the common library
chart (see ../common/templates/_helpers.tpl).
*/}}

{{/*
Name of the chart ConfigMap: it carries the .Values.env key/value pairs and is
consumed by the workload through envFrom.configMapRef, so both sides resolve the
name here.
*/}}
{{- define "octopus.configMapName" -}}
{{- include "common.fullname" . -}}
{{- end -}}

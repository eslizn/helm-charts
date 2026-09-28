{{/*
Shared helpers for every chart in this repository.
Resource templates in this library accept either the root context directly or a
dict of the form (dict "ctx" $ "name" "..." "ports" $ports ...) so a chart can
override a single rendered field (dynamic ports, sidecars, env) without
duplicating the whole template.
*/}}

{{/*
Chart name, overridable with nameOverride.
*/}}
{{- define "common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name: release name + chart name, overridable with
fullnameOverride. Truncated at 63 chars for the DNS naming spec.
*/}}
{{- define "common.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Name suffix for a named component: "main" is the bare fullname, every other
key becomes <fullname>-<key>.
*/}}
{{- define "common.componentName" -}}
{{- $ctx := .ctx -}}
{{- $fullname := include "common.fullname" $ctx -}}
{{- if eq .component "main" -}}
{{- $fullname -}}
{{- else -}}
{{- printf "%s-%s" $fullname .component | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
chart label value.
*/}}
{{- define "common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "common.labels" -}}
helm.sh/chart: {{ include "common.chart" . }}
{{ include "common.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels. These are part of the immutable workload selector: changing
them requires recreating the workload.
*/}}
{{- define "common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Name of the service account to use.
*/}}
{{- define "common.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "common.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Main container image, falling back to the chart appVersion when image.tag is
empty. Usage: include "common.image" $ctx
*/}}
{{- define "common.image" -}}
{{- include "common.imageRef" (dict "image" .Values.image "appVersion" .Chart.AppVersion) -}}
{{- end -}}

{{/*
Render "repository:tag" for an arbitrary image map.
Usage: include "common.imageRef" (dict "image" $someImage "appVersion" "" )
*/}}
{{- define "common.imageRef" -}}
{{- $tag := .image.tag | default .appVersion | toString -}}
{{- if not $tag -}}
{{- fail (printf "image tag is required: set image.tag or Chart.yaml appVersion (repository: %s)" .image.repository) -}}
{{- end -}}
{{- printf "%s:%s" .image.repository $tag -}}
{{- end -}}

{{/*
Tolerate both "the template was called with the root context" and "the template
was called with an override dict".
*/}}
{{- define "common.ctx" -}}
{{- if .ctx -}}
{{- .ctx -}}
{{- else -}}
{{- . -}}
{{- end -}}
{{- end -}}


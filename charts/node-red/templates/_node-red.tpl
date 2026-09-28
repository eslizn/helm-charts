{{/*
Chart private named templates. Shared behaviour lives in the common library
chart (see ../common/templates/_helpers.tpl).
*/}}

{{/*
Name of the ConfigMap holding the non-secret environment variables.
Usage: include "node-red.envConfigMapName" $
*/}}
{{- define "node-red.envConfigMapName" -}}
{{- printf "%s-env" (include "common.fullname" .) -}}
{{- end -}}

{{/*
Name of the ConfigMap holding settings.js: either the one the user manages or
the one this chart renders.
Usage: include "node-red.settingsConfigMapName" $
*/}}
{{- define "node-red.settingsConfigMapName" -}}
{{- .Values.nodeRed.existingSettingsConfigMap | default (printf "%s-settings" (include "common.fullname" .)) -}}
{{- end -}}

{{/*
Name of the Secret holding the credentials.
Usage: include "node-red.secretName" $
*/}}
{{- define "node-red.secretName" -}}
{{- .Values.secret.existingSecret | default (printf "%s-secret" (include "common.fullname" .)) -}}
{{- end -}}

{{/*
Whether a settings.js is mounted at all.
*/}}
{{- define "node-red.settingsMountEnabled" -}}
{{- if or .Values.nodeRed.settings .Values.nodeRed.existingSettingsConfigMap -}}true{{- end -}}
{{- end -}}

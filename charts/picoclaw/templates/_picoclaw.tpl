{{/*
Name of the Secret holding config.json: either the one the user manages or the
one this chart renders.
Usage: include "picoclaw.configSecretName" $
*/}}
{{- define "picoclaw.configSecretName" -}}
{{- .Values.config.existingSecret | default (printf "%s-config" (include "common.fullname" .)) -}}
{{- end -}}

{{/*
Name of the Secret holding the launcher dashboard token.
Usage: include "picoclaw.launcherSecretName" $
*/}}
{{- define "picoclaw.launcherSecretName" -}}
{{- .Values.launcher.existingSecret | default (printf "%s-launcher" (include "common.fullname" .)) -}}
{{- end -}}

{{/*
Whether a config.json is mounted at all.
*/}}
{{- define "picoclaw.configMountEnabled" -}}
{{- if or .Values.config.create .Values.config.existingSecret -}}true{{- end -}}
{{- end -}}

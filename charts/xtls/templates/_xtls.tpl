{{/*
Chart private named templates. Shared naming/label templates come from the
common library (common.fullname, common.labels, ...).
*/}}

{{/*
Routes of the Traefik IngressRouteTCP: one HostSNI rule per REALITY serverName
declared in options.inbounds, all pointing at the main service port. The match
and the service reference are chart specific, so they stay here instead of in
the shared library.

Usage: include "xtls.ingressRouteTCPRoutes" .
*/}}
{{- define "xtls.ingressRouteTCPRoutes" -}}
{{- $fullname := include "common.fullname" . -}}
{{- $port := .Values.service.main.port -}}
{{- range .Values.options.inbounds }}
{{- range .streamSettings.realitySettings.serverNames }}
- match: HostSNI(`{{ . }}`)
  services:
    - name: {{ $fullname }}
      port: {{ $port }}
      proxyProtocol:
        version: 2
{{- end }}
{{- end }}
{{- end -}}

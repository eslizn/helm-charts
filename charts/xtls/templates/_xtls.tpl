{{/*
Chart private named templates. Shared naming/label templates come from the
common library (common.fullname, common.labels, ...).
*/}}

{{/*
Routes of the Traefik IngressRouteTCP: one HostSNI rule per REALITY serverName
declared in options.inbounds, all pointing at the main service port. The match
and the service reference are chart specific, so they stay here instead of in
the shared library.

Inbounds that are not REALITY (no streamSettings.realitySettings.serverNames,
say a Trojan or a plain TLS vless inbound) are skipped: dig resolves the missing
keys to an empty list, where writing the path out would abort the render with
"nil pointer evaluating interface {}.streamSettings".

nativeLB (values.ingress.nativeLB) is what puts the Service's
internalTrafficPolicy/trafficDistribution in charge of picking a replica:
without it Traefik resolves the endpoint IPs and balances on its own, and the
Service fields never come into play.

Usage: include "xtls.ingressRouteTCPRoutes" .
*/}}
{{- define "xtls.ingressRouteTCPRoutes" -}}
{{- $fullname := include "common.fullname" . -}}
{{- $port := .Values.service.main.port -}}
{{- $nativeLB := .Values.ingress.nativeLB -}}
{{- range .Values.options.inbounds }}
{{- range dig "streamSettings" "realitySettings" "serverNames" (list) . }}
- match: HostSNI(`{{ . }}`)
  services:
    - name: {{ $fullname }}
      port: {{ $port }}
      {{- if $nativeLB }}
      nativeLB: true
      {{- end }}
      proxyProtocol:
        version: 2
{{- end }}
{{- end }}
{{- end -}}

{{/*
Name of the Secret holding the origin certificate. Usage: include
"xtls.originTlsSecretName" $.
*/}}
{{- define "xtls.originTlsSecretName" -}}
{{- .Values.origin.tlsSecretName | default (printf "%s-origin-tls" (include "common.fullname" .)) -}}
{{- end -}}

{{/*
The host the origin serves, together with the consistency check for it. The
sidecar terminates TLS for exactly one name, so that name has to be the only
REALITY serverName in options.inbounds - one destination cannot answer for
several names. The host is a value (not derived from the inbound) so the
release values name the domain explicitly, and the two cannot drift silently.

Usage: include "xtls.originHost" .
*/}}
{{- define "xtls.originHost" -}}
{{- $host := .Values.origin.host -}}
{{- if not $host -}}
{{- fail "xtls: origin.host is required when origin.enabled" -}}
{{- end -}}
{{- $serverNames := list -}}
{{- range .Values.options.inbounds -}}
{{- range dig "streamSettings" "realitySettings" "serverNames" (list) . -}}
{{- if not (has . $serverNames) -}}
{{- $serverNames = append $serverNames . -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if ne (len $serverNames) 1 -}}
{{- fail (printf "xtls: origin is single-host, but the REALITY serverNames are [%s]; leave exactly one, equal to origin.host (%q)" (join ", " $serverNames) $host) -}}
{{- end -}}
{{- if ne $host (index $serverNames 0) -}}
{{- fail (printf "xtls: origin.host %q must equal the REALITY serverName %q" $host (index $serverNames 0)) -}}
{{- end -}}
{{- $host -}}
{{- end -}}

{{/*
Refuse to render an origin sidecar the xray config does not point at. The
sidecar only makes sense as the REALITY `dest`; a mismatch is otherwise only
visible as a fallback that never reaches nginx.

Only checks the REALITY inbounds; a non-REALITY inbound is not involved.

Usage: include "xtls.validateOrigin" .
*/}}
{{- define "xtls.validateOrigin" -}}
{{- $host := include "xtls.originHost" . -}}
{{- $dest := printf "127.0.0.1:%v" .Values.origin.port -}}
{{- range .Values.options.inbounds -}}
{{- $reality := dig "streamSettings" "realitySettings" dict . -}}
{{- if has $host ($reality.serverNames | default list) -}}
{{- $inboundDest := $reality.dest | default "" -}}
{{- if ne $inboundDest $dest -}}
{{- fail (printf "xtls: origin.enabled, but the REALITY inbound that serves %q has dest %q; set it to %q so the fallback reaches the sidecar" $host $inboundDest $dest) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
The origin sidecar container. Returns a one-element YAML list, parsed with
fromYamlArray and appended to workload.extraContainers.
Usage: include "xtls.originContainer" (dict "ctx" $)
*/}}
{{- define "xtls.originContainer" -}}
{{- $origin := .ctx.Values.origin -}}
- name: origin
  image: {{ include "common.imageRef" (dict "image" $origin.image "appVersion" "") | quote }}
  imagePullPolicy: {{ $origin.image.pullPolicy | default "IfNotPresent" }}
  command: [nginx]
  args: [-c, /etc/nginx-origin/nginx.conf, -g, "daemon off;"]
  {{- with $origin.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  ports:
    - name: origin-tls
      containerPort: {{ $origin.port }}
      protocol: TCP
  {{- /* No readinessProbe on purpose: the main container has none either, so
         a sidecar that is not ready (certificate not issued yet, say) would
         take the whole xray replica out of the Service endpoints. The TCP
         liveness only restarts nginx when it stops listening. */}}
  livenessProbe:
    tcpSocket:
      port: origin-tls
    initialDelaySeconds: 10
    periodSeconds: 10
  {{- with $origin.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: origin-config
      mountPath: /etc/nginx-origin
      readOnly: true
    - name: origin-tls
      mountPath: /etc/origin-tls
      readOnly: true
    - name: origin-tmp
      mountPath: /tmp
{{- end -}}

{{/*
Volumes of the origin sidecar. Returns a YAML list, parsed with fromYamlArray.
The tls Secret is optional: cert-manager may not have issued it yet, and a
missing optional Secret leaves the Pod runnable (nginx starts, TLS handshakes
for `host` fail until the Secret appears). nginx reads the certificate through
a variable path, so it does not need the file at startup.
Usage: include "xtls.originVolumes" (dict "ctx" $)
*/}}
{{- define "xtls.originVolumes" -}}
{{- $ctx := .ctx -}}
{{- $host := include "xtls.originHost" $ctx -}}
- name: origin-config
  configMap:
    name: {{ include "common.fullname" $ctx }}-origin
- name: origin-tls
  secret:
    secretName: {{ include "xtls.originTlsSecretName" $ctx }}
    optional: true
    defaultMode: 0440
    items:
      - key: tls.crt
        path: {{ $host }}.crt
      - key: tls.key
        path: {{ $host }}.key
- name: origin-tmp
  emptyDir:
    sizeLimit: 16Mi
{{- end -}}

{{/*
Chart-private named templates. Shared behaviour lives in the common library
chart (see ../common/templates/_helpers.tpl).
*/}}

{{/*
Name of the ConfigMap holding the non-secret environment variables.
Usage: include "deepseek-harness.envConfigMapName" $
*/}}
{{- define "deepseek-harness.envConfigMapName" -}}
{{- printf "%s-env" (include "common.fullname" .) -}}
{{- end -}}

{{/*
Name of the Secret holding the credentials: either the one the user manages or
the one this chart renders.
Usage: include "deepseek-harness.secretName" $
*/}}
{{- define "deepseek-harness.secretName" -}}
{{- .Values.secret.existingSecret | default (printf "%s-secret" (include "common.fullname" .)) -}}
{{- end -}}

{{/*
Effective advertised HTTP(S) root. An explicit dsh.web.publicUrl wins.
Otherwise, with Ingress enabled and the first host's first path at "/", derive
<scheme>://<first host>/; the scheme is https when ingress.tls is non-empty.
A non-root path cannot be derived because the chart does not know whether the
proxy strips the prefix, so it returns empty and validate fails.

Usage: include "deepseek-harness.publicUrl" $
*/}}
{{- define "deepseek-harness.publicUrl" -}}
{{- $explicit := .Values.dsh.web.publicUrl | default "" -}}
{{- if $explicit -}}
{{- $explicit -}}
{{- else if .Values.ingress.enabled -}}
{{- $hosts := .Values.ingress.hosts | default list -}}
{{- if $hosts -}}
{{- $firstHost := (first $hosts).host | default "" -}}
{{- $paths := (first $hosts).paths | default list -}}
{{- $path := "/" -}}
{{- if $paths -}}
{{- $path = (first $paths).path | default "/" -}}
{{- end -}}
{{- if and $firstHost (eq $path "/") -}}
{{- $scheme := "http" -}}
{{- if .Values.ingress.tls -}}
{{- $scheme = "https" -}}
{{- end -}}
{{- printf "%s://%s/" $scheme $firstHost -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Comma-separated authorities accepted by the /api Host/Origin fence: every
ingress host, every explicit dsh.web.trustedHosts entry, and the advertised
public URL's host. dsh accepts loopback and its own bind IP without this list;
an Ingress host is neither, so it must be included.

Usage: include "deepseek-harness.trustedHosts" $
*/}}
{{- define "deepseek-harness.trustedHosts" -}}
{{- $hosts := list -}}
{{- if .Values.ingress.enabled -}}
{{- $ingressHosts := .Values.ingress.hosts | default list -}}
{{- range $ingressHosts -}}
{{- if .host -}}
{{- $hosts = append $hosts .host -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $explicitHosts := .Values.dsh.web.trustedHosts | default list -}}
{{- range $explicitHosts -}}
{{- if . -}}
{{- $hosts = append $hosts . -}}
{{- end -}}
{{- end -}}
{{- $publicUrl := include "deepseek-harness.publicUrl" . -}}
{{- if $publicUrl -}}
{{- $parsed := urlParse $publicUrl -}}
{{- if $parsed.host -}}
{{- $hosts = append $hosts $parsed.host -}}
{{- end -}}
{{- end -}}
{{- join "," (uniq $hosts) -}}
{{- end -}}

{{/*
Fail when two mount paths are equal or nested. Usage:
include "deepseek-harness.validatePathPair" (dict
  "a" $pathA "aName" "dsh.home"
  "b" $pathB "bName" "dsh.workspace.mountPath")
*/}}
{{- define "deepseek-harness.validatePathPair" -}}
{{- $a := .a | trimSuffix "/" -}}
{{- $b := .b | trimSuffix "/" -}}
{{- if eq $a $b -}}
{{- fail (printf "deepseek-harness: %s and %s must differ" .aName .bName) -}}
{{- end -}}
{{- if or (hasPrefix (printf "%s/" $a) (printf "%s/" $b)) (hasPrefix (printf "%s/" $b) (printf "%s/" $a)) -}}
{{- fail (printf "deepseek-harness: %s and %s must not be nested" .aName .bName) -}}
{{- end -}}
{{- end -}}

{{/*
Validate the combinations this chart cannot support. Rendering stops with a
message that names the value to change; this is deliberately a hard failure
instead of a silently ignored setting.

Usage: include "deepseek-harness.validate" $
*/}}
{{- define "deepseek-harness.validate" -}}
{{- if ne (int .Values.replicaCount) 1 -}}
{{- fail "deepseek-harness: replicaCount must be 1 - a second dsh would have its own credentials, plugins and cookie secret" -}}
{{- end -}}
{{- if .Values.autoscaling.enabled -}}
{{- fail "deepseek-harness: autoscaling.enabled must be false - this chart runs exactly one stateful dsh process" -}}
{{- end -}}
{{- if ne .Values.workload.kind "StatefulSet" -}}
{{- fail "deepseek-harness: workload.kind must be StatefulSet - the chart relies on its ordered rollout and stable Pod identity" -}}
{{- end -}}
{{- if ne .Values.persistence.mountPath .Values.dsh.home -}}
{{- fail (printf "deepseek-harness: persistence.mountPath (%s) must equal dsh.home (%s)" .Values.persistence.mountPath .Values.dsh.home) -}}
{{- end -}}
{{- if and .Values.persistence.enabled (not .Values.persistence.existingClaim) (eq (.Values.persistence.create | toString) "false") -}}
{{- fail "deepseek-harness: persistence.create=false requires persistence.existingClaim" -}}
{{- end -}}
{{- $modes := list "" "read-only" "workspace-write" "danger-full-access" -}}
{{- if not (has (.Values.dsh.permissionMode | default "") $modes) -}}
{{- fail (printf "deepseek-harness: dsh.permissionMode %q must be one of \"\", read-only, workspace-write, danger-full-access" .Values.dsh.permissionMode) -}}
{{- end -}}
{{- /* workspace.persistent and agents.persistent are effective only while
       persistence.enabled is true; with persistence off all three roots are
       ephemeral. */ -}}
{{- if not (regexMatch "^/" .Values.dsh.home) -}}
{{- fail "deepseek-harness: dsh.home must be an absolute path" -}}
{{- end -}}
{{- if not (regexMatch "^/" .Values.dsh.workspace.mountPath) -}}
{{- fail "deepseek-harness: dsh.workspace.mountPath must be an absolute path" -}}
{{- end -}}
{{- if not (regexMatch "^/" .Values.dsh.agents.home) -}}
{{- fail "deepseek-harness: dsh.agents.home must be an absolute path" -}}
{{- end -}}
{{- include "deepseek-harness.validatePathPair" (dict
      "a" .Values.dsh.home "aName" "dsh.home"
      "b" .Values.dsh.workspace.mountPath "bName" "dsh.workspace.mountPath") -}}
{{- include "deepseek-harness.validatePathPair" (dict
      "a" .Values.dsh.home "aName" "dsh.home"
      "b" .Values.dsh.agents.home "bName" "dsh.agents.home") -}}
{{- include "deepseek-harness.validatePathPair" (dict
      "a" .Values.dsh.workspace.mountPath "aName" "dsh.workspace.mountPath"
      "b" .Values.dsh.agents.home "bName" "dsh.agents.home") -}}

{{- if .Values.ingress.enabled -}}
{{- $hosts := .Values.ingress.hosts | default list -}}
{{- if not $hosts -}}
{{- fail "deepseek-harness: ingress.enabled requires at least one ingress.hosts entry (or set dsh.web.publicUrl and use workload access directly)" -}}
{{- end -}}
{{- if not .Values.dsh.web.publicUrl -}}
{{- $firstHost := (first $hosts).host | default "" -}}
{{- if not $firstHost -}}
{{- fail "deepseek-harness: ingress.enabled requires a non-empty first hosts[].host, or an explicit dsh.web.publicUrl" -}}
{{- end -}}
{{- $paths := (first $hosts).paths | default list -}}
{{- $path := "/" -}}
{{- if $paths -}}
{{- $path = (first $paths).path | default "/" -}}
{{- end -}}
{{- if ne $path "/" -}}
{{- fail "deepseek-harness: an ingress path other than / requires dsh.web.publicUrl (the external HTTP(S) root, with trailing slash) and a proxy that strips the prefix" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- if .Values.dsh.web.publicUrl -}}
{{- $u := urlParse .Values.dsh.web.publicUrl -}}
{{- if not $u.host -}}
{{- fail (printf "deepseek-harness: dsh.web.publicUrl %q is not a valid URL" .Values.dsh.web.publicUrl) -}}
{{- end -}}
{{- if not (has $u.scheme (list "http" "https")) -}}
{{- fail "deepseek-harness: dsh.web.publicUrl must use http or https" -}}
{{- end -}}
{{- end -}}

{{- if .Values.persistence.enabled -}}
{{- $subPaths := list -}}
{{- $subPaths = append $subPaths .Values.persistence.subPath -}}
{{- if .Values.dsh.workspace.persistent -}}
{{- $subPaths = append $subPaths .Values.dsh.workspace.subPath -}}
{{- end -}}
{{- if .Values.dsh.agents.persistent -}}
{{- $subPaths = append $subPaths .Values.dsh.agents.subPath -}}
{{- end -}}
{{- range $subPaths -}}
{{- if . -}}
{{- if not (regexMatch "^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$" .) -}}
{{- fail (printf "deepseek-harness: PVC subPath %q may contain only letters, digits, dots, underscores, hyphens and slashes" .) -}}
{{- end -}}
{{- if has ".." (splitList "/" .) -}}
{{- fail (printf "deepseek-harness: PVC subPath %q must not contain .." .) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if and .Values.dsh.workspace.persistent (not .Values.dsh.workspace.subPath) -}}
{{- fail "deepseek-harness: dsh.workspace.subPath is required when dsh.workspace.persistent=true" -}}
{{- end -}}
{{- if and .Values.dsh.agents.persistent (not .Values.dsh.agents.subPath) -}}
{{- fail "deepseek-harness: dsh.agents.subPath is required when dsh.agents.persistent=true" -}}
{{- end -}}
{{- if and .Values.dsh.workspace.persistent (eq .Values.persistence.subPath .Values.dsh.workspace.subPath) -}}
{{- fail "deepseek-harness: persistence.subPath and dsh.workspace.subPath must differ" -}}
{{- end -}}
{{- if and .Values.dsh.agents.persistent (eq .Values.persistence.subPath .Values.dsh.agents.subPath) -}}
{{- fail "deepseek-harness: persistence.subPath and dsh.agents.subPath must differ" -}}
{{- end -}}
{{- if and .Values.dsh.workspace.persistent .Values.dsh.agents.persistent (eq .Values.dsh.workspace.subPath .Values.dsh.agents.subPath) -}}
{{- fail "deepseek-harness: dsh.workspace.subPath and dsh.agents.subPath must differ" -}}
{{- end -}}
{{- end -}}
{{- end -}}

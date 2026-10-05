{{/*
Helpers for the futuopend chart.

One Futu OpenD process serves exactly one Futu account, so the chart renders one
Deployment/Service/PVC/Secret per entry of .Values.accounts. The common library
derives every name and every selector label from common.name / common.fullname,
which normally describe the whole release. To get per-account resources out of
it, each account is rendered in its own synthetic context whose
nameOverride/fullnameOverride carry the account name:

    {{- $v := mergeOverwrite (deepCopy $root.Values) (deepCopy $acct) -}}
    {{- $_ := set $v "nameOverride" (include "futuopend.accountName" ...) -}}
    {{- $_ := set $v "fullnameOverride" (include "futuopend.accountFullname" ...) -}}
    {{- $ctx := dict "Values" $v "Chart" $root.Chart "Release" $root.Release -}}

Two things depend on this and are easy to get wrong:

  * mergeOverwrite, not merge. sprig's merge gives precedence to the
    destination, so `merge $defaults $acct` would let the top level win and the
    account override would vanish; mergeOverwrite lets the account win, which is
    the point. Lists are not merged either way - an account that sets
    workload.env replaces the whole list, the same trap as xtls options.inbounds.
  * The distinct nameOverride is what keeps the account selectors apart.
    app.kubernetes.io/name is part of spec.selector, and without the account
    suffix every account's Service would select every account's Pod, so a client
    asking for one account could be answered by another account's session.

Go templates cannot return a map from an include, only a string, which is why
the four lines above are repeated in each per-account resource template instead
of being factored into one.

The account name also has to be part of the label, not just the resource name:
common.selectorLabels is built from common.name (nameOverride), so the label
value becomes "<chart>-<account>" and the resources are named
"<release>-<chart>-<account>".
*/}}

{{/*
Suffix-safe account identifier, used as the app.kubernetes.io/name label value.
Usage: include "futuopend.accountName" (dict "ctx" $ "account" $acct)
*/}}
{{- define "futuopend.accountName" -}}
{{- printf "%s-%s" (include "common.name" .ctx) .account.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Resource name of one account: <release>-<chart>-<account> (or fullnameOverride).
Usage: include "futuopend.accountFullname" (dict "ctx" $ "account" $acct)
*/}}
{{- define "futuopend.accountFullname" -}}
{{- printf "%s-%s" (include "common.fullname" .ctx) .account.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Name of the Secret holding the account credentials: the account's own Secret,
or an existing one the user manages. Usage: include "futuopend.secretName" (dict "ctx" $ctx)
*/}}
{{- define "futuopend.secretName" -}}
{{- if .ctx.Values.existingSecret -}}
{{- .ctx.Values.existingSecret -}}
{{- else -}}
{{- include "common.fullname" .ctx -}}
{{- end -}}
{{- end -}}

{{/*
Validate every account up front, so a typo fails the render with a message
instead of producing resources that collide or overwrite each other.
Usage: include "futuopend.validate" (dict "ctx" $)
*/}}
{{- define "futuopend.validate" -}}
{{- $root := .ctx -}}
{{- if ne (int ($root.Values.replicaCount | default 1)) 1 -}}
{{- fail (printf "futuopend: replicaCount must be 1, got %v. One OpenD process serves one account, and a second Pod on the same account is a second concurrent login - Futu kicks the top quote rights off one of them. List the account twice in accounts[] if you really want two instances." $root.Values.replicaCount) -}}
{{- end -}}
{{- $kind := ($root.Values.workload | default dict).kind | default "Deployment" -}}
{{- if ne $kind "Deployment" -}}
{{- fail (printf "futuopend: workload.kind %q is not supported, only Deployment. A StatefulSet runs N identical Pods (the accounts differ, so they cannot share a spec) and a DaemonSet runs one Pod per node; niether can express one account per instance." $kind) -}}
{{- end -}}
{{- $seen := dict -}}
{{- range $acct := $root.Values.accounts -}}
{{- $name := toString $acct.name -}}
{{- if not $acct.name -}}
{{- fail "futuopend: every entry of .Values.accounts needs a name - it becomes the resource name suffix and the app.kubernetes.io/name label of that account" -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $name) -}}
{{- fail (printf "futuopend: accounts[].name %q is not a DNS label (lowercase alphanumerics and '-', must start and end alphanumeric)" $name) -}}
{{- end -}}
{{- if hasKey $seen $name -}}
{{- fail (printf "futuopend: accounts[].name %q is used twice; the names become resource names, so they have to be unique" $name) -}}
{{- end -}}
{{- $_ := set $seen $name true -}}
{{- $fullname := include "futuopend.accountFullname" (dict "ctx" $root "account" $acct) -}}
{{- if gt (len $fullname) 62 -}}
{{- fail (printf "futuopend: accounts[].name %q makes the resource name %q too long (63 char limit) - shorten either the name or the release name" $name $fullname) -}}
{{- end -}}
{{- if and (not $acct.loginAccount) (not $acct.existingSecret) -}}
{{- fail (printf "futuopend: account %q needs loginAccount (or an existingSecret holding the loginAccount/loginPwdMd5 keys)" $name) -}}
{{- end -}}
{{- if and $acct.loginByRemember $acct.loginPwdMd5 -}}
{{- fail (printf "futuopend: account %q sets both loginByRemember and loginPwdMd5; OpenD ignores the password when the remembered login is used, so pick one" $name) -}}
{{- end -}}
{{- if and (not $acct.loginPwdMd5) (not $acct.existingSecret) (not $acct.loginByRemember) -}}
{{- fail (printf "futuopend: account %q needs loginPwdMd5 (the MD5 of the login password, 32 hex chars: printf %%s \"$PASSWORD\" | md5sum), or existingSecret for a Secret you manage yourself, or loginByRemember to reuse a session already saved in the account's PVC" $name) -}}
{{- end -}}
{{- with $acct.rsaPrivateKey -}}
{{- if not .secretName -}}
{{- fail (printf "futuopend: account %q sets rsaPrivateKey without secretName; the key has to come from a Secret (PKCS#1, 512 or 1024 bit, no passphrase)" $name) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Container ports of one account, as YAML so callers can turn it back into a list
with fromYamlArray. The names api/telnet are what the probes and the Service
targetPort refer to.
Usage: include "futuopend.ports" (dict "ctx" $ctx) | fromYamlArray
*/}}
{{- define "futuopend.ports" -}}
{{- $f := .ctx.Values.futuopend | default dict -}}
{{- $ports := list (dict "name" "api" "containerPort" (int ($f.apiPort | default 11111)) "protocol" "TCP") -}}
{{- if gt (int ($f.telnetPort | default 0)) 0 -}}
{{- $ports = append $ports (dict "name" "telnet" "containerPort" (int $f.telnetPort) "protocol" "TCP") -}}
{{- end -}}
{{- toYaml $ports -}}
{{- end -}}

{{/*
Service ports of one account. Same list, but with the service port and a named
targetPort so the Service follows a changed apiPort instead of pinning a number.
Usage: include "futuopend.servicePorts" (dict "ctx" $ctx) | fromYamlArray
*/}}
{{- define "futuopend.servicePorts" -}}
{{- $v := .ctx.Values -}}
{{- $f := $v.futuopend | default dict -}}
{{- $main := ($v.service | default dict).main | default dict -}}
{{- $apiPort := dict "name" "api" "port" (int ($f.apiPort | default 11111)) "targetPort" "api" "protocol" "TCP" -}}
{{- if and $main.nodePort (eq ($main.type | default "ClusterIP") "NodePort") -}}
{{- $_ := set $apiPort "nodePort" (int $main.nodePort) -}}
{{- end -}}
{{- $ports := list $apiPort -}}
{{- if gt (int ($f.telnetPort | default 0)) 0 -}}
{{- $ports = append $ports (dict "name" "telnet" "port" (int $f.telnetPort) "targetPort" "telnet" "protocol" "TCP") -}}
{{- end -}}
{{- toYaml $ports -}}
{{- end -}}

{{/*
Container arguments for one account.

Flags rather than FutuOpenD.xml wherever a flag exists: command-line values win
over the file, and the file shipped in the image then stays untouched. Notes on
the non-obvious ones:

  -console=0        the interactive console redraws a ">>>" prompt with padding
                    and produced ~400 KB in 22 s in testing - useless in
                    `kubectl logs`. With 0 the console is silent and the log
                    file below is the record.
  -no_monitor=1     do not fork a supervisor process. Without it OpenD
                    backgrounds itself, PID 1 exits and the Pod restart-loops.
  -api_ip=0.0.0.0   the shipped config listens on 127.0.0.1, which no other Pod
                    could reach; a Service in front of it would never work.
  -data_dir         the state directory. F3CNN/Device.dat (the device identity
                    that decides whether a login counts as a new device and
                    triggers SMS verification) lives here, which is why it is a
                    PVC and not an emptyDir.
  -log_path         OpenD writes <log_path>/Log/*.log. Kept on the PVC so the
                    login result survives the Pod.

Credentials come from environment variables filled from a Secret, referenced
here as $(FUTU_LOGIN_ACCOUNT) / $(FUTU_LOGIN_PWD_MD5) so the Kubernetes
kubelet-substituted values never appear in the Pod spec.
Usage: include "futuopend.args" (dict "ctx" $ctx) | fromYamlArray
*/}}
{{- define "futuopend.args" -}}
{{- $v := .ctx.Values -}}
{{- $f := $v.futuopend | default dict -}}
{{- $mount := $v.persistence.mountPath | default "/data" -}}
{{- $args := list
      "-console=0"
      "-no_monitor=1"
      "-api_ip=0.0.0.0"
      (printf "-api_port=%d" (int ($f.apiPort | default 11111)))
      (printf "-lang=%s" ($f.lang | default "chs"))
      (printf "-log_level=%s" ($f.logLevel | default "info"))
      (printf "-data_dir=%s" $mount)
      (printf "-log_path=%s/log" $mount) -}}
{{- if $v.loginAccount -}}
{{- $args = append $args "-login_account=$(FUTU_LOGIN_ACCOUNT)" -}}
{{- end -}}
{{- if $v.loginByRemember -}}
{{- $args = append $args "-login_by_remember=1" -}}
{{- else if $v.loginPwdMd5 -}}
{{- $args = append $args "-login_pwd_md5=$(FUTU_LOGIN_PWD_MD5)" -}}
{{- end -}}
{{- /* loginRegion sits at the account level, next to the other login fields. */ -}}
{{- with $v.loginRegion }}{{ $args = append $args (printf "-login_region=%s" .) }}{{ end -}}
{{- if gt (int ($f.telnetPort | default 0)) 0 -}}
{{- $args = append $args (printf "-telnet_port=%d" (int $f.telnetPort)) -}}
{{- $args = append $args "-telnet_ip=0.0.0.0" -}}
{{- end -}}
{{- with $v.rsaPrivateKey -}}
{{- $args = append $args (printf "-rsa_private_key=%s/%s" (.mountPath | default "/etc/futuopend/rsa") .key) -}}
{{- end -}}
{{- with $f.simulateTrade }}{{ $args = append $args (printf "-simulate_trade=%s" .) }}{{ end -}}
{{- with $f.futureTradeApiTimeZone }}{{ $args = append $args (printf "-future_trade_api_time_zone=%s" .) }}{{ end -}}
{{- range $f.extraArgs }}{{ $args = append $args . }}{{ end -}}
{{- toYaml $args -}}
{{- end -}}

{{/*
Credential environment of one account. Both keys exist in the chart-rendered
Secret and in an existingSecret, so the reference is the same either way.
Usage: include "futuopend.env" (dict "ctx" $ctx) | fromYamlArray
*/}}
{{- define "futuopend.env" -}}
{{- $v := .ctx.Values -}}
{{- if $v.loginAccount -}}
{{- $name := include "futuopend.secretName" (dict "ctx" .ctx) -}}
{{- $env := list (dict "name" "FUTU_LOGIN_ACCOUNT" "valueFrom" (dict "secretKeyRef" (dict "name" $name "key" "loginAccount"))) -}}
{{- if and $v.loginPwdMd5 (not $v.loginByRemember) -}}
{{- $env = append $env (dict "name" "FUTU_LOGIN_PWD_MD5" "valueFrom" (dict "secretKeyRef" (dict "name" $name "key" "loginPwdMd5"))) -}}
{{- end -}}
{{- toYaml $env -}}
{{- end -}}
{{- end -}}

{{/*
Extra volumes of one account: the config ConfigMap (only when the account sets
futuopend.config) and the RSA key Secret. The persistence claim is added by
common.podTemplate itself. Usage: include "futuopend.volumes" (dict "ctx" $ctx) | fromYamlArray
*/}}
{{- define "futuopend.volumes" -}}
{{- $v := .ctx.Values -}}
{{- $volumes := list -}}
{{- if $v.futuopend.config -}}
{{- $volumes = append $volumes (dict "name" "config" "configMap" (dict "name" (include "common.fullname" .ctx))) -}}
{{- end -}}
{{- with $v.rsaPrivateKey -}}
{{- $volumes = append $volumes (dict "name" "rsa" "secret" (dict "secretName" .secretName)) -}}
{{- end -}}
{{- toYaml $volumes -}}
{{- end -}}

{{/*
Mounts matching futuopend.volumes. The config is mounted at the fixed path the
entrypoint looks at, and is copied from there into the writable state directory
because a ConfigMap mount itself is read-only.
Usage: include "futuopend.volumeMounts" (dict "ctx" $ctx) | fromYamlArray
*/}}
{{- define "futuopend.volumeMounts" -}}
{{- $v := .ctx.Values -}}
{{- $mounts := list -}}
{{- if $v.futuopend.config -}}
{{- $mounts = append $mounts (dict "name" "config" "mountPath" "/etc/futuopend" "readOnly" true) -}}
{{- end -}}
{{- with $v.rsaPrivateKey -}}
{{- $mounts = append $mounts (dict "name" "rsa" "mountPath" (.mountPath | default "/etc/futuopend/rsa") "readOnly" true) -}}
{{- end -}}
{{- toYaml $mounts -}}
{{- end -}}

{{/*
Deployment of one account.

common.deployment is not used here: it renders neither strategy nor a pinned
replica count, and this workload needs both. Recreate, because the state PVC is
ReadWriteOnce - a rolling update would start the replacement Pod while the old
one still holds the claim, which either multi-attaches (stuck Pending) or, on
the same node, briefly runs two logins of the same account. replicas is 1 for
the same reason (futuopend.validate rejects anything else).

Everything else - pod spec, probes, env, volumes, mounts, ports, scheduling -
comes from common.podTemplate, which reads it all out of the account context.
Usage: include "futuopend.deployments" (dict "ctx" $)
*/}}
{{- define "futuopend.deployments" -}}
{{- $root := .ctx -}}
{{- include "futuopend.validate" (dict "ctx" $root) -}}
{{- /* The ServiceAccount is release-wide, so its name has to come from the root
       context: common.serviceAccountName on the account context would resolve
       through fullnameOverride and point at a ServiceAccount that does not
       exist. */ -}}
{{- $serviceAccountName := include "common.serviceAccountName" $root -}}
{{- range $acct := $root.Values.accounts -}}
{{- $v := mergeOverwrite (deepCopy $root.Values) (deepCopy $acct) -}}
{{- $_ := set $v "nameOverride" (include "futuopend.accountName" (dict "ctx" $root "account" $acct)) -}}
{{- $_ := set $v "fullnameOverride" (include "futuopend.accountFullname" (dict "ctx" $root "account" $acct)) -}}
{{- $ctx := dict "Values" $v "Chart" $root.Chart "Release" $root.Release -}}
{{- $w := $v.workload | default dict -}}
{{- /* The podTemplate reads env/volumes/mounts/ports off the workload values,
       so the derived ones are merged into that list rather than passed as
       overrides - passing an override would drop whatever the user put in
       workload.env / workload.volumes for this account. */ -}}
{{- $_ := set $w "ports" (include "futuopend.ports" (dict "ctx" $ctx) | fromYamlArray) -}}
{{- /* Derived args first, so anything the user puts in workload.args can
       override them; futuopend.extraArgs is the narrower way to add flags. */ -}}
{{- $_ := set $w "args" (concat (include "futuopend.args" (dict "ctx" $ctx) | fromYamlArray) ($w.args | default list)) -}}
{{- $env := include "futuopend.env" (dict "ctx" $ctx) | fromYamlArray -}}
{{- if $env }}{{ $_ := set $w "env" (concat $env ($w.env | default list)) }}{{ end -}}
{{- $volumes := include "futuopend.volumes" (dict "ctx" $ctx) | fromYamlArray -}}
{{- if $volumes }}{{ $_ := set $w "volumes" (concat ($w.volumes | default list) $volumes) }}{{ end -}}
{{- $mounts := include "futuopend.volumeMounts" (dict "ctx" $ctx) | fromYamlArray -}}
{{- if $mounts }}{{ $_ := set $w "volumeMounts" (concat ($w.volumeMounts | default list) $mounts) }}{{ end -}}
{{- /* Roll the Pod when the credentials change: the Secret is only read at
       container start, so without this an edited password would keep running
       the old one until something else restarted the Pod. Skipped when the
       Secret is the user's own - the chart cannot see its contents. */ -}}
{{- if not $v.existingSecret -}}
{{- $_ := set $v "podAnnotations" (merge (dict "checksum/credentials" (include "futuopend.credentialsChecksum" (dict "ctx" $ctx))) ($v.podAnnotations | default dict)) -}}
{{- end -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "common.fullname" $ctx }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
spec:
  replicas: 1
  strategy:
    {{- toYaml ($w.strategy | default (dict "type" "Recreate")) | nindent 4 }}
  selector:
    matchLabels:
      {{- include "common.selectorLabels" $ctx | nindent 6 }}
  template:
    {{- include "common.podTemplate" (dict "ctx" $ctx "serviceAccountName" $serviceAccountName) | nindent 4 }}
---
{{- end -}}
{{- end -}}

{{/*
Checksum of the credential fields, for the pod annotation above.
Usage: include "futuopend.credentialsChecksum" (dict "ctx" $ctx)
*/}}
{{- define "futuopend.credentialsChecksum" -}}
{{- $v := .ctx.Values -}}
{{- printf "%s|%s" (toString $v.loginAccount) (toString $v.loginPwdMd5) | sha256sum -}}
{{- end -}}

{{/*
Service of one account: <release>-<chart>-<account>, selecting only that
account's Pod. Type comes from service.main.type so an account can be published
outside the cluster (the API is raw TCP, so an Ingress cannot front it).
Usage: include "futuopend.services" (dict "ctx" $)
*/}}
{{- define "futuopend.services" -}}
{{- $root := .ctx -}}
{{- range $acct := $root.Values.accounts -}}
{{- $v := mergeOverwrite (deepCopy $root.Values) (deepCopy $acct) -}}
{{- $_ := set $v "nameOverride" (include "futuopend.accountName" (dict "ctx" $root "account" $acct)) -}}
{{- $_ := set $v "fullnameOverride" (include "futuopend.accountFullname" (dict "ctx" $root "account" $acct)) -}}
{{- $ctx := dict "Values" $v "Chart" $root.Chart "Release" $root.Release -}}
{{- $main := ($v.service | default dict).main | default dict -}}
{{- $svc := dict "type" ($main.type | default "ClusterIP") "ports" (include "futuopend.servicePorts" (dict "ctx" $ctx) | fromYamlArray) -}}
{{- with $main.annotations }}{{ $_ := set $svc "annotations" . }}{{ end -}}
{{- with $main.labels }}{{ $_ := set $svc "labels" . }}{{ end -}}
{{- with $main.externalTrafficPolicy }}{{ $_ := set $svc "externalTrafficPolicy" . }}{{ end -}}
{{- with $main.internalTrafficPolicy }}{{ $_ := set $svc "internalTrafficPolicy" . }}{{ end -}}
{{- include "common.service" (dict "ctx" $ctx "services" (dict "main" $svc)) }}
{{- end -}}
{{- end -}}

{{/*
PVC of one account. Never shared: it holds F3CNN/Device.dat, and two instances
built on the same device identity re-trigger the device-lock verification.
common.pvc renders nothing when persistence is off or satisfied by an existing
claim, so its output is checked before the document separator is emitted - two
accounts in one file would otherwise run together into invalid YAML.
Usage: include "futuopend.pvcs" (dict "ctx" $)
*/}}
{{- define "futuopend.pvcs" -}}
{{- $root := .ctx -}}
{{- range $acct := $root.Values.accounts -}}
{{- $v := mergeOverwrite (deepCopy $root.Values) (deepCopy $acct) -}}
{{- $_ := set $v "nameOverride" (include "futuopend.accountName" (dict "ctx" $root "account" $acct)) -}}
{{- $_ := set $v "fullnameOverride" (include "futuopend.accountFullname" (dict "ctx" $root "account" $acct)) -}}
{{- $ctx := dict "Values" $v "Chart" $root.Chart "Release" $root.Release -}}
{{- $pvc := include "common.pvc" (dict "ctx" $ctx) -}}
{{- if trim $pvc }}
---
{{ $pvc }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
FutuOpenD.xml of one account, only when the account sets futuopend.config.

Flags cover everything with a command-line equivalent, so this exists for the
handful of settings that only exist in the file: push_proto_type,
qot_push_frequency, pdt_protection, dtcall_confirmation. The rendered file is
complete rather than partial - the binary expects a full config - with the
documented defaults below and the account's keys merged over them.
Usage: include "futuopend.configmaps" (dict "ctx" $)
*/}}
{{- define "futuopend.configmaps" -}}
{{- $root := .ctx -}}
{{- $defaults := dict
      "ip" "0.0.0.0"
      "api_port" 11111
      "lang" "chs"
      "log_level" "info"
      "push_proto_type" 0
      "price_reminder_push" 1
      "auto_hold_quote_right" 1
      "future_trade_api_time_zone" "UTC+8"
      "pdt_protection" 1
      "dtcall_confirmation" 1 -}}
{{- range $acct := $root.Values.accounts -}}
{{- $v := mergeOverwrite (deepCopy $root.Values) (deepCopy $acct) -}}
{{- $f := $v.futuopend | default dict -}}
{{- if $f.config -}}
{{- $_ := set $v "nameOverride" (include "futuopend.accountName" (dict "ctx" $root "account" $acct)) -}}
{{- $_ := set $v "fullnameOverride" (include "futuopend.accountFullname" (dict "ctx" $root "account" $acct)) -}}
{{- $ctx := dict "Values" $v "Chart" $root.Chart "Release" $root.Release -}}
{{- /* The flags win over this file anyway, so mirror the effective values of
       the ones that appear in both rather than leaving the file's stale
       defaults in place. */ -}}
{{- $cfg := mergeOverwrite (deepCopy $defaults) (dict "ip" "0.0.0.0" "api_port" (int ($f.apiPort | default 11111)) "lang" ($f.lang | default "chs") "log_level" ($f.logLevel | default "info")) (deepCopy $f.config) -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "common.fullname" $ctx }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
data:
  FutuOpenD.xml: |
    <futu_opend>
    {{- range $k, $val := $cfg }}
        <{{ $k }}>{{ $val }}</{{ $k }}>
    {{- end }}
    </futu_opend>
---
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Credential Secret of one account, skipped when the account points at an
existingSecret. Only the MD5 of the password is ever handled: the binary rejects
a plaintext -login_pwd.
Usage: include "futuopend.secrets" (dict "ctx" $)
*/}}
{{- define "futuopend.secrets" -}}
{{- $root := .ctx -}}
{{- range $acct := $root.Values.accounts -}}
{{- if not $acct.existingSecret -}}
{{- $v := mergeOverwrite (deepCopy $root.Values) (deepCopy $acct) -}}
{{- $_ := set $v "nameOverride" (include "futuopend.accountName" (dict "ctx" $root "account" $acct)) -}}
{{- $_ := set $v "fullnameOverride" (include "futuopend.accountFullname" (dict "ctx" $root "account" $acct)) -}}
{{- $ctx := dict "Values" $v "Chart" $root.Chart "Release" $root.Release -}}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "common.fullname" $ctx }}
  labels:
    {{- include "common.labels" $ctx | nindent 4 }}
type: Opaque
stringData:
  loginAccount: {{ $acct.loginAccount | quote }}
  {{- with $acct.loginPwdMd5 }}
  loginPwdMd5: {{ . | quote }}
  {{- end }}
---
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Helm test per account. A plain TCP connect, because the API is raw TCP carrying
protobuf - common.testConnection is not used, it wgets an HTTP endpoint. It
proves the account's Service reaches its Pod; a failed login still leaves the
port listening, so check the log on the PVC for the login itself.
Usage: include "futuopend.testPods" (dict "ctx" $)
*/}}
{{- define "futuopend.testPods" -}}
{{- $root := .ctx -}}
{{- range $acct := $root.Values.accounts -}}
{{- $v := mergeOverwrite (deepCopy $root.Values) (deepCopy $acct) -}}
{{- $_ := set $v "nameOverride" (include "futuopend.accountName" (dict "ctx" $root "account" $acct)) -}}
{{- $_ := set $v "fullnameOverride" (include "futuopend.accountFullname" (dict "ctx" $root "account" $acct)) -}}
{{- $ctx := dict "Values" $v "Chart" $root.Chart "Release" $root.Release -}}
{{- $port := int (($v.futuopend | default dict).apiPort | default 11111) -}}
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
    - name: nc
      image: {{ $v.testImage | default "busybox" }}
      # -w bounds the wait: a port that accepts but never answers would
      # otherwise hang the test until busybox gives up. </dev/null closes stdin
      # so nc exits as soon as the connection is established.
      command: ['sh']
      args: ['-c', 'nc -w 10 {{ include "common.fullname" $ctx }} {{ $port }} </dev/null']
  restartPolicy: Never
---
{{- end -}}
{{- end -}}

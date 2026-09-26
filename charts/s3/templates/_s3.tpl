{{/*
Chart private helpers. They render the parts of the driver pod that depend on
more than one value, so templates/daemonset.yaml can hand them to
common.daemonset through its "volumes" and "extraContainers" overrides.

Usage: include "s3.volumes" . | fromYaml
*/}}

{{/*
Host paths the driver mounts from the node. The plugin directory is namespaced
by the driver name, so the list is rendered here instead of being listed in
values.yaml.
*/}}
{{- define "s3.volumes" -}}
- name: registration-dir
  hostPath:
    path: /var/lib/kubelet/plugins_registry/
    type: DirectoryOrCreate
- name: plugin-dir
  hostPath:
    path: /var/lib/kubelet/plugins/{{ .Values.storageClass.provisioner }}
    type: DirectoryOrCreate
- name: stage-dir
  hostPath:
    path: /var/lib/kubelet/plugins/kubernetes.io/csi
    type: DirectoryOrCreate
- name: pods-mount-dir
  hostPath:
    path: /var/lib/kubelet/pods
    type: Directory
- name: fuse-device
  hostPath:
    path: /dev/fuse
- name: systemd-control
  hostPath:
    path: /run/systemd
    type: DirectoryOrCreate
{{- end -}}

{{/*
CSI node-driver-registrar sidecar. Rendered as a container list so it can be
passed to common.daemonset through extraContainers.
*/}}
{{- define "s3.registrarContainers" -}}
- name: driver-registrar
  image: {{ include "common.imageRef" (dict "image" .Values.registrar "appVersion" "") }}
  imagePullPolicy: {{ .Values.registrar.pullPolicy }}
  args:
    - "--kubelet-registration-path=$(DRIVER_REG_SOCK_PATH)"
    - "--v=4"
    - "--csi-address=$(ADDRESS)"
  env:
    - name: ADDRESS
      value: /csi/csi.sock
    - name: DRIVER_REG_SOCK_PATH
      value: /var/lib/kubelet/plugins/{{ .Values.storageClass.provisioner }}/csi.sock
    - name: KUBE_NODE_NAME
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
  volumeMounts:
    - name: plugin-dir
      mountPath: /csi
    - name: registration-dir
      mountPath: /registration/
{{- end -}}

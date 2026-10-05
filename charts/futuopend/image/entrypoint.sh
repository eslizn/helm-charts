#!/bin/sh
# Futu OpenD container entrypoint.
#
# Exists for two reasons:
#
#  1. FutuOpenD rewrites its config file when settings change, and a ConfigMap
#     mount is read-only. When a config is mounted (the chart does that for
#     accounts that set futuopend.config) it is copied into the writable state
#     directory and -cfg_file points at the copy. Without a mounted config the
#     FutuOpenD.xml shipped in /opt/futuopend is used as-is.
#
#  2. The state directory has to be writable, and a failure there otherwise
#     surfaces as an OpenD crash loop with no hint about the cause. When a PVC
#     is mounted and podSecurityContext.fsGroup does not match the container's
#     gid, this is the error that says so.
#
# exec, so FutuOpenD is PID 1 and gets the kubelet's SIGTERM directly - it is
# also why the chart passes -no_monitor=1: without it OpenD forks a supervisor,
# PID 1 exits and the Pod restart-loops.
set -eu

data_dir=/data
for arg in "$@"; do
  case "$arg" in
    -data_dir=*) data_dir="${arg#-data_dir=}" ;;
  esac
done

if [ ! -d "$data_dir" ]; then
  echo "entrypoint: state directory $data_dir does not exist." >&2
  echo "entrypoint: mount a volume there, or point -data_dir at one." >&2
  exit 1
fi

if [ ! -w "$data_dir" ]; then
  echo "entrypoint: state directory $data_dir is not writable by uid $(id -u)." >&2
  echo "entrypoint: with a PVC, podSecurityContext.fsGroup must be set to the" >&2
  echo "entrypoint: container's gid (the chart sets fsGroup 10001 by default)." >&2
  exit 1
fi

if [ -f /etc/futuopend/FutuOpenD.xml ]; then
  cp -f /etc/futuopend/FutuOpenD.xml "$data_dir/FutuOpenD.xml"
  set -- "-cfg_file=$data_dir/FutuOpenD.xml" "$@"
fi

exec /opt/futuopend/FutuOpenD "$@"

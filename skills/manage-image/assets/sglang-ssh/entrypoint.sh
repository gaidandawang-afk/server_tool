#!/usr/bin/env bash
set -euo pipefail

authorized_keys_source="${AUTHORIZED_KEYS_SOURCE:-/run/server-tool/authorized_keys}"
host_key_dir="${HOST_KEY_DIR:-/etc/ssh/persistent-host-keys}"
gpu_list="${CUDA_VISIBLE_DEVICES:-}"

if [[ ! -s "${authorized_keys_source}" ]]; then
  echo "authorized key file is missing or empty: ${authorized_keys_source}" >&2
  exit 1
fi

if [[ ! "${gpu_list}" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
  echo "CUDA_VISIBLE_DEVICES must be a comma-separated GPU index list" >&2
  exit 1
fi

printf 'SetEnv CUDA_VISIBLE_DEVICES=%s\n' "${gpu_list}" \
  > /etc/ssh/sshd_config.d/98-server-tool-runtime.conf

install -d -m 0700 /root/.ssh
install -m 0600 "${authorized_keys_source}" /root/.ssh/authorized_keys
install -d -m 0755 /run/sshd
install -d -m 0700 "${host_key_dir}"

if [[ ! -s "${host_key_dir}/ssh_host_ed25519_key" ]]; then
  ssh-keygen -q -t ed25519 -N "" -f "${host_key_dir}/ssh_host_ed25519_key"
fi

if [[ ! -s "${host_key_dir}/ssh_host_rsa_key" ]]; then
  ssh-keygen -q -t rsa -b 4096 -N "" -f "${host_key_dir}/ssh_host_rsa_key"
fi

chmod 0600 "${host_key_dir}"/ssh_host_*_key
/usr/sbin/sshd -t

exec /usr/sbin/sshd -D -e

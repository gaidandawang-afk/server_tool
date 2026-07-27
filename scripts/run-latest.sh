#!/usr/bin/env bash
set -euo pipefail

container_name="${CONTAINER_NAME:-sglang-ssh-v0.5.16}"
image="${SSH_IMAGE:-server-tool/sglang-ssh:v0.5.16}"
ssh_port="${SSH_PORT:-6200}"
persist_root="${PERSIST_ROOT:-/data2/iws}"
gpu_list="${CUDA_VISIBLE_DEVICES:-0,1,2,3,4,5,6,7}"
authorized_keys="${persist_root}/ssh/authorized_keys"
host_keys="${persist_root}/ssh/host-keys"

if docker container inspect "${container_name}" >/dev/null 2>&1; then
  echo "container already exists: ${container_name}" >&2
  exit 1
fi

if ss -lntH | awk '{print $4}' | grep -Eq ":${ssh_port}$"; then
  echo "TCP port is already in use: ${ssh_port}" >&2
  exit 1
fi

if ! docker image inspect "${image}" >/dev/null 2>&1; then
  echo "image is not available locally: ${image}" >&2
  exit 1
fi

if [[ ! -s "${authorized_keys}" ]]; then
  echo "authorized key file is missing or empty: ${authorized_keys}" >&2
  exit 1
fi

mkdir -p \
  "${host_keys}" \
  "${persist_root}/workspace" \
  "${persist_root}/cache/huggingface" \
  "${persist_root}/cache/sglang" \
  "${persist_root}/cache/torch"

docker run --detach \
  --name "${container_name}" \
  --hostname "${container_name}" \
  --restart unless-stopped \
  --gpus all \
  --shm-size 32g \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  --publish "${ssh_port}:22" \
  --env "CUDA_VISIBLE_DEVICES=${gpu_list}" \
  --env "NVIDIA_VISIBLE_DEVICES=all" \
  --volume "${authorized_keys}:/run/server-tool/authorized_keys:ro" \
  --volume "${host_keys}:/etc/ssh/persistent-host-keys" \
  --volume "/data1:/data1" \
  --volume "/data2:/data2" \
  --volume "${persist_root}/workspace:/workspace" \
  --volume "${persist_root}/cache/huggingface:/root/.cache/huggingface" \
  --volume "${persist_root}/cache/sglang:/root/.cache/sglang" \
  --volume "${persist_root}/cache/torch:/root/.cache/torch" \
  --workdir /workspace \
  "${image}"

#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  echo "usage: $0 <image> <container-name>" >&2
  exit 2
fi

image="$1"
container_name="$2"
: "${SSH_PORT:?SSH_PORT is required}"
: "${PERSIST_ROOT:?PERSIST_ROOT is required}"
: "${GPU_IDS:?GPU_IDS is required}"

if [[ ! "${SSH_PORT}" =~ ^[0-9]+$ ]]; then
  echo "SSH_PORT must be numeric" >&2
  exit 2
fi

if (( SSH_PORT < 6100 || SSH_PORT > 6300 )); then
  echo "SSH_PORT must be inside the authorized range 6100-6300" >&2
  exit 2
fi

case "${PERSIST_ROOT}" in
  /data2/iws | /data2/iws/*) ;;
  *)
    echo "PERSIST_ROOT must be /data2/iws or a child path" >&2
    exit 2
    ;;
esac

if [[ "${GPU_IDS}" == "all" ]]; then
  gpu_list="$(nvidia-smi --query-gpu=index --format=csv,noheader | paste -sd, -)"
else
  gpu_list="${GPU_IDS}"
fi

if [[ ! "${gpu_list}" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
  echo "GPU_IDS must be 'all' or a comma-separated GPU index list" >&2
  exit 2
fi

authorized_keys="${PERSIST_ROOT}/ssh/authorized_keys"
host_keys="${PERSIST_ROOT}/ssh/host-keys"

if docker container inspect "${container_name}" >/dev/null 2>&1; then
  echo "container already exists: ${container_name}" >&2
  exit 1
fi

if ss -lntH | awk '{print $4}' | grep -Eq ":${SSH_PORT}$"; then
  echo "TCP port is already in use: ${SSH_PORT}" >&2
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

image_id="$(docker image inspect --format '{{.Id}}' "${image}")"
base_image="$(
  docker image inspect \
    --format '{{index .Config.Labels "org.opencontainers.image.base.name"}}' \
    "${image}"
)"
if [[ -z "${base_image}" || "${base_image}" == "<no value>" ]]; then
  echo "image is missing org.opencontainers.image.base.name: ${image}" >&2
  exit 1
fi

mkdir -p \
  "${host_keys}" \
  "${PERSIST_ROOT}/container-manifests" \
  "${PERSIST_ROOT}/workspace" \
  "${PERSIST_ROOT}/cache/huggingface" \
  "${PERSIST_ROOT}/cache/sglang" \
  "${PERSIST_ROOT}/cache/torch"

container_id="$(docker run --detach \
  --name "${container_name}" \
  --hostname "${container_name}" \
  --restart unless-stopped \
  --gpus all \
  --shm-size 32g \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  --publish "${SSH_PORT}:22" \
  --env "CUDA_VISIBLE_DEVICES=${gpu_list}" \
  --env "NVIDIA_VISIBLE_DEVICES=all" \
  --volume "${authorized_keys}:/run/server-tool/authorized_keys:ro" \
  --volume "${host_keys}:/etc/ssh/persistent-host-keys" \
  --volume "/data1:/data1" \
  --volume "/data2:/data2" \
  --volume "${PERSIST_ROOT}/workspace:/workspace" \
  --volume "${PERSIST_ROOT}/cache/huggingface:/root/.cache/huggingface" \
  --volume "${PERSIST_ROOT}/cache/sglang:/root/.cache/sglang" \
  --volume "${PERSIST_ROOT}/cache/torch:/root/.cache/torch" \
  --workdir /workspace \
  "${image}")"

manifest="${PERSIST_ROOT}/container-manifests/${container_name}.env"
tmp_manifest="$(mktemp "${manifest}.tmp.XXXXXX")"
{
  printf 'container_name=%s\n' "${container_name}"
  printf 'container_id=%s\n' "${container_id}"
  printf 'image_tag=%s\n' "${image}"
  printf 'image_digest=%s\n' "${image_id}"
  printf 'base_image=%s\n' "${base_image}"
} >"${tmp_manifest}"
chmod 0644 "${tmp_manifest}"
mv -- "${tmp_manifest}" "${manifest}"
printf 'container_manifest=%s\n' "${manifest}"

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image_repository="${SSH_IMAGE_REPOSITORY:-server-tool/sglang-ssh}"
versions=("v0.5.13.post1" "v0.5.16")

for version in "${versions[@]}"; do
  base_image="lmsysorg/sglang:${version}"
  target_image="${image_repository}:${version}"

  if ! docker image inspect "${base_image}" >/dev/null 2>&1; then
    echo "base image is not available locally: ${base_image}" >&2
    exit 1
  fi

  docker build \
    --file "${repo_root}/docker/Dockerfile.ssh" \
    --build-arg "BASE_IMAGE=${base_image}" \
    --tag "${target_image}" \
    "${repo_root}"
done

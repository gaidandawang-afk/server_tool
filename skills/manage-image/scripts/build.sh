#!/usr/bin/env bash
set -euo pipefail

if (( $# == 0 )); then
  echo "usage: $0 <sglang-version> [<sglang-version> ...]" >&2
  exit 2
fi

skill_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
context="${skill_root}/assets/sglang-ssh"
image_repository="${SSH_IMAGE_REPOSITORY:-server-tool/sglang-ssh}"

for version in "$@"; do
  base_image="lmsysorg/sglang:${version}"
  target_image="${image_repository}:${version}"

  if ! docker image inspect "${base_image}" >/dev/null 2>&1; then
    echo "base image is not available locally: ${base_image}" >&2
    exit 1
  fi

  docker build \
    --file "${context}/Dockerfile" \
    --build-arg "BASE_IMAGE=${base_image}" \
    --tag "${target_image}" \
    "${context}"
done

#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# < 2 )); then
  echo "usage: $0 <source-root> <output-dir> [-- <build-args>...]" >&2
  exit 2
fi

source_root="${1%/}"
output_dir="${2%/}"
shift 2
if [[ "${1:-}" == "--" ]]; then
  shift
fi
build_args=("$@")

test -d "$source_root"
test -f "$source_root/build.sh"
: "${ASCEND_TOOLKIT:?ASCEND_TOOLKIT must point at the Ascend toolkit root}"
test -f "$ASCEND_TOOLKIT/set_env.sh"

export http_proxy="${http_proxy:-http://80.253.24.60:8080}"
export https_proxy="${https_proxy:-http://80.253.24.60:8080}"

(
  cd "$source_root"
  git submodule update --init --recursive
  # shellcheck disable=SC1091
  source "$ASCEND_TOOLKIT/set_env.sh"
  # Upstream build.sh builds all four modules by default and auto-detects the
  # DeepEP SOC; the default "all" target rejects a positional SOC_VERSION, so we
  # do NOT pass a SOC here. To build a single module pass it via build_args (e.g.
  # ./build.sh <src> <out> -- -a kernels Ascend910_9382).
  build_cmd=(bash build.sh)
  if (( ${#build_args[@]} > 0 )); then
    build_cmd+=("${build_args[@]}")
  fi
  "${build_cmd[@]}"
)

mkdir -p "$output_dir"
wheel_patterns=(
  "$source_root"/output/sgl_kernel_npu-*.whl
  "$source_root"/output/deep_ep-*.whl
  "$source_root"/output/attentions-*.whl
  "$source_root"/output/torch_memory_saver-*.whl
)
collected=()
for pattern in "${wheel_patterns[@]}"; do
  # shellcheck disable=SC2086
  mapfile -t matches < <(compgen -G "$pattern" || true)
  if (( ${#matches[@]} == 0 )); then
    echo "missing wheel: $pattern" >&2
    exit 1
  fi
  cp -- "${matches[0]}" "$output_dir/"
  collected+=("$output_dir/${matches[0]##*/}")
done

{
  printf 'source_root=%s\n' "$source_root"
  printf 'source_commit=%s\n' "$(git -C "$source_root" rev-parse HEAD)"
  printf 'built_at=%s\n' "$(date --iso-8601=seconds)"
  printf 'build_args=%s\n' "${build_args[*]:-}"
  sha256sum -- "${collected[@]}"
} >"$output_dir/sha256.txt"

for wheel in "${collected[@]}"; do
  printf 'built wheel: %s\n' "$wheel"
done
printf 'built manifest: %s\n' "$output_dir/sha256.txt"

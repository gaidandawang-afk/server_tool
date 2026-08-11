#!/usr/bin/env bash

# Runtime kernel selection for sgl-kernel-npu. Mirrors the CuDA
# sg_prepare_ft_runtime injection + st_record_python_package verification pattern
# in skills/test-service/scripts/sglang_ft_ops.sh, but for the NPU wheel set.
#
# Each of the four wheels (sgl_kernel_npu, deep_ep, attentions,
# torch_memory_saver) has its own independent version, so the expected version is
# read per-distribution from the immutable root's dist-info rather than assuming a
# single SGLANG_KERNEL_NPU_VERSION. SGLANG_KERNEL_NPU_VERSION is kept as an optional
# annotation only.
#
# SGLANG_KERNEL_NPU_WHEEL_SELECT selects which of the four wheels to validate and is
# expected to match what was installed into the root. Empty means all four:
# sgl_kernel_npu, deep_ep, attentions, torch_memory_saver.

# Read the installed version of a distribution from the immutable root's dist-info.
npu_installed_version() {
  local st_distribution="$1"
  python3 - "$st_distribution" "$SGLANG_KERNEL_NPU_ROOT" <<'PY'
import importlib.metadata
import pathlib
import sys

distribution, root = sys.argv[1:]
root_path = pathlib.Path(root)
# importlib.metadata dists live alongside the --target install root.
try:
    version = importlib.metadata.version(distribution)
except importlib.metadata.PackageNotFoundError:
    sys.exit(2)
# Guard: the metadata must actually resolve inside the installed root.
dists = importlib.metadata.distributions(path=[str(root_path)])
for dist in dists:
    if dist.metadata["Name"].lower().replace("-", "_") == distribution.lower().replace("-", "_"):
        print(dist.version)
        sys.exit(0)
sys.exit(3)
PY
}

npu_prepare_runtime() {
  : "${SGLANG_KERNEL_NPU_ROOT:?}"
  : "${SGLANG_KERNEL_NPU_VERSION:?}"

  export PYTHONNOUSERSITE=1
  export PYTHONPATH="$SERVER_TOOL_PROJECT_ROOT/python:$SGLANG_KERNEL_NPU_ROOT:$PYTHONPATH"

  local npu_selection="${SGLANG_KERNEL_NPU_WHEEL_SELECT:-}"
  local npu_selected
  if [[ -z "$npu_selection" ]]; then
    npu_selected="sgl_kernel_npu deep_ep attentions torch_memory_saver"
  else
    npu_selected="$npu_selection"
  fi

  local npu_module npu_expected
  for npu_module in $npu_selected; do
    npu_expected="$(npu_installed_version "$npu_module")" || {
      st_log "cannot resolve installed version for $npu_module under $SGLANG_KERNEL_NPU_ROOT"
      continue
    }
    case "$npu_module" in
      sgl_kernel_npu)
        st_record_python_package \
          sgl_kernel_npu sgl_kernel_npu "$npu_expected" \
          "$SGLANG_KERNEL_NPU_ROOT" "${SGLANG_KERNEL_NPU_REQUIRED_SYMBOL:-}"
        ;;
      deep_ep|attentions|torch_memory_saver)
        st_record_python_package \
          "$npu_module" "$npu_module" "$npu_expected" \
          "$SGLANG_KERNEL_NPU_ROOT"
        ;;
      *)
        st_log "unrecognized SGLANG_KERNEL_NPU_WHEEL_SELECT entry: $npu_module"
        ;;
    esac
  done
}

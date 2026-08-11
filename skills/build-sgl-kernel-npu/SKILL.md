---
name: build-sgl-kernel-npu
description: Build and install the Ascend NPU kernels for SGLang (sgl-kernel-npu) into an immutable version root selected at runtime.
---

# Build SGL Kernel NPU

Use this skill only when a task needs to compile the custom NPU kernels that SGLang
loads on Ascend, or to switch which compiled kernel build a runtime selects.

## Goal

Compile `sgl-kernel-npu` in an Ascend container using a fixed command chain, producing
the four wheels it ships, and optionally install a chosen subset into an immutable
version root under `/data2/iws/deps/sgl-kernel-npu`.

The four wheels are: `sgl_kernel_npu`, `deep_ep`, `attentions`, and
`torch_memory_saver`. The NPU `MoeDistributeDispatchV2` operator is a torch_npu custom
op registered by the `deep_ep` wheel's compiled `deep_ep_cpp*.so`.

## Rules

1. Build in a task-local remote worktree under the profile's `REMOTE_PROJECT_ROOT`;
   never build from a hand-edited shared checkout.
2. Derive the expected commit from local `HEAD`; do not hardcode commit hashes.
3. Run all compilation through the fixed proxy `http://80.253.24.60:8080`.
4. First `git submodule update --init --recursive`, then
   `source $ASCEND_TOOLKIT/set_env.sh`, then `bash build.sh <SOC>` where
   `SOC` is `Ascend910` or `a3`.
5. Store built wheels only under `/data2/iws/builds/sgl-kernel-npu/`. Never place
   tested source or per-task builds under the shared dependency root.
6. Install runtime dependencies following the `install-environment` parallel version
   root convention (distinct immutable version directory, refuse overwrite, do not
   touch `current`).
7. The runtime selects a kernel build only by placing that immutable version root ahead
   on `PYTHONPATH`; there is no environment variable and no sglang source change.
8. Read `references/build-guide.md` before running the build chain. Promote only
   repeated, stable leaf operations into `scripts/`.
9. Record the commit, build command, environment, wheels and SHA256 manifest as output.
10. Never decide the installed wheel subset automatically: honor the profile's
    `SGLANG_KERNEL_NPU_WHEEL_SELECT` (empty = all four).

## Kernel selection at runtime

SGLang loads `sgl_kernel_npu`, `deep_ep` and `attentions` through ordinary Python
import. To switch to a freshly compiled build, export the immutable version root first on
`PYTHONPATH` and validate that the imported module paths resolve inside that root:

- reuse `scripts/npu-runtime-prep.sh`, which mirrors the `sglang_ft_ops.sh` injection +
  `st_record_python_package` verification pattern. The expected version for each wheel
  is read from the immutable root's own `dist-info` (the four wheels have independent
  versions), not from a single `SGLANG_KERNEL_NPU_VERSION`.
- `SGLANG_KERNEL_NPU_REQUIRED_SYMBOL` is an optional auxiliary `hasattr` check on the
  `sgl_kernel_npu` module. Keep it empty unless that symbol is a real top-level
  attribute. `MoeDistributeDispatchV2` is deliberately NOT used here: it is registered
  as a torch_npu custom op (`torch_npu.npu_moe_distribute_dispatch_v2`) by the `deep_ep`
  wheel rather than being a top-level module attribute, so module import + version +
  path are the authoritative validation surface.

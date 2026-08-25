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

## Runtime pitfall: `deep_ep_cpp` top-level module shadowing

The `deep_ep` wheel ships its compiled `deep_ep_cpp*.so` only **inside** the
`deep_ep/` package (`top_level.txt = deep_ep`), but the wheel's own code does a
**top-level `import deep_ep_cpp`** (`deep_ep/buffer.py`,
`deep_ep/strategies/low_latency_strategy.py`). So even with our immutable version
root first on `PYTHONPATH`:

- `import deep_ep` / `import sgl_kernel_npu` resolve inside our root, BUT
- `import deep_ep_cpp` falls through to whichever top-level `deep_ep_cpp*.so`
  exists **earlier on `PYTHONPATH`/`sys.path`** — on an image that already carries
  an older NPU kernel build under `site-packages`, that stale `.so` wins.

A stale `.so` built from different source is NOT ABI/API-compatible: the container's
old `low_latency_dispatch` may accept 10 positional args while the freshly built
Python strategy passes 12, crashing on the first forward pass with
`low_latency_dispatch(): incompatible function arguments`. `build.sh` will not fix
this on its own — the fresh wheel is already internally consistent (12-arg `.so`
matching 12-arg Python); it is purely a module-layout/packaging gap.

**Fix:** after installing the version root, make the correct `.so` importable at the
version-root **top level**, so `import deep_ep_cpp` finds it before any
`site-packages` copy:

```bash
cp "$SGLANG_KERNEL_NPU_ROOT/deep_ep/deep_ep_cpp"*.so \
   "$SGLANG_KERNEL_NPU_ROOT/deep_ep_cpp"*.so
```

Then verify at runtime that `deep_ep_cpp.__file__` / `deep_ep.__file__` /
`sgl_kernel_npu.__file__` all resolve **inside** the selected version root (not
`site-packages`). Consider feeding this packaging gap back upstream.

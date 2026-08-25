---
name: test-service
description: Create, update, and execute committed service test contracts from reusable operation units while preserving structured evidence for every outcome.
---

# Test Service

Use this skill to run a committed service test against the branch selected by the task profile.

## Contract

Each test is expressed by:

- `TEST.md`: goal, applicable branch, topology, phases, barriers, signals, pass/fail gates and required artifacts.
- `run.sh`: mechanical setup, launch, requests, fault injection, collection and targeted cleanup.

Stable contracts live under `cases/<component>/<case>/`. Compose them from functions in
`scripts/`; do not copy common curl, status, process or precision logic into every case.

## Rules

1. Locate the exact committed contract under `cases/` and verify that it applies to the selected source branch.
2. Do not replace the requested scenario with a nearby test.
3. Verify source HEAD, shared environment, selected GPU and port range.
4. Parallelize only independent work inside the same phase.
5. Preserve causal barriers between baseline, fault, recovery and validation stages.
6. Save each parallel request's response and error independently before aggregation.
7. Bound every readiness, request and outer test wait.
8. Preserve output and provenance on both success and failure.
9. Require at least one structured assertion; exit zero alone is never a pass.
10. Keep every cold repetition in a distinct run and artifact directory.
11. Read `references/evidence.md` before creating or changing a test contract.

Task-local exploratory tests go under ignored `work/<profile>/<task>/`. Stable behavioral
contracts must be promoted into `cases/`; no committed case may source files from another project.

Run a committed case with `scripts/run-case.py`. Use `tools/server_tool.py` directly only when
the task needs nonstandard committed attachments.

## Model-specific profile settings

Committed SGLang cases take the model from `MODEL_PATH`. A profile may also select:

- `SGLANG_KERNEL_REQUIRED_SYMBOL` (default `fp8_blockwise_scaled_mm`; main-based
  SGLang with `sglang-kernel==0.4.5` uses `fp8_scaled_mm`);
- `SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS` (default `128`);
- `SGLANG_FT_MEM_FRACTION_STATIC` (default `0.75`);
- `SGLANG_FT_MOE_RUNNER_BACKEND` (default `deep_gemm`);
- `SGLANG_FT_EP_DISPATCH_ALGORITHM` (`dynamic` for ordinary launchers unless
  explicitly selected; rejoin launchers default to `static`);
- `SGLANG_FT_DETERMINISTIC_INFERENCE` (`1` for ordinary FT launchers and `0`
  for native no-FT launchers unless explicitly selected);
- `SGLANG_FT_RANDOM_SEED` for an optional fixed non-negative seed;
- `SGLANG_DEEPEP_BF16_DISPATCH` (`0` by default; use `1` for a compatible
  DeepSeek BF16/DeepGEMM environment);
- `SGLANG_FT_PRECISION_ORACLE_FAMILY` (default
  `qwen-fp8-d4t4e4-count10-no-overlap`);
- `SGLANG_FT_RELIABLE_ORACLE_ID` for the optional four-token rejoin request.

Ordinary fault-scenario gates resolve their oracle as
`<family>-rank<rank>-r<redundant-experts>` and accept only sequences already listed in that
entry's `known_output_ids`. If an entry has no known-sequence list, the gate falls back to
its canonical `output_ids`. A test run must never register its own output as passing.
Strict token equality is reserved for dedicated precision-attribution runs with matched
native no-FT controls. Use a distinct flat profile, task root and artifact root for each
model and configuration.

## Ascend (NPU) runtime kernel selection and smoke verification

The committed FT cases above are CUDA-flow oriented. On an Ascend/NPU host the same
sglang service should be verified against the **selected** NPU kernel build, using the
`build-sgl-kernel-npu` and `ascend-sglang-env-replication` skills. Follow this general
path (values are profile/config-driven, not literal constants):

1. In the Ascend container, `source <ascend-toolkit>/set_env.sh` (e.g.
   `/usr/local/Ascend/ascend-toolkit/set_env.sh`) so `libhccl.so` and the CANN solver
   resolve.
2. Select the kernel version root via
   `skills/build-sgl-kernel-npu/scripts/npu-runtime-prep.sh` (or the equivalent:
   `PYTHONNOUSERSITE=1`, the immutable version root **first** on `PYTHONPATH`, then
   verify `sgl_kernel_npu` / `deep_ep` / `deep_ep_cpp` `. __file__` all resolve inside
   that root and that `importlib.metadata.version` matches the root's `dist-info`).
   See that skill for the `deep_ep_cpp` top-level shadowing pitfall and its top-level
   `.so` fix.
3. Restrict to the dies/GPUs the task owns with the Ascend device selector
   (`ASCEND_RT_VISIBLE_DEVICES`), pick a free port, and launch
   `python3 -m sglang.launch_server` with a **non-FT** flag set when the installed
   sglang build lacks the FT/elastic-EP/`mooncake`-a2a machinery (drop
   `--enable-fault-tolerance`, `--elastic-ep-backend`, use `--moe-a2a-backend deepep`
   instead of `mooncake` when the compiled mooncake bindings are absent).
4. Prove the service is actually on the selected nodes: `npu-smi` shows elevated HBM
   only on the owned dies; `sglangschedul` workers map to exactly them.
5. Pass gates: `/health_generate` returns 200 and `/generate` returns real text
   without a forward-pass crash; then tear down only the launched process group and
   confirm port + dies return to baseline.

Do not assume the image's bundled kernel is the one you are testing — ALWAYS confirm
the import path resolves to the selected version root (the image commonly carries an
older `sgl_kernel_npu`/`deep_ep` under `site-packages`).

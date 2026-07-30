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

- `SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS` (default `128`);
- `SGLANG_FT_MEM_FRACTION_STATIC` (default `0.75`);
- `SGLANG_FT_MOE_RUNNER_BACKEND` (default `deep_gemm`);
- `SGLANG_DEEPEP_BF16_DISPATCH` (`0` by default; use `1` for a compatible
  DeepSeek BF16/DeepGEMM environment);
- `SGLANG_FT_PRECISION_ORACLE_FAMILY` (default
  `qwen-fp8-d4t4e4-count10-no-overlap`);
- `SGLANG_FT_RELIABLE_ORACLE_ID` for the optional four-token rejoin request.

Ordinary exact-token gates resolve their oracle as
`<family>-rank<rank>-r<redundant-experts>`. The resolved ID must already exist in
`assets/sglang/precision_oracles.json`; a test run must never register its own output as a
passing oracle. Use a distinct flat profile, task root and artifact root for each model and
configuration.

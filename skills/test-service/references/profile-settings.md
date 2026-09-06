## Model-specific profile settings

Committed SGLang cases take the model from `MODEL_PATH`. A profile may also select:

- `SGLANG_KERNEL_REQUIRED_SYMBOL` (default `fp8_blockwise_scaled_mm`; main-based
  SGLang with `sglang-kernel==0.4.5` uses `fp8_scaled_mm`);
- `SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS` (default `128`);
- `SGLANG_FT_MEM_FRACTION_STATIC` (default `0.75`);
- `SGLANG_FT_MOE_RUNNER_BACKEND` (default `deep_gemm`);
- `SGLANG_FT_MOONCAKE_TRANSPORT_MODE` (`mixed-nvlink` by default, or
  `tcp-fallback` to force TCP and the Mooncake EP Python fallback);
- `SGLANG_FT_EP_DISPATCH_ALGORITHM` (`dynamic` for ordinary launchers unless
  explicitly selected; rejoin launchers default to `static`);
- `SGLANG_FT_DETERMINISTIC_INFERENCE` (`1` for ordinary FT launchers and `0`
  for native no-FT launchers unless explicitly selected);
- `SGLANG_FT_OVERLAP_SCHEDULE` (`0` by default for ordinary FT launchers; set
  `1` only in contracts that include concurrent requests and explicit overlap
  coverage assertions);
- `SGLANG_FT_RANDOM_SEED` for an optional fixed non-negative seed;
- `SGLANG_FT_CUDA_GRAPH_MODE` (`disabled` by default, or `decode-only` for
  full decode CUDA Graph with prefill graphs disabled in rejoin launchers);
- `SGLANG_DEEPEP_BF16_DISPATCH` (`0` by default; use `1` for a compatible
  DeepSeek BF16/DeepGEMM environment);
- `SGLANG_FT_PRECISION_ORACLE_FAMILY` (default
  `qwen-fp8-d4t4e4-count10-no-overlap`);
- `SGLANG_FT_RELIABLE_ORACLE_ID` for the optional four-token rejoin request.
- `SGLANG_FT_CONTROL_PHASE_TIMEOUT_SEC` (test default `60`) and
  `SGLANG_FT_CONTROL_WAIT_TIMEOUT_SEC` (test default `90`); the observation
  timeout must be greater than the product control-phase timeout.
- `SGLANG_FT_PAUSE_TIMEOUT_SEC` (default `300`; timeout-specific contracts may
  shorten it explicitly).
- `SGLANG_FT_ELASTIC_EP_SCALE_TIMEOUT_SEC` (test default `150`) and
  `SGLANG_FT_ELASTIC_EP_WAIT_TIMEOUT_SEC` (test default `180`) for the separate
  runtime Elastic EP scale/recovery path.
Ordinary fault-scenario gates resolve their oracle as
`<family>-rank<rank>-r<redundant-experts>` and accept only sequences already listed in that
entry's `known_output_ids`. If an entry has no known-sequence list, the gate falls back to
its canonical `output_ids`. A test run must never register its own output as passing.
Strict token equality is reserved for dedicated precision-attribution runs with matched
native no-FT controls. Use a distinct flat profile, task root and artifact root for each
model and configuration.

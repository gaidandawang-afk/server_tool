# DeepSeek-V2-Lite r64 profile validation — 2026-07-30

## Fixed inputs

- SGLang branch and commit:
  `worktree-dp-only-ft-revise@7f553fee0991e90566ac9c173eae89d9b2c52609`
- Model: `/data1/models/DeepSeek-V2-Lite-Chat`
- Topology: TP=4, DP=4, EP=4 on GPU `4,5,6,7`
- Redundant experts: `64`
- Memory fraction: `0.75`
- MoE runner: `deep_gemm`
- DeepEP BF16 dispatch: `1`
- `sgl-deep-gemm`: `0.1.4.post1`, with
  `m_grouped_bf16_gemm_nt_masked`
- Container, SGLang kernel and Mooncake identities match
  `VALIDATION-2026-07-30-REVISE.md`.
- Artifact root:
  `work/sglang-dp-only-ft-revise-deepseek-v2-lite-r64/artifacts`

## Configuration finding

The first diagnostic run,
`deepseek-v2-lite-r64-continue-baseline-7f553fee-20260730`, proved that the model and
64 redundant experts loaded, but its first request returned HTTP 503 because the inherited
FP8 path raised `forward_deepgemm_masked is deprecated`. The artifact is retained.

The profile now transports and records `SGLANG_FT_MOE_RUNNER_BACKEND` and
`SGLANG_DEEPEP_BF16_DISPATCH`. Keeping `deep_gemm` and setting BF16 dispatch to `1`
selects the compatible kernel path in the current environment.

## Results

| Contract | Run | Assertions | Result |
| --- | --- | ---: | --- |
| `fault-kill-continue-status-only` | `deepseek-v2-lite-r64-bf16-continue-v2-7f553fee-20260730` | 28 | PASS |
| `fault-kill-continue-status-only` | `deepseek-v2-lite-r64-bf16-continue-v3-7f553fee-20260730` | 28 | PASS |
| `fault-rejection-contracts` | `deepseek-v2-lite-r64-rejection-oracle-7f553fee-20260730` | 29 | PASS |

The two independent cold baseline runs returned
`[185,185,16,185,17,185,18,185,19,185]` on all four ranks. Their eight baseline
responses matched exactly, so the four
`deepseek-v2-lite-chat-bf16-d4t4e4-count10-no-overlap-rankN-r64` entries were added to
the committed precision registry.

The rejection-contract run resolved the DeepSeek rank0/r64 oracle from the profile and
matched it both before the fault and after scale-down. It also passed healthy-state
rejections, pause and scale-down status transitions, dead-rank routing rejection, owned
process cleanup and source-cleanliness gates.

All three successful runs exited zero with every structured assertion passing. A final
preflight found GPU `4,5,6,7` idle at 15 MiB and zero utilization.

## Applicability limits

- The default ten-token request path is registered. The optional
  `historical-count4` rejoin request still needs its own DeepSeek oracle before that
  diagnostic variant is selected.
- `fault-kill-pause-continuous-scale-down` cannot reach one survivor with only 64
  redundant experts. For a 64-logical-expert model, that topology requires at least
  192 redundant experts; use a separate profile and artifact root for that case.

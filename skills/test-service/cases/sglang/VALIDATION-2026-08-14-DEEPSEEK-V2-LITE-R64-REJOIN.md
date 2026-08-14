# DeepSeek-V2-Lite r64 rejoin oracle validation — 2026-08-14

## Evidence

- Independent source run: `issue42-clean-f42c9737-32c0160d99-gpu0123-r1`
- Source branch pair: `codex/clean/sglang-nohca-recovery` and
  `codex/clean/mooncake-nohca-recovery`
- Scenario: native no-FT static rank-3 kill, automatic 4-to-3 shrink, then rank-3
  rejoin
- Model: `/data1/models/DeepSeek-V2-Lite-Chat`
- Topology: TP=4, DP=4, EP=4 on GPU `0,1,2,3`
- Redundant experts: `64`
- Artifact:
  `work/sglang-clean-nohca-recovery-42-gpu0123/artifacts/issue42-clean-f42c9737-32c0160d99-gpu0123-r1/output/recovered-dp3.json`

The recovered rank-3 request returned HTTP 200 with ten output tokens:

`[185,185,16,11,207,17,11,207,18,11]`

The source contract classified this as `known_output_drift` and passed the
rejoin lifecycle. This sequence predates the FT acceptance run and is therefore
registered as an allowed known rank-3/r64 rejoin output. The canonical output
remains unchanged. No output first observed by the FT run may be added during
that run.

## Applicability

This allowance applies only to
`deepseek-v2-lite-chat-bf16-d4t4e4-count10-no-overlap-rank3-r64`. Survivor-rank
oracles and other models, ranks, redundancy counts, request shapes, or dispatch
configurations remain unchanged.

# Reject invalid fault-tolerance operations

Validate the `codex/dp-only-ft-squashed` or `worktree-dp-only-ft-revise` SGLang branch with
the kernel and Mooncake roots selected by the task profile. Use one bounded cold run for a
branch-usability round; use two independent cold runs for a stability campaign.

```powershell
python skills\test-service\scripts\run-case.py `
  --profile profiles\<profile>.local.env `
  --case sglang/fault-rejection-contracts `
  --name fault-rejection-contracts `
  --repeat 2
```

## Topology

- Model: `Qwen3-30B-A3B-FP8`
- Four profile-selected GPUs with TP=4, DP=4 and EP=4
- Fault-tolerance strategy: `pause`
- Mooncake TCP with CPU staging fallback
- Deterministic inference, overlap and CUDA graph disabled

## Ordered phases and barriers

1. Verify the selected kernel and Mooncake identities.
2. Reach `0=healthy,1=healthy,2=healthy,3=healthy` with four schedulers and complete an
   exact-token DP0 baseline.
3. Require retry and `scale_down([1])` to return HTTP 400 with `no_paused_rank`.
4. Prove both rejected operations leave all four ranks healthy.
5. Kill scheduler rank 1 and reach `0=paused,1=dead,2=paused,3=paused`.
6. Apply `scale_down([1])` with HTTP 200 and reach
   `0=healthy,1=dead,2=healthy,3=healthy`.
7. Require DP0 generation to return HTTP 200 with exact registered token IDs.
8. Require retry after the committed scale-down to return HTTP 400 with `no_paused_rank`
   and leave status unchanged.
9. Require explicit DP1 routing to return HTTP 400 and leave status unchanged.
10. Stop the owned process group and leave the source checkout clean.

The healthy-state rejections must complete before fault injection. The scale-down status is
a barrier before testing post-commit retry and dead-rank routing.

Every gate must append a structured assertion. Exit zero without assertions is not a pass.

## Required artifacts

Keep source/container/GPU provenance, imported package records, every request and response
JSON, status JSON after each rejection, server log, owned PGID, precision records,
`assertions.jsonl` and `result.json`.

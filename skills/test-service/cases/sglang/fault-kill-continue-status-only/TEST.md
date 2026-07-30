# Kill one scheduler and continue serving

Apply to SGLang branches `codex/dp-only-ft-squashed` and
`worktree-dp-only-ft-revise`. Run two bounded cold repetitions for stability campaigns; one
cold run is sufficient for a branch-usability validation round.

```powershell
python skills\test-service\scripts\run-case.py `
  --profile profiles\<profile>.local.env `
  --case sglang/fault-kill-continue-status-only `
  --name fault-kill-continue-status-only `
  --repeat 2 `
  --timeout 420
```

## Topology

- Model: `Qwen3-30B-A3B-FP8`
- TP=4, DP=4, EP=4 on the four profile-selected GPUs
- Mooncake TCP with CPU staging fallback
- Deterministic inference; overlap and CUDA graph disabled
- FT strategy: `continue`

## Ordered gates

1. Import the profile-selected kernel and Mooncake versions from their explicit roots.
2. Reach `0=healthy,1=healthy,2=healthy,3=healthy` with four schedulers.
3. Complete one ten-token baseline generation on each DP before fault injection, and require
   all four baselines to match.
4. Kill global scheduler rank 1.
5. Reach `0=healthy,1=dead,2=healthy,3=healthy` with exactly three schedulers.
6. Prove the continue path dispatched no pause command.
7. Converge to HTTP 400 for explicit routing to dead DP1 within 180 seconds.
8. Return HTTP 200 on DP0, DP2 and DP3, with each survivor matching its own pre-fault
   ten-token baseline.
9. Stop the owned service process group and leave the source checkout clean.

## Required artifacts

Keep container and source provenance, imported package records, requests and responses, FT
status JSON, server log, owned PGID, four baseline responses and precision JSON files, three
post-fault precision JSON files, assertions and result JSON.

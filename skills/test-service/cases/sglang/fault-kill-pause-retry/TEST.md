# Kill one scheduler, pause, and retry

Apply to SGLang branches `codex/dp-only-ft-squashed`, `worktree-dp-only-ft-revise`, and
the rebased `ft-2commits` validation branches. Run two bounded cold repetitions for stability campaigns; one
cold run is sufficient for a branch-usability validation round.

```powershell
python skills\test-service\scripts\run-case.py `
  --profile profiles\<profile>.local.env `
  --case sglang/fault-kill-pause-retry `
  --name fault-kill-pause-retry `
  --repeat 2 `
  --timeout 420
```

## Topology

- Model: compatible profile-selected MoE model
- TP=4, DP=4, EP=4 on the four profile-selected GPUs
- Mooncake TCP with CPU staging fallback
- Deterministic inference; overlap and CUDA graph disabled
- FT strategy: `pause`

## Ordered gates

1. Import the profile-selected kernel and Mooncake versions from their explicit roots.
2. Reach `0=healthy,1=healthy,2=healthy,3=healthy` with four schedulers.
3. Complete one ten-token baseline generation on each DP before fault injection.
4. Kill global scheduler rank 1.
5. Reach `0=paused,1=dead,2=paused,3=paused` with exactly three schedulers.
6. Reject generation while paused with HTTP 503.
7. Apply retry with HTTP 200.
8. Reach `0=healthy,1=dead,2=healthy,3=healthy` with three schedulers.
9. Converge to HTTP 400 for explicit routing to dead DP1 within 180 seconds.
10. Return HTTP 200 on DP0, DP2 and DP3, with each survivor output belonging to
    the registered known-sequence set for the selected model and topology.
11. Stop the owned service process group and leave the source checkout clean.

## Required artifacts

Keep container and source provenance, imported package records, all request/response JSON, FT
status JSON, server log, owned PGID, four baseline responses, three post-recovery
known-sequence JSON files, assertions and result JSON.

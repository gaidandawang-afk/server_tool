# Kill one scheduler and continue serving

Apply to SGLang branch `codex/dp-only-ft-squashed`. Run two bounded cold repetitions.

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
3. Kill global scheduler rank 1.
4. Reach `0=healthy,1=dead,2=healthy,3=healthy` with exactly three schedulers.
5. Prove the continue path dispatched no pause command.
6. Reject explicit routing to dead DP1 with HTTP 400.
7. Return HTTP 200 and exact ten-token registered output on DP0, DP2 and DP3.
8. Stop the owned service process group and leave the source checkout clean.

## Required artifacts

Keep container and source provenance, imported package records, requests and responses, FT
status JSON, server log, owned PGID, three precision JSON files, assertions and result JSON.

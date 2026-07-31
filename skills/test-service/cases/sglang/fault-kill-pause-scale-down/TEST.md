# Kill, pause, and logical scale-down

Validate the `codex/dp-only-ft-squashed` or `worktree-dp-only-ft-revise` SGLang branch with
the kernel and Mooncake roots selected by the task profile. Run cold twice for stability
campaigns; one cold run is sufficient for a branch-usability validation round.

```powershell
python skills\test-service\scripts\run-case.py `
  --profile profiles\<profile>.local.env `
  --case sglang/fault-kill-pause-scale-down `
  --name fault-kill-pause-scale-down `
  --repeat 2
```

## Topology

- Model: compatible profile-selected MoE model with registered per-rank precision oracles
- GPU: four profile-selected GPUs
- TP=4, DP=4, EP=4
- Mooncake TCP with CPU staging fallback
- HTTP port: `PORT_BASE`
- Deterministic inference, overlap and CUDA graph disabled

## Ordered gates

1. Import the exact selected `sglang-kernel` version from `SGLANG_KERNEL_ROOT`.
2. Start with `0=healthy,1=healthy,2=healthy,3=healthy` and four schedulers.
3. Complete one ten-token baseline generation on each DP before fault injection.
4. Kill global scheduler rank 1.
5. Reach `0=paused,1=dead,2=paused,3=paused` with three schedulers.
6. Reject generation while paused with HTTP 503.
7. Apply logical `scale_down` to rank 1 with HTTP 200.
8. Reach `0=healthy,1=dead,2=healthy,3=healthy` without killing another scheduler.
9. Reject explicit DP1 routing with HTTP 400.
10. Return HTTP 200 on DP0, DP2 and DP3; require each survivor to match both its own
    pre-fault baseline and its registered exact oracle.
11. Stop the owned server process group and leave the source checkout clean.

Every gate must append a structured assertion. Exit zero without assertions is not a pass.

## Required artifacts

- `container.env`, `provenance.env`, `invocation.json`
- actual Python package version and import path
- request and response JSON for every HTTP operation
- FT status JSON, server log, owned PGIDs
- four pre-fault baseline responses and both baseline-parity and oracle precision JSON
- `assertions.jsonl` and `result.json`

# Kill, self-pause, and whole-DP scale-down

Validate `codex/ft-vllm-api-refactor` with the kernel and Mooncake roots selected by the
task profile. Run cold twice for stability
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
- Mooncake TCP host transport with intra-node NVLink for GPU payloads
- HTTP port: `PORT_BASE`
- Deterministic inference, overlap and CUDA graph disabled

## Ordered gates

1. Import the exact selected `sglang-kernel` version from `SGLANG_KERNEL_ROOT`.
2. Start with `0=healthy,1=healthy,2=healthy,3=healthy` and four schedulers.
3. Complete one ten-token baseline generation on each DP before fault injection.
4. Kill global scheduler rank 1.
5. Reach `0=healthy,1=dead,2=healthy,3=healthy` with three schedulers. Because the kill is
   idle, no survivor forward exception occurred and the survivor states remain healthy.
6. Reject generation during the incident with HTTP 503 and prove no central pause command
   was dispatched.
7. Submit whole-DP `scale_down([1])`, require HTTP 202 with the matching request ID, then poll
   the full engine topology. Rank 1 was already externally killed, so its whole-DP block is
   already empty; require one survivor topology install and forced EPLB.
8. Remain `0=healthy,1=dead,2=healthy,3=healthy` with exactly three schedulers.
9. Reject explicit DP1 routing with HTTP 503 and the inactive-rank error.
10. Return HTTP 200 on DP0, DP2 and DP3; require each survivor output to belong
    to the registered known-sequence set for the selected model and topology.
11. Stop the owned server process group and leave the source checkout clean.

Every gate must append a structured assertion. Exit zero without assertions is not a pass.

## Required artifacts

- `container.env`, `provenance.env`, `invocation.json`
- actual Python package version and import path
- request and response JSON for every HTTP operation
- FT status JSON, admission response, control-barrier log evidence, server
  log, owned PGIDs
- four pre-fault baseline responses and per-survivor known-sequence result JSON
- `assertions.jsonl` and `result.json`

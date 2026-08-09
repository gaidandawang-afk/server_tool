# Whole-DP scale-down and complete node-group rejoin

Validate `codex/ft-self-pause-minimal` with the kernel and Mooncake roots selected by the
task profile. One bounded cold pass is sufficient for a branch-usability round; every new
source HEAD requires fresh validation.

```powershell
python skills\test-service\scripts\run-case.py `
  --profile profiles\<profile>.local.env `
  --case sglang/fault-kill-pause-scale-down-then-rejoin `
  --name fault-kill-pause-scale-down-then-rejoin
```

## Topology

- Four independent one-GPU SGLang node process groups, one DP block per node
- TP=4, DP=4, EP=4, NNODES=4 with API ports `PORT_BASE..PORT_BASE+3`
- Distributed initialization port `PORT_BASE+4`
- Pause strategy, static expert placement, deterministic inference
- Native `--elastic-ep-rejoin`; no DP-scoped respawn or joiner

The default uses the registered ten-token request. Diagnostic variants may select the
existing dispatch, deterministic, request-style, token-count, and random-seed profile inputs,
but each variant requires its own run name and artifact directory.

## Ordered phases and barriers

1. Verify provenance, start four healthy node process groups, and complete one baseline
   inference.
2. Kill and confirm exit of node 3's complete owned process group, trigger Mooncake failure
   detection, reach `0=unhealthy,1=unhealthy,2=unhealthy,3=dead` after the survivors
   self-pause, and prove admission returns HTTP 503.
3. Apply `scale_down([3])`, remain `0=healthy,1=healthy,2=healthy,3=dead`, keep exactly the
   three survivor groups, reject DP3 routing with HTTP 400, and generate correctly on DP0.
4. Only after the loss is committed by scale-down, start a complete NNODES=4 node-3 rejoin
   process group. Scheduler ProcessUp alone must leave DP3 `disabled` and unroutable, and a
   `recover([3])` sent at this point must be rejected with HTTP 400
   `recover_requires_recovered_ranks`.
5. Drive survivor forwards until Mooncake completes rank-3 recovery on every survivor, then
   execute one post-recovery forward.
6. Reach `0=healthy,1=healthy,2=healthy,3=disabled`; DP3 must still return HTTP 400. The
   completed native data-plane recovery, not a rank-state change, is the barrier that makes
   `recover([3])` admissible.
7. Only now apply `recover([3])`. Its HTTP 200 completion updates the expected mask and DPC
   route without a Scheduler command; then reach four `healthy` ranks.
8. Generate on DP3 and DP0, validate registered output, stop all four owned process groups,
   and leave the source checkout clean.

Recover is gated by native data-plane recovery, not by the rank state: once DP3 reports
`disabled` a recover request is rejected with `recover_requires_recovered_ranks` until the
native recovery completes; HTTP 200 is a completion response only after the route update.

## Required artifacts

Keep source/container/GPU provenance, effective case inputs, four initial node logs and the
node-3 rejoin log, all owned PGIDs, process-group kill evidence, every request/response/status
JSON, recovery-drive responses, recover barrier log evidence, precision JSON,
`assertions.jsonl`, and `result.json`.

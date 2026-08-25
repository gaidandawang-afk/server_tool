# Whole-DP scale-down and complete node-group rejoin

Applicable source branch: SGLang `codex/ft-vllm-api-refactor` at
clean local HEAD with the Mooncake branch and wheel selected by the profile.

Validate the Mooncake Elastic EP FT source branch, kernel and Mooncake roots selected by the
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
- Mooncake transport selected by `SGLANG_FT_MOONCAKE_TRANSPORT_MODE`; the
  `tcp-fallback` mode must log TCP-only startup and no intra-node NVLink transport
- Pause strategy, static expert placement, deterministic inference
- Native `--elastic-ep-rejoin`; no DP-scoped respawn or joiner

The default uses the registered ten-token request. Diagnostic variants may select the
existing dispatch, deterministic, request-style, token-count, and random-seed profile inputs,
but each variant requires its own run name and artifact directory.

## Ordered phases and barriers

1. Verify provenance, start four healthy node process groups, and complete one baseline
   inference.
2. Start a DP0 streaming request and prove it entered decode, then kill and confirm exit of
   node 3's complete owned process group. Reach `3=dead` with at least one survivor marked
   `unhealthy` after observing the failed in-flight collective, and prove admission returns
   HTTP 503. Survivors execute different collective phases, so the test does not require all
   three to report the same failure before scale-down.
3. Submit `scale_down([3])`, require HTTP 202 with the matching request ID, and poll until
   `0=healthy,1=healthy,2=healthy,3=dead`. Keep exactly the three survivor groups, require DP3
   routing to return HTTP 503 with an inactive-rank error, and generate correctly on DP0.
4. Only after the loss is committed by scale-down, start a complete NNODES=4 node-3 rejoin
   process group. Require its Scheduler process to exist while DP3 remains `dead` and
   unroutable, then wait for the joiner to log that it has entered process-group recovery
   after model initialization.
5. While DP3 is still `dead`, route exactly one survivor forward to DP0. Mooncake must
   complete rank-3 recovery on every survivor before the bounded observation deadline, then
   execute one post-recovery forward.
6. After native join lets the replacement Scheduler become ready and the DPC reports
   ProcessUp, the existing FT observation chain must automatically restore the expected mask
   and route. Reach four `healthy` ranks without calling `/fault_tolerance/apply`.
7. Generate on DP3 and DP0, validate registered output, stop all four owned process groups,
   and leave the source checkout clean.

Automatic route reopening is gated by both process readiness and native data-plane recovery.
The two signals may arrive in either order; until both have been observed, DP3 remains `dead`
and unroutable. There is no public `disabled` state and no explicit FT recover operation.

## Required artifacts

Keep source/container/GPU provenance, effective case inputs, four initial node logs with
mixed-transport assertions and the node-3 rejoin log with the process-group recovery entry
marker, all owned PGIDs, process-group kill evidence, every request/response/status JSON,
the single recovery-drive response, native recovery log evidence, precision JSON,
`assertions.jsonl`, and `result.json`.

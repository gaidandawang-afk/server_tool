# Fail-stop after an unattended exception pause

Validate `codex/ft-self-pause-minimal` with the kernel and Mooncake roots selected by the
task profile. Use one bounded cold run for a
branch-usability round; use two independent cold runs for a stability campaign.

```powershell
python skills\test-service\scripts\run-case.py `
  --profile profiles\<profile>.local.env `
  --case sglang/fault-exception-pause-retry-timeout `
  --name fault-exception-pause-retry-timeout `
  --repeat 2 `
  --timeout 600
```

## Topology

- Model: compatible profile-selected MoE model with a registered precision oracle
- Four profile-selected GPUs with TP=4, DP=4 and EP=4
- Fault-tolerance strategy: `pause`
- One task-local, one-shot recoverable ModelRunner forward exception on DP0
- Unattended-pause fail-stop timeout: 30 seconds
- Mooncake TCP with CPU staging fallback
- Deterministic inference, overlap and CUDA graph disabled

## Ordered phases and barriers

1. Verify the selected kernel and Mooncake identities.
2. Reach `0=healthy,1=healthy,2=healthy,3=healthy` with four schedulers and complete an
   exact-token DP0 baseline.
3. Arm and trigger the one-shot DP0 forward exception.
4. Require the affected request to return HTTP 503 and observe exactly one injection
   completion record.
5. Retain all four schedulers and reach
   `0=unhealthy,1=unhealthy,2=unhealthy,3=unhealthy`.
6. Require a second request to return HTTP 503, proving the admission gate remains closed.
7. Issue no retry, scale-down or recover command; prove all four schedulers remain alive
   before the configured timeout.
8. Require the scheduler log to show that the 30-second unattended-pause deadline expired.
9. Require the entire owned process group to exit within 120 seconds, including bounded crash
   diagnostics, and identify `Fault tolerance pause unattended` as the reason.
10. Leave the source checkout clean.

The all-unhealthy status and HTTP 503 are barriers before the intentional no-apply wait. A
scheduler crash before the configured pause timeout is a failure, as is a surviving owned
process after the bounded fail-stop and crash-diagnostic wait. The contract asserts the
Scheduler-owned deadline rather than a tokenizer-manager fallback timer.

Every gate must append a structured assertion. Exit zero without assertions is not a pass.

## Required artifacts

Keep source/container/GPU provenance, imported package records, baseline and trigger response
JSON, trigger and completion records, unhealthy status and admission JSON, server log, owned
PGID, precision record, `assertions.jsonl` and `result.json`.

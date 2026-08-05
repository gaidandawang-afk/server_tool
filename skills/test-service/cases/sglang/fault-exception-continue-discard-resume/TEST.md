# Recoverable exception with continue and discard

Validate `codex/ft-self-pause-whole-dp` with
the kernel and Mooncake roots selected by the task profile. Use one bounded cold run for a
branch-usability round; use two independent cold runs for a stability campaign.

```powershell
python skills\test-service\scripts\run-case.py `
  --profile profiles\<profile>.local.env `
  --case sglang/fault-exception-continue-discard-resume `
  --name fault-exception-continue-discard-resume `
  --repeat 2
```

## Topology

- Model: compatible profile-selected MoE model with a registered precision oracle
- Four profile-selected GPUs with TP=4, DP=4 and EP=4
- Fault-tolerance strategy: `continue`
- One task-local, one-shot recoverable ModelRunner forward exception on DP0
- Mooncake TCP with CPU staging fallback
- Deterministic inference, overlap and CUDA graph disabled

## Ordered phases and barriers

1. Verify the selected kernel and Mooncake identities.
2. Reach `0=healthy,1=healthy,2=healthy,3=healthy` with four schedulers.
3. Complete an exact-token DP0 baseline.
4. Arm and trigger the one-shot DP0 forward exception.
5. Require the affected request to return HTTP 503 and observe exactly one injection
   completion record.
6. Retain all four schedulers, reach
   `0=unhealthy,1=unhealthy,2=unhealthy,3=unhealthy`, and dispatch neither a central pause
   command nor retry reset.
7. Because continue does not close admission, generate again on DP0 with HTTP 200 and the
   exact registered token IDs. The successful native forward/report must then restore four
   healthy ranks.
8. Stop the owned process group and leave the source checkout clean.

The exception-completion record is a barrier: the transient unhealthy status must be observed
before the recovery forward. No retry operation is part of this continue contract.

Every gate must append a structured assertion. Exit zero without assertions is not a pass.

## Required artifacts

Keep source/container/GPU provenance, imported package records, baseline, discarded and
post-exception response JSON, trigger and completion records, status JSON, server log, owned
PGID, precision records, `assertions.jsonl` and `result.json`.

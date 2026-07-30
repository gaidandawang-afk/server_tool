# Fail-stop after an unattended exception pause

Validate the `codex/dp-only-ft-squashed` or `worktree-dp-only-ft-revise` SGLang branch with
the kernel and Mooncake roots selected by the task profile. Use one bounded cold run for a
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
   `0=paused,1=paused,2=paused,3=paused`.
6. Issue no retry, scale-down or recover command; prove all four schedulers remain alive
   before the configured timeout.
7. Require the log to show the 30-second unattended-pause fail-stop was armed.
8. Require the entire owned process group to exit within 60 seconds and the log to identify
   `Fault tolerance pause unattended` as the reason.
9. Leave the source checkout clean.

The all-paused state is a barrier before the intentional no-apply wait. A scheduler crash
before the configured pause timeout is a failure, as is a surviving owned process after the
bounded fail-stop wait.

Every gate must append a structured assertion. Exit zero without assertions is not a pass.

## Required artifacts

Keep source/container/GPU provenance, imported package records, baseline and trigger response
JSON, trigger and completion records, paused status JSON, server log, owned PGID, precision
record, `assertions.jsonl` and `result.json`.

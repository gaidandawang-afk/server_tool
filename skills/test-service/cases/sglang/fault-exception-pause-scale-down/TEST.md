# Recoverable exception, disable and recover

## Applicability

- Source branch: `codex/dp-only-ft-squashed`
- TP=4, DP=4, EP=4 on the four profile-selected GPUs
- Fault tolerance strategy: `pause`
- Repetition for this validation round: one cold run

## Ordered phases and barriers

1. Verify dependency identities and reach four healthy schedulers.
2. Generate one bounded baseline on each explicitly routed DP. These requests also warm
   every route before the fault.
3. Arm a task-local recoverable exception for DP2.
4. Require the triggering request to return HTTP 503 and observe the completion record.
5. Reach `0=paused,1=paused,2=paused,3=paused`.
6. Apply logical scale-down for DP2.
7. Reach `0=healthy,1=healthy,2=disabled,3=healthy` while retaining four schedulers.
8. Require DP2 routing to return HTTP 400.
9. Generate on DP0/1/3 and compare each output with that DP's own baseline.
10. Prove ordinary survivor forwards do not clear DP2's disabled state.
11. Explicitly recover DP2 and reach four healthy ranks without another scheduler resume.
12. Generate on DP2 and compare it with DP2's own baseline.
13. Stop the owned process group and leave source clean.

## Required artifacts

Keep provenance, package records, requests/responses, all state snapshots, injection records,
server log, resume-count assertion, precision records, owned PGID, assertions and result JSON.

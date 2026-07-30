# Recoverable exception, disable and recover

## Applicability

- Source branch: `codex/dp-only-ft-squashed`
- TP=4, DP=4, EP=4 on the four profile-selected GPUs
- Fault tolerance strategy: `pause`
- Repetition for this validation round: one cold run

## Ordered phases and barriers

1. Verify dependency identities and reach four healthy schedulers.
2. Arm a task-local recoverable exception for DP2.
3. Require the triggering request to return HTTP 503 and observe the completion record.
4. Reach `0=paused,1=paused,2=paused,3=paused`.
5. Apply logical scale-down for DP2.
6. Reach `0=healthy,1=healthy,2=disabled,3=healthy` while retaining four schedulers.
7. Require DP2 routing to return HTTP 400.
8. Generate on DP0/1/3; match DP0 to its oracle and DP1/3 to DP0.
9. Prove ordinary survivor forwards do not clear DP2's disabled state.
10. Explicitly recover DP2 and reach four healthy ranks without another scheduler resume.
11. Generate on DP2 and match the survivor output.
12. Stop the owned process group and leave source clean.

## Required artifacts

Keep provenance, package records, requests/responses, all state snapshots, injection records,
server log, resume-count assertion, precision records, owned PGID, assertions and result JSON.

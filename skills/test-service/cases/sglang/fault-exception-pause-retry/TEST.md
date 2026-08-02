# Recoverable exception, pause and retry

## Applicability

- Source branches: `codex/dp-only-ft-squashed`, `worktree-dp-only-ft-revise`, rebased `ft-2commits` validation branches
- TP=4, DP=4, EP=4 on the four profile-selected GPUs
- Fault tolerance strategy: `pause`
- Repetition: two independent cold runs

## Ordered phases and barriers

1. Verify the selected kernel and Mooncake identities.
2. Reach `0=healthy,1=healthy,2=healthy,3=healthy` with four schedulers.
3. Arm a task-local one-shot recoverable forward exception for DP0.
4. Trigger the exception and require the current request to return HTTP 503.
5. Observe one injection completion record and retain all four schedulers.
6. Reach `0=paused,1=paused,2=paused,3=paused`.
7. Require another request to return HTTP 503 while paused.
8. Apply retry with HTTP 200.
9. Reach `0=healthy,1=healthy,2=healthy,3=healthy` with four schedulers.
10. Generate on every DP, match DP0 to the registered ten-token oracle and require DP1/2/3
    to match DP0.
11. Stop the owned process group and leave the source checkout clean.

The exception-completion record is a barrier: no paused-state or retry assertion may run
until the injected forward has actually raised.

## Required artifacts

Keep source/container/GPU preflight provenance, imported package records, requests and
responses, status JSON, trigger and completion records, server log, owned PGID, four precision
records, assertions and result JSON.

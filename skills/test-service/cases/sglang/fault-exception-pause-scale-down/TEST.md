# Recoverable exception and whole-DP scale-down

## Applicability

- Source branch: `codex/ft-self-pause-minimal-simplify`; revalidate its exact selected HEAD
- TP=4, DP=4, EP=4 on the four profile-selected GPUs
- Fault tolerance strategy: `pause`
- Repetition for this validation round: one cold run

## Ordered phases and barriers

1. Verify dependency identities and reach four healthy schedulers.
2. Generate one baseline with a 90-second bound on each explicitly routed DP. These
   requests also warm every route before the fault.
3. Arm a task-local recoverable exception for DP2.
4. Require the triggering request to return HTTP 503 and observe the completion record.
5. Reach `0=unhealthy,1=unhealthy,2=unhealthy,3=unhealthy` and prove admission remains
   closed with HTTP 503.
6. Apply `scale_down([2])`. The operation must prepare the survivor topology and actively
   shut down DP2's complete Scheduler block.
7. Reach `0=healthy,1=healthy,2=dead,3=healthy` with exactly three schedulers and no
   remaining global rank 2 process.
8. Require DP2 routing to return HTTP 400.
9. Generate on DP0/1/3 and compare each output with that DP's own baseline.
10. Stop the owned process group and leave source clean. This contract does not call recover;
    recovery requires a complete owner-node process-group rejoin first.

## Required artifacts

Keep provenance, package records, requests/responses, all state snapshots, injection records,
server log, process-level shutdown evidence, precision records, owned PGID, assertions and
result JSON.

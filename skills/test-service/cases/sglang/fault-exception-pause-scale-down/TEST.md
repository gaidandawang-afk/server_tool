# Recoverable exception and whole-DP scale-down

## Applicability

- Source branch: `codex/ft-vllm-api-refactor`; revalidate its exact selected HEAD
- TP=4, DP=4, EP=4 on the four profile-selected GPUs
- Fault tolerance strategy: `pause`
- Schedule variant: set `SGLANG_FT_OVERLAP_SCHEDULE=0` for non-overlap or `1`
  for overlap. Each validation campaign must run both variants under distinct
  task profiles and artifact directories.
- Repetition for this validation round: one cold run

## Ordered phases and barriers

1. Verify dependency identities and reach four healthy schedulers.
2. Generate one baseline with a 90-second bound on each explicitly routed DP. Then
   launch eight requests concurrently, two per DP, prove at least two client processes
   are simultaneously in flight, and require every response to finish with HTTP 200 and
   exactly 64 output tokens. This is the explicit overlap-schedule workload gate.
3. Arm a task-local recoverable exception for DP2.
4. Require the triggering request to return HTTP 503 and observe the completion record.
5. Reach `0=unhealthy,1=unhealthy,2=unhealthy,3=unhealthy` and prove admission remains
   closed with HTTP 503.
6. Submit `scale_down([2])`, require HTTP 202 with the matching request ID, then poll the
   full engine topology. The operation must prepare the survivors and actively shut down
   DP2's complete Scheduler block.
7. Reach `0=healthy,1=healthy,2=dead,3=healthy` with exactly three schedulers and no
   remaining global rank 2 process.
8. Require DP2 routing to return HTTP 503 with the inactive-rank error.
9. Generate on DP0/1/3 and compare each output with that DP's own baseline. Then launch
   six concurrent requests, two per surviving DP, again prove simultaneous in-flight
   clients and require complete HTTP 200 responses with exactly 64 output tokens.
10. Stop the owned process group and leave source clean. This contract does not call recover;
    recovery requires a complete owner-node process-group rejoin first.

## Required artifacts

Keep provenance, selected overlap mode, package records, every concurrent request/response/error/
status/contract independently, all state snapshots, injection records, server log,
process-level shutdown evidence, precision records, owned PGID, assertions and result JSON.

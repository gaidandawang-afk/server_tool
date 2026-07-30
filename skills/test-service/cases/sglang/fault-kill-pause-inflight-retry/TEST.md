# Kill an in-flight DP1 stream, pause, then retry

## Applicability

- Source branch: `codex/dp-only-ft-squashed`
- TP=4, DP=4, EP=4 on the four profile-selected GPUs
- Fault tolerance strategy: `pause`
- Repetition for this validation round: one cold run

## Ordered phases and barriers

1. Verify dependencies, four healthy schedulers and bounded DP0/DP1 baselines.
2. Start a 64-token streaming request explicitly routed to DP1.
3. Observe at least one DP1 completion token before killing scheduler rank1.
4. Reach `0=paused,1=dead,2=paused,3=paused` with three schedulers.
5. Require the original stream to have HTTP 200 but no normal or complete final response.
6. Require a DP0 request to return HTTP 503 while paused.
7. Apply retry and reach `0=healthy,1=dead,2=healthy,3=healthy`.
8. Generate through DP0 and compare ten tokens with its pre-fault baseline.
9. Stop only the owned process group and leave source clean.

## Required artifacts

Keep provenance, package records, requests and baselines, all state snapshots, stream stdout,
stderr and contract JSON, blocked response, retry request/response, post-retry response and
precision record, server log, owned PGID, assertions and result JSON.

# Kill an in-flight DP1 stream with continue strategy

## Applicability

- Source branches: `codex/dp-only-ft-squashed`, `worktree-dp-only-ft-revise`, rebased `ft-2commits` validation branches
- TP=4, DP=4, EP=4 on the four profile-selected GPUs
- Fault tolerance strategy: `continue`
- Repetition for this validation round: one cold run

## Ordered phases and barriers

1. Verify dependencies, four healthy schedulers and bounded DP0/DP1 baselines.
2. Start a 64-token streaming request explicitly routed to DP1.
3. Observe at least one DP1 completion token before killing scheduler rank1.
4. Reach `0=healthy,1=dead,2=healthy,3=healthy` with three schedulers.
5. Require the original stream to have HTTP 200 but no normal or complete final response.
6. Generate through DP0 and compare ten tokens with its pre-fault baseline.
7. Stop only the owned process group and leave source clean.

## Required artifacts

Keep provenance, package records, requests and baselines, state snapshots, stream stdout,
stderr and contract JSON, post-fault response and precision record, server log, owned PGID,
assertions and result JSON.

# A*C>1 whole-DP shutdown

## Applicability

- Source branch: `codex/ft-self-pause-minimal`; revalidate its exact selected HEAD
- TP=4, DP=2, EP=4 on the four profile-selected GPUs
- Attention TP=2, so each routed DP owns two global Scheduler siblings
- Fault tolerance strategy: `pause`
- Repetition: one bounded cold run for branch usability

## Ordered phases and barriers

1. Verify dependency identities and reach `0=healthy,1=healthy` with four schedulers.
2. Generate bounded baselines successfully on DP0 and DP1. Their sampled token sequences are
   not required to match because the two routed DP groups have distinct deterministic RNG streams.
3. Record global rank 3, then externally kill global rank 2 in the same DP1 block.
4. Reach `0=healthy,1=dead`, retain rank 3 only as a pre-apply sibling, and prove admission
   is closed with HTTP 503.
5. Apply `scale_down([1])` with HTTP 200.
6. Require the whole-DP shutdown barrier to remove both global ranks 2 and 3, leaving exactly
   two DP0 schedulers. Rank 3 must not be retained.
7. Remain `0=healthy,1=dead`, reject DP1 routing with HTTP 400, and generate successfully on
   DP0 with output equal to its pre-fault baseline.
8. Stop only the owned process group and leave the selected source checkout clean.

The pre-apply rank-3 PID proves the case actually exercised a partially alive A*C block. The
post-apply global-rank and process-count assertions are the whole-DP completion barrier.

## Required artifacts

Keep provenance, package records, routed requests and baselines, incident and final status,
blocked/dead-route responses, post-fault precision, server log, owned PGID, process-level
shutdown assertions, `assertions.jsonl`, and `result.json`.

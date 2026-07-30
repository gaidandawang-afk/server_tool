# TP sibling EP retention after one scheduler exits

## Applicability

- Source branch: `codex/dp-only-ft-squashed`
- TP=4, DP=2, EP=4 on the four profile-selected GPUs
- Attention TP=2 gives each routed DP two physical scheduler siblings
- Fault tolerance strategy: `pause`
- Repetition for this validation round: one cold run

## Ordered phases and barriers

1. Verify dependency identities and reach `0=healthy,1=healthy` with four schedulers.
2. Generate bounded baselines on DP0 and DP1 and require equal ten-token output.
3. Record global rank3's PID, then kill global rank2 in the same DP1 sibling group.
4. Reach `0=paused,1=dead`, retain exactly three schedulers, and prove rank3 kept its PID.
5. Apply retry and reach `0=healthy,1=dead`.
6. Require explicit routing to DP1 to return HTTP 400.
7. Generate through DP0 and compare ten tokens with its pre-fault baseline.
8. Prove rank3 still lives and logged preservation of expert weights and physical EP layout.
9. Stop only the owned process group and leave source clean.

## Required artifacts

Keep provenance, package records, both routed requests and baselines, state snapshots, retry
request/response, dead-route response, post-fault response and precision records, server log,
owned PGID, assertions and result JSON.

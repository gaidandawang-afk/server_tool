# Consecutive scheduler kills with one multi-rank scale-down

Validate that pause-mode FT can accumulate two scheduler deaths and commit both dead ranks
with one `scale_down([1,2])` operation.

## Ordered gates

1. Start TP=4, DP=4, EP=4 with four healthy schedulers.
2. Kill DP1, then reach `healthy/paused, dead, paused, paused`.
3. While the survivors remain paused, kill DP2.
4. Reach `paused,dead,dead,paused` with two schedulers.
5. Apply one multi-rank scale-down for DP1 and DP2 with HTTP 200.
6. Reach `healthy,dead,dead,healthy` without another scheduler exit.
7. Reject explicit routing to both dead DPs with HTTP 400.
8. Generate on DP0 and DP3 and match their registered ten-token oracles.
9. Clean the owned process group and source worktree.

One bounded cold PASS is sufficient for the current case-usability round.

## Required artifacts

Preserve all status snapshots, apply request/response, routed generation responses, precision
results, scheduler-count assertions, server log, provenance and cleanup evidence.

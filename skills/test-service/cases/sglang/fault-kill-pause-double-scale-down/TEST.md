# Consecutive scheduler kills with one multi-rank scale-down

Validate that pause-mode FT can accumulate two scheduler deaths and commit both dead ranks
with one `scale_down([1,2])` operation.

## Applicability

- Source branch: `codex/ft-vllm-api-refactor`; revalidate its exact selected HEAD
- TP=4, DP=4, EP=4 on four profile-selected GPUs
- Repetition for branch-usability validation: one cold run

## Ordered gates

1. Start TP=4, DP=4, EP=4 with four healthy schedulers and complete one baseline inference.
2. Kill idle DP1, then reach `healthy,dead,healthy,healthy`; admission is closed without a
   survivor forward exception.
3. While the incident remains active, kill DP2.
4. Reach `healthy,dead,dead,healthy` with two schedulers and prove admission returns HTTP 503.
5. Submit one multi-rank scale-down for DP1 and DP2, require HTTP 202 with the matching
   request ID, then poll the full engine topology.
6. Remain `healthy,dead,dead,healthy` after survivor prepare/route/resume completion.
7. Reject explicit routing to both dead DPs with HTTP 400.
8. Generate on DP0 and DP3 and match their registered ten-token oracles.
9. Clean the owned process group and source worktree.

One bounded cold PASS is sufficient for the current case-usability round.

## Required artifacts

Preserve all status snapshots, apply request/response, routed generation responses, precision
results, scheduler-count assertions, server log, provenance and cleanup evidence.

# Continuous scale-down to one surviving DP

Validate three bounded kill/pause/scale-down rounds in one service lifetime. DP1, DP2 and DP3
are removed sequentially; DP0 must resume and retain deterministic output after every round.
This single-DP endpoint uses 384 redundant experts and `mem_fraction_static=0.45`, matching
the historical condition that retains the complete expert set on the final survivor.

## Applicability

- Source branches: `codex/dp-only-ft-squashed`, `worktree-dp-only-ft-revise`
- TP=4, DP=4, EP=4 on four profile-selected GPUs
- Repetition for branch-usability validation: one cold run

## Ordered gates

1. Start TP=4, DP=4, EP=4 with all ranks healthy, then complete a deterministic DP0
   baseline before injecting the first fault.
2. For each target rank 1, 2 and 3:
   - kill only that owned scheduler;
   - reach the cumulative dead set with every survivor paused;
   - apply scale-down only for the newly dead rank;
   - reach the cumulative dead set with every survivor healthy;
   - confirm the scheduler count decreased by exactly one;
   - route a request to DP0 and match its registered ten-token oracle.
3. Finish at `0=healthy,1=dead,2=dead,3=dead` with one scheduler.
4. Clean the owned process group and source worktree.

Every phase is causally ordered and independently bounded. One cold PASS is sufficient for
the current case-usability round.

## Required artifacts

Preserve per-round status, apply request/response, DP0 generation and precision files, process
counts, server log, provenance, assertions, result and cleanup evidence.

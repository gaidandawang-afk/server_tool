# Native Mooncake in-flight isolation without FT

Validate `codex/dp-only-ft-squashed` or `worktree-dp-only-ft-revise` with fault tolerance
disabled. One stream runs on DP0 while DP1 is killed. Mooncake must isolate the dead peer
without an FT apply operation, and the already-running DP0 stream must return a complete HTTP
200 response.

## Topology

- Model: `Qwen3-30B-A3B-FP8`
- Four profile-selected GPUs; TP=4, DP=4, EP=4
- Mooncake TCP with CPU staging fallback
- Fault tolerance disabled
- Stream routed to DP0; scheduler DP1 is the fault target

## Ordered gates

1. Import the profile-selected kernel and Mooncake builds.
2. Start four schedulers and confirm the FT status API returns HTTP 503.
3. Start a 64-token stream on DP0 and observe positive DP0 decode progress.
4. Kill scheduler DP1 and retain exactly three schedulers.
5. Observe native Mooncake broken-peer detection for rank 1.
6. Require the original DP0 stream to finish with curl rc 0, HTTP 200, a final
   `finish_reason`, 64 completion tokens and 64 output IDs.
7. Generate ten deterministic tokens on DP0 and match the registered oracle.
8. Clean the owned process group and leave the source worktree clean.

One bounded cold PASS is sufficient for the current case-usability round.

## Required artifacts

- provenance, container identity, package imports and invocation
- FT-disabled response, stream request/output/error/final response/contract
- post-fault request, response and precision result
- server log, assertions, result and owned process evidence

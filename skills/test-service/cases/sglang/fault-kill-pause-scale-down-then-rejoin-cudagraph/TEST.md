# Decode-only CUDA Graph in-flight kill, scale-down, and rejoin

Applicable source branch: SGLang `codex/ft-vllm-api-refactor` at clean
local HEAD with the Mooncake branch and wheel selected by the profile. The
Mooncake source must include the deferred-recovery CUDA Graph compatibility
changes under validation.

Run one bounded cold pass for each new source HEAD:

```powershell
python skills\test-service\scripts\run-case.py `
  --profile profiles\<profile>.local.env `
  --case sglang/fault-kill-pause-scale-down-then-rejoin-cudagraph `
  --name fault-kill-pause-scale-down-then-rejoin-cudagraph
```

## Goal and topology

Launch four independent DP/TP/EP ranks with Mooncake mixed NVLink/TCP transport,
static expert dispatch, full decode CUDA Graph, prefill CUDA Graph disabled, and
decode capture batch sizes 1, 2, 4, and 8. Start a DP0 stream, prove decode has
begun, kill the complete rank-3 process group, explicitly apply
`scale_down([3])`, and start a replacement rank 3 with native rejoin.

## Ordered phases and barriers

1. Verify provenance, launch four ranks, require health, and complete baseline
   inference before fault injection.
2. Start the DP0 stream and observe a decode token before killing only the owned
   rank-3 process group. Require DP3 to become dead (survivors may remain healthy)
   and HTTP 503 admission closure.
3. Submit `scale_down([3])`, require HTTP 202 with the matching request ID, poll until
   three survivors are healthy and DP3 is dead, then wait for route closure through an HTTP 503
   inactive-rank error and a correct
   post-shrink DP0 generation.
4. Start replacement rank 3. Require its deferred local native fast path and its
   one decode graph capture to finish before process-group recovery join begins.
5. Drive survivor recovery, require all four routes healthy, and validate DP3 and
   DP0 generation against pre-registered precision oracles.
6. Require each survivor to retain exactly its one startup decode capture, the
   replacement to capture exactly once, and graph replay to occur without illegal
   address or Python fallback-dispatch errors.
7. Stop only owned process groups, leave the source clean, and preserve all
   structured assertions.

## Pass/fail gates and artifacts

The run must pass every HTTP, status, process-count, precision, native recovery,
capture-count, capture-before-join, replay, forbidden-error, cleanup, and source
cleanliness assertion. Preserve provenance, inputs and hashes, request/response
JSON, stream files, all initial and rejoin node logs, `assertions.jsonl`, and
`result.json`. Repetition mode is cold; each repetition uses a distinct run name
and artifact directory.

# Recoverable exception, pause and retry

## Applicability

- Source branch: `codex/ft-vllm-api-refactor`; revalidate its exact selected HEAD
- TP=4, DP=4, EP=4 on the four profile-selected GPUs
- Fault tolerance strategy: `pause`
- Repetition: one bounded cold run for branch usability

## Ordered phases and barriers

1. Verify the selected kernel and Mooncake identities.
2. Reach `0=healthy,1=healthy,2=healthy,3=healthy` with four schedulers and complete one
   baseline inference.
3. Arm a task-local one-shot recoverable forward exception for DP0.
4. Trigger the exception and require the current request to return HTTP 503.
5. Observe one injection completion record and retain all four schedulers.
6. Reach `0=unhealthy,1=unhealthy,2=unhealthy,3=unhealthy`; this reflects the
   coordinated exception, not the Scheduler-local paused bit.
7. Require another request to return HTTP 503, proving admission remains closed.
8. Submit maskless retry, require HTTP 202 with the matching request ID, then poll the full
   engine topology until healthy. Completion covers the expected Scheduler command responses
   and DPC route update. Require no EPLB.
9. Reach `0=healthy,1=healthy,2=healthy,3=healthy` with four schedulers.
10. Generate on every DP and match each response to that DP's registered ten-token oracle;
    different routed DP groups are not required to share a token sequence.
11. Stop the owned process group and leave the source checkout clean.

The exception-completion record is a barrier: no unhealthy-state or retry assertion may run
until the injected forward has actually raised.

## Required artifacts

Keep source/container/GPU preflight provenance, imported package records, requests and
responses, status JSON, trigger and completion records, server log, owned PGID, four precision
records, assertions and result JSON.

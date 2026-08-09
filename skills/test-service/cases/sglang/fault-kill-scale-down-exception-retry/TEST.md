# Retry on the committed 4-to-3 topology

## Applicability

- Source branch: `codex/ft-self-pause-minimal`; revalidate its exact selected HEAD
- TP=4, DP=4, EP=4 on the four profile-selected GPUs
- Fault tolerance strategy: `pause`
- Repetition: one bounded cold run for branch usability

## Test-only injection mode

After DP1 exits, the original injector cannot all-reduce on the launch-time CPU process group:
that group still contains the dead rank. This case opts into
`SGLANG_TEST_FT_RECOVERABLE_FAULT_LOCAL_ONLY=1` and injects only survivor DP0. The default
coordinated injector remains unchanged for the four-rank exception cases. This is a test
mechanism boundary, not a product recovery mechanism. In local-only mode, DP0 first completes
the same model/EP forward as the other survivors and raises only after that forward returns;
the injector must not strand DP2/3 inside a collective.

## Ordered phases and barriers

1. Verify provenance, reach four healthy schedulers, and complete a registered DP0 baseline.
2. Kill DP1, reach `healthy,dead,healthy,healthy`, prove admission returns HTTP 503, then
   commit `scale_down([1])`.
3. Remain `healthy,dead,healthy,healthy` with exactly three schedulers; require DP1 HTTP 400
   and DP0 HTTP 200 before arming the next fault.
4. Inject one local recoverable exception on survivor DP0. Require the triggering request to
   return HTTP 503, observe one completion record, and reach
   `unhealthy,dead,healthy,healthy` while the scheduler count remains three.
5. Apply maskless retry. Require no EPLB during retry and final
   `healthy,dead,healthy,healthy` status.
6. Prove the route did not expand: DP1 remains HTTP 400, DP0/2/3 return HTTP 200 with
   registered outputs, and the scheduler count remains three.
7. Stop the owned process group and leave the source checkout clean.

The completed scale-down status and DP1 route closure are barriers before exception injection.
The retry response is not complete until the expected survivors respond and the three-rank
route is installed; no runtime-reported mask may re-enable DP1.

## Required artifacts

Keep source/container/GPU provenance, baseline and all request/response JSON, scale-down and
retry payloads/responses, injection trigger/completion files, every status snapshot,
no-EPLB evidence, process counts, per-survivor precision JSON, server log, owned PGID,
`assertions.jsonl`, and `result.json`.

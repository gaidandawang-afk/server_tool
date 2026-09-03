# Reject invalid fault-tolerance operations

Validate `codex/ft-vllm-api-refactor` with one bounded cold run for branch usability.
Every selected source HEAD requires fresh validation.

## Topology

- Four profile-selected GPUs with TP=4, DP=4, EP=4
- Fault-tolerance strategy `pause`, EPLB enabled, Mooncake elastic EP
- One task-local coordinated recoverable exception injection on DP1; no fault is injected on DP0

## Ordered phases and barriers

1. Verify dependency identities, reach four healthy schedulers, and complete a registered DP0
   baseline.
2. While healthy, submit `scale_down([1])`. Require HTTP 202 acceptance followed by the
   aggregate status error `scale_down_requires_incident`, correlated by request ID on all
   engines. Require the removed `recover` instruction to return synchronous HTTP 400 with the
   standard SGLang error envelope and a Pydantic message containing `Input tag 'recover'`. Status must remain four
   healthy engines. The contract does not submit a rank-0 fault or scale-down operation.
3. Trigger the coordinated exception on DP1, observe its completion record, reach four `unhealthy`
   ranks, and prove admission returns HTTP 503.
4. During that incident, submit `scale_down([])`, require HTTP 202, then poll the matching
   aggregate `scale_down_requires_ranks` error while the unhealthy topology stays unchanged.
5. Submit valid `scale_down([1])` and require HTTP 202. Before it completes, submit retry and
   require synchronous HTTP 409 with the nested `ft_operation_in_progress` error envelope.
   Poll the first request to `healthy,dead,healthy,healthy`, and require whole-DP1 shutdown to
   leave three schedulers.
6. Before any node-group rejoin, require the removed legacy `recover([1])` instruction to
   remain rejected with HTTP 400 and a message containing `Input tag 'recover'`; status must remain
   unchanged, and DP1 routing must return HTTP 503 with an inactive-rank error. Recovery
   is automatic only after complete process and
   native data-plane readiness are observed.
7. Generate correctly on DP0, stop the owned process group, and leave source clean.

This contract deliberately contains no kill-to-retry assertion. Retry success is covered only
by `fault-exception-pause-retry`; behavior after a real process loss is outside retry's
supported contract.

## Required artifacts

Keep source/container/GPU provenance, imported package records, every request and response,
status after each rejection, request IDs, accepted/error envelopes, injection trigger/completion
records, whole-DP process evidence, server log, owned PGID, precision JSON, `assertions.jsonl`,
and `result.json`.

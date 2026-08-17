# Reject invalid fault-tolerance operations

Validate `codex/ft-self-pause-minimal-simplify` with one bounded cold run for branch usability.
Every selected source HEAD requires fresh validation.

## Topology

- Four profile-selected GPUs with TP=4, DP=4, EP=4
- Fault-tolerance strategy `pause`, EPLB enabled, Mooncake elastic EP
- One task-local coordinated recoverable exception injection

## Ordered phases and barriers

1. Verify dependency identities, reach four healthy schedulers, and complete a registered DP0
   baseline.
2. Without an incident, require `scale_down([1])` to return HTTP 400 with
   `scale_down_requires_incident`; require the removed legacy `recover([1])` instruction to
   return HTTP 400 with `unsupported instruction: recover`. Status must remain four healthy
   ranks.
3. Trigger the coordinated exception, observe its completion record, reach four `unhealthy`
   ranks, and prove admission returns HTTP 503.
4. During that incident, require `scale_down([])` to return HTTP 400 with
   `scale_down_requires_ranks` and leave the unhealthy status unchanged.
5. Apply valid `scale_down([1])`, reach `healthy,dead,healthy,healthy`, and require whole-DP1
   shutdown to leave three schedulers.
6. Before any node-group rejoin, require the removed legacy `recover([1])` instruction to
   remain rejected with HTTP 400 and `unsupported instruction: recover`; status and the DP1
   HTTP 400 route must remain unchanged. Recovery is automatic only after complete process
   and native data-plane readiness are observed.
7. Generate correctly on DP0, stop the owned process group, and leave source clean.

This contract deliberately contains no kill-to-retry assertion. Retry success is covered only
by `fault-exception-pause-retry`; behavior after a real process loss is outside retry's
supported contract.

## Required artifacts

Keep source/container/GPU provenance, imported package records, every request and response,
status after each rejection, injection trigger/completion records, whole-DP process evidence,
server log, owned PGID, precision JSON, `assertions.jsonl`, and `result.json`.

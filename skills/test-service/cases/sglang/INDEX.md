# SGLang self-pause and whole-DP FT case index

This is the server_tool-owned index for the four-GPU DP-only FT regression set. The active
contracts target `codex/ft-self-pause-minimal` and the architecture defined by
`SELF_PAUSE_WHOLE_DP_FT.md`. They must be validated against the exact selected source HEAD.

**Validation state:** source `764933930`, case contracts `3b3b572`. Five of fifteen active
contracts meet the current pre-fault inference contract. Two earlier scenario passes need
revalidation under that new gate, two are environment-blocked, and six remain unverified on
the exact HEAD. No unresolved FT correctness failure has been observed. The PASS results retained in
[the 2026-08-02 record](VALIDATION-2026-08-02-FT-2COMMITS.md) apply only to the old
`4c8b11fa4` semantics and are not carried forward.

## Architecture contract

- `pause` is a Scheduler-local event-loop state. The control plane closes admission but does
  not publish a `PAUSED` rank state or dispatch a central pause command.
- Public rank states are only `healthy`, `unhealthy`, `dead`, and `disabled`.
- A recoverable exception is the only supported retry trigger. Process or node loss must
  converge through `scale_down`; kill-based retry is not an executable contract.
- `scale_down` kills every Scheduler member of each target DP, waits for the retained watchdog
  process facts, then installs the explicit survivor topology, forces EPLB and updates DPC route.
- Rejoin is always a complete native `nnodes` process-group lifecycle. ProcessUp alone remains
  `dead`; a successful native recovery forward/EPLB becomes `disabled`; explicit recover only
  commits the expected mask and DPC route, changing the cohort to `healthy`.
- The retained continue cases preserve native Mooncake membership, second-forward, and route
  behavior. The no-FT case remains a native baseline.
- Every active contract must complete a real `/generate` request after startup and before any
  fault injection or FT operation. Failure at this gate is an environment or baseline-runtime
  blocker, not evidence about the scenario's FT operation.

## Precision classification

Control-flow success and precision success are separate results. A case that reaches the
expected FT state but lacks an equivalent precision comparison is `CONTROL PASS,
PRECISION UNDETERMINED`, not a precision pass.

Scenario contracts use registered known-sequence sets. A response passes only when its full
token sequence is already registered for the selected model, topology, and redundant-expert
count. A run must never register its own output as passing. Strict token equality remains
reserved for matched precision-attribution runs with identical request history and runtime
configuration.

## Active contracts

| Scenario | Suite identifier | server_tool contract | New-architecture evidence | Status |
| --- | --- | --- | --- | --- |
| Native Mooncake isolates a killed idle DP while an unaffected stream completes | `fault_kill_noft_status_apply_generate.sh` | `fault-kill-noft-native-inflight` | Native isolation and EPLB completed; the stream kept progressing but did not finish under shared GPU load | ENVIRONMENT BLOCKED |
| Kill one scheduler and continue on survivors | `fault_kill_continue_status_only.sh` | `fault-kill-continue-status-only` | native EPLB/second forward, DEAD route closure | VALIDATED ONCE |
| Kill one scheduler and commit whole-DP scale-down | `fault_kill_pause_scale_down.sh` | `fault-kill-pause-scale-down` | Three runs stopped at the pre-fault inference gate; kill and scale-down were not executed | ENVIRONMENT BLOCKED |
| Recoverable exception and retry | `fault_exception_pause_retry.sh` | `fault-exception-pause-retry` | exact-HEAD run still required | NOT RUN |
| Retry after a committed 4-to-3 scale-down | `fault_kill_scale_down_exception_retry.sh` | `fault-kill-scale-down-exception-retry` | local survivor exception, mask reset, no EPLB or re-expansion | VALIDATED ONCE |
| Recoverable exception and whole-DP scale-down | `fault_exception_pause_scale_down.sh` | `fault-exception-pause-scale-down` | exact-HEAD run still required | NOT RUN |
| Kill one member when A*C>1 and shut down its complete DP | `fault_tpgt1_whole_dp_shutdown.sh` | `fault-tpgt1-whole-dp-shutdown` | older-HEAD pass exists; exact-HEAD run still required | REVALIDATE |
| Kill an in-flight stream with continue | `fault_kill_continue_inflight.sh` | `fault-kill-continue-inflight` | exact-HEAD run still required | NOT RUN |
| Kill two schedulers and scale down both | `fault_kill_pause_double_scale_down.sh` | `fault-kill-pause-double-scale-down` | Earlier functional pass lacked the new direct pre-fault `/generate` gate | REVALIDATE |
| Scale down three schedulers sequentially | `fault_kill_pause_continuous_scale_down.sh` | `fault-kill-pause-continuous-scale-down` | repeated explicit commits, final single survivor | VALIDATED ONCE |
| Reject invalid FT API operations | `fault_rejection_contracts.sh` | `fault-rejection-contracts` | incident/empty-target/recover-before-DISABLED errors | VALIDATED ONCE |
| Lose and rejoin a logical node with continue | `fault_kill_continue_whole_node_rejoin.sh` | `fault-kill-continue-whole-node-rejoin` | exact-HEAD run still required | NOT RUN |
| Scale down and rejoin a logical node with pause | `fault_kill_pause_scale_down_then_rejoin.sh` | `fault-kill-pause-scale-down-then-rejoin` | Earlier functional pass used health checks but lacked the new direct pre-fault `/generate` gate | REVALIDATE |
| Recoverable exception with continue/discard | `fault_exception_continue_discard_resume.sh` | `fault-exception-continue-discard-resume` | request discard, healthy status, no pause or retry | VALIDATED ONCE |
| Leave a self-paused exception unattended | `fault_exception_pause_retry_timeout.sh` | `fault-exception-pause-retry-timeout` | exact-HEAD run still required | NOT RUN |

The legacy kill-to-retry executable contracts are intentionally removed. Killing a process is
outside retry's supported preconditions, so those scenarios must not be run as substitutes
for exception-injection retry. Their historical results remain available only in the
immutable `VALIDATION-*` records.

For a branch-usability round, one bounded cold PASS on the selected source commit is enough to
mark a case `Validated once`. Stability campaigns use independent names and artifact
directories for every cold repetition.

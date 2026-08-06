# SGLang self-pause and whole-DP FT case index

This is the server_tool-owned index for the four-GPU DP-only FT regression set. The active
contracts target `codex/ft-self-pause-minimal` and the architecture defined by
`SELF_PAUSE_WHOLE_DP_FT.md`. They must be validated against the exact selected source HEAD.

**Validation state:** pending on `codex/ft-self-pause-minimal`. No active contract in this
index has yet passed on the new architecture. The PASS results retained in
[the 2026-08-02 record](VALIDATION-2026-08-02-FT-2COMMITS.md) apply only to the old
`4c8b11fa4` semantics and must not be carried forward.

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
| Native Mooncake isolates a killed idle DP while an unaffected stream completes | `fault_kill_noft_status_apply_generate.sh` | `fault-kill-noft-native-inflight` | FT disabled, native isolation, complete DP0 stream | PENDING |
| Kill one scheduler and continue on survivors | `fault_kill_continue_status_only.sh` | `fault-kill-continue-status-only` | native EPLB/second forward, DEAD route closure | PENDING |
| Kill one scheduler and commit whole-DP scale-down | `fault_kill_pause_scale_down.sh` | `fault-kill-pause-scale-down` | admission closure, explicit topology, DEAD target | PENDING |
| Recoverable exception and retry | `fault_exception_pause_retry.sh` | `fault-exception-pause-retry` | UNHEALTHY, maskless retry reset, no EPLB | PENDING |
| Retry after a committed 4-to-3 scale-down | `fault_kill_scale_down_exception_retry.sh` | `fault-kill-scale-down-exception-retry` | local survivor exception, no EPLB or re-expansion | PENDING |
| Recoverable exception and whole-DP scale-down | `fault_exception_pause_scale_down.sh` | `fault-exception-pause-scale-down` | exception admission barrier, target shutdown, no direct recover | PENDING |
| Kill one member when A*C>1 and shut down its complete DP | `fault_tpgt1_whole_dp_shutdown.sh` | `fault-tpgt1-whole-dp-shutdown` | both target siblings exit; no sibling retention | PENDING |
| Kill an in-flight stream with continue | `fault_kill_continue_inflight.sh` | `fault-kill-continue-inflight` | interrupted target stream, native survivor service | PENDING |
| Kill two schedulers and scale down both | `fault_kill_pause_double_scale_down.sh` | `fault-kill-pause-double-scale-down` | one multi-target explicit commit, both targets DEAD | PENDING |
| Scale down three schedulers sequentially | `fault_kill_pause_continuous_scale_down.sh` | `fault-kill-pause-continuous-scale-down` | repeated explicit commits, final single survivor | PENDING |
| Reject invalid FT API operations | `fault_rejection_contracts.sh` | `fault-rejection-contracts` | incident/empty-target/recover-before-DISABLED errors | PENDING |
| Lose and rejoin a logical node with continue | `fault_kill_continue_whole_node_rejoin.sh` | `fault-kill-continue-whole-node-rejoin` | complete node-group restart and native automatic recovery | PENDING |
| Scale down and rejoin a logical node with pause | `fault_kill_pause_scale_down_then_rejoin.sh` | `fault-kill-pause-scale-down-then-rejoin` | DEAD -> DISABLED -> explicit recover -> HEALTHY | PENDING |
| Recoverable exception with continue/discard | `fault_exception_continue_discard_resume.sh` | `fault-exception-continue-discard-resume` | request discard, healthy status, no pause or retry | PENDING |
| Leave a self-paused exception unattended | `fault_exception_pause_retry_timeout.sh` | `fault-exception-pause-retry-timeout` | UNHEALTHY admission barrier and Scheduler-local fail-stop | PENDING |

The legacy kill-to-retry executable contracts are intentionally removed. Killing a process is
outside retry's supported preconditions, so those scenarios must not be run as substitutes
for exception-injection retry. Their historical results remain available only in the
immutable `VALIDATION-*` records.

For a branch-usability round, one bounded cold PASS on the selected source commit is enough to
mark a case `Validated once`. Stability campaigns use independent names and artifact
directories for every cold repetition.

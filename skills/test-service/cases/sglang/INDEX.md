# SGLang self-pause and whole-DP FT case index

This is the server_tool-owned index for the four-GPU DP-only FT regression set. The active
contracts target `codex/ft-self-pause-minimal` and the architecture defined by
`SELF_PAUSE_WHOLE_DP_FT.md`. They must be validated against the exact selected source HEAD.

**Validation state:** exact source `b7c6f9229`, 2026-08-10. Fourteen of fifteen active contracts
passed one bounded cold run on GPU 4,5,6,7, totaling 428/428 passing structured assertions in
their successful runs. The only unresolved failure is
`fault-kill-pause-continuous-scale-down`: both `-r1` (initially shared GPUs) and `-r2` (all four
GPUs idle at 15 MiB, 0%) completed the first two sequential scale-downs, then timed out after
180 seconds on the third `scale_down([3])`. DP0 logged EPLB `rebalance start` without
`rebalance end`; Mooncake also reported a leaked BatchID. Both failed runs cleaned the owned
process group and left the source clean. This repeat excludes shared-GPU pressure as the primary
cause and is an unresolved FT correctness failure. Historical PASS results retained in
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
- Rejoin is always a complete native `nnodes` process-group lifecycle. The replacement
  Scheduler waits in native join before it becomes ready, so survivor recovery-drive precedes
  ProcessUp. ProcessUp then reports the derived rank state from the expected mask: a DP scaled
  out of the expected mask becomes `disabled`; a DP still in the expected mask becomes
  `healthy`. A successful native recovery forward/EPLB clears the pending-recovery gate and
  makes `recover` admissible
  without changing the reported rank state; explicit recover only commits the expected mask and
  DPC route, changing the cohort to `healthy`.
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
| Native Mooncake isolates a killed idle DP while an unaffected stream completes | `fault_kill_noft_status_apply_generate.sh` | `fault-kill-noft-native-inflight` | exact `b7c6f9229`: killed DP1, DP0 64-token stream completed, native isolation and post-fault precision passed, 18/18 (`20260810-r1`) | VALIDATED ONCE |
| Kill one scheduler and continue on survivors | `fault_kill_continue_status_only.sh` | `fault-kill-continue-status-only` | exact `b7c6f9229`: DP1 dead/400, no pause, three survivor generations and precision passed, 28/28 (`20260810-r1`) | VALIDATED ONCE |
| Kill one scheduler and commit whole-DP scale-down | `fault_kill_pause_scale_down.sh` | `fault-kill-pause-scale-down` | exact `b7c6f9229`: 503, no central pause, forced EPLB, dead target and three survivor precisions passed, 30/30 (`20260810-r1`) | VALIDATED ONCE |
| Recoverable exception and retry | `fault_exception_pause_retry.sh` | `fault-exception-pause-retry` | exact `b7c6f9229`: exception → four unhealthy → maskless retry → four healthy, scheduler count retained, no EPLB, four DP precisions passed, 30/30 (`20260810-r1`) | VALIDATED ONCE |
| Retry after a committed 4-to-3 scale-down | `fault_kill_scale_down_exception_retry.sh` | `fault-kill-scale-down-exception-retry` | exact `b7c6f9229`: 4→3 then survivor exception/retry retained the sparse topology and three precisions, 40/40 (`20260810-r1`) | VALIDATED ONCE |
| Recoverable exception and whole-DP scale-down | `fault_exception_pause_scale_down.sh` | `fault-exception-pause-scale-down` | exact `b7c6f9229`: four unhealthy → scale_down DP2, forced EPLB and three survivor precisions passed, 33/33 (`20260810-r1`) | VALIDATED ONCE |
| Kill one member when A*C>1 and shut down its complete DP | `fault_tpgt1_whole_dp_shutdown.sh` | `fault-tpgt1-whole-dp-shutdown` | exact `b7c6f9229`: rank2 killed with sibling rank3 alive; scale-down removed both and retained DP0 precision, 27/27 (`20260810-r1`) | VALIDATED ONCE |
| Kill an in-flight stream with continue | `fault_kill_continue_inflight.sh` | `fault-kill-continue-inflight` | exact `b7c6f9229`: rank1 stream interrupted, DP1 dead, DP0 continued with matching precision, 19/19 (`20260810-r1`) | VALIDATED ONCE |
| Kill two schedulers and scale down both | `fault_kill_pause_double_scale_down.sh` | `fault-kill-pause-double-scale-down` | exact `b7c6f9229`: DP1/DP2 dead, one multi-rank scale-down, DP0/DP3 precision passed, 26/26 (`20260810-r1`) | VALIDATED ONCE |
| Scale down three schedulers sequentially | `fault_kill_pause_continuous_scale_down.sh` | `fault-kill-pause-continuous-scale-down` | exact `b7c6f9229`: first two rounds pass; third `scale_down([3])` hangs after DP0 EPLB rebalance start and times out at 180s in both shared-GPU `r1` and idle-GPU `r2`; cleanup/source-clean pass | FAILED TWICE; INVESTIGATION REQUIRED |
| Reject invalid FT API operations | `fault_rejection_contracts.sh` | `fault-rejection-contracts` | exact `b7c6f9229`: all status/error-message invariants and post-scale-down precision passed, 35/35 (`20260810-r1`) | VALIDATED ONCE |
| Lose and rejoin a logical node with continue | `fault_kill_continue_whole_node_rejoin.sh` | `fault-kill-continue-whole-node-rejoin` | exact `b7c6f9229`: replacement `dead` while native join waits; survivor recovery-drive → ready/ProcessUp → automatic healthy route; four-rank precision and cleanup passed, 47/47 assertions (`native-first-20260810-r1`) | VALIDATED ONCE |
| Scale down and rejoin a logical node with pause | `fault_kill_pause_scale_down_then_rejoin.sh` | `fault-kill-pause-scale-down-then-rejoin` | exact `b7c6f9229`: replacement `dead` while native join waits; survivor recovery-drive → `disabled` → explicit recover → healthy; precision and cleanup passed, 52/52 assertions (`native-first-20260810-r1`) | VALIDATED ONCE |
| Recoverable exception with continue/discard | `fault_exception_continue_discard_resume.sh` | `fault-exception-continue-discard-resume` | exact `b7c6f9229`: current request discarded, healthy/no-pause state retained, next forward and precision passed, 22/22 (`20260810-r1`) | VALIDATED ONCE |
| Leave a self-paused exception unattended | `fault_exception_pause_retry_timeout.sh` | `fault-exception-pause-retry-timeout` | exact `b7c6f9229`: exception → all unhealthy, schedulers initially retained, unattended local deadline exited the owned group, 21/21 (`20260810-r1`) | VALIDATED ONCE |

The legacy kill-to-retry executable contracts are intentionally removed. Killing a process is
outside retry's supported preconditions, so those scenarios must not be run as substitutes
for exception-injection retry. Their historical results remain available only in the
immutable `VALIDATION-*` records.

For a branch-usability round, one bounded cold PASS on the selected source commit is enough to
mark a case `Validated once`. Stability campaigns use independent names and artifact
directories for every cold repetition.

# SGLang self-pause and whole-DP FT case index

This is the server_tool-owned index for the four-GPU DP-only FT regression set. The active
contracts target `codex/ft-self-pause-minimal` and the architecture defined by
`SELF_PAUSE_WHOLE_DP_FT.md`. They must be validated against the exact selected source HEAD.

**Validation state:** source `b7c6f9229`, case contracts revised 2026-08-09. Thirteen of the
fifteen active contracts meet the current pre-fault inference contract, validated on 2026-08-06
at source `764933930` (case contracts `3b3b572`) in a clean GPU 3,4,6,7 window, and are
functionally unaffected by the rejoin-state revision. The two rejoin contracts
(`fault-kill-pause-scale-down-then-rejoin`, `fault-kill-continue-whole-node-rejoin`) were
revised on 2026-08-09 for the derived-rank-state semantics of `b7c6f9229` and are pending
revalidation on the exact new HEAD. Two bounded cold attempts of the pause rejoin contract on
2026-08-09 (`pause-rejoin-b7c6f9229-20260809-r2` and `-r3`) were baseline-runtime blocked on
shared GPU 0,1,2,3: all ranks reached `healthy`, but `/health` remained HTTP 503 for the full
600-second startup gate while the GPUs were near 100% utilization. Neither attempt reached the
pre-fault `/generate`, so they are not FT correctness failures. The continue rejoin contract was
not run in that blocked window. No unresolved FT correctness failure has been observed. The PASS
results retained in
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
- Rejoin is always a complete native `nnodes` process-group lifecycle. ProcessUp alone reports
  the derived rank state from the expected mask: a DP scaled out of the expected mask becomes
  `disabled`; a DP still in the expected mask becomes `healthy` but unroutable. A successful
  native recovery forward/EPLB clears the pending-recovery gate and makes `recover` admissible
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
| Native Mooncake isolates a killed idle DP while an unaffected stream completes | `fault_kill_noft_status_apply_generate.sh` | `fault-kill-noft-native-inflight` | FT API 503; native isolation and EPLB completed; the unaffected DP0 stream ran to completion in a clean window (`gpu3467-r3`) | VALIDATED ONCE |
| Kill one scheduler and continue on survivors | `fault_kill_continue_status_only.sh` | `fault-kill-continue-status-only` | native EPLB/second forward, DEAD route closure | VALIDATED ONCE |
| Kill one scheduler and commit whole-DP scale-down | `fault_kill_pause_scale_down.sh` | `fault-kill-pause-scale-down` | All four baselines, explicit topology, forced EPLB, DEAD target and survivor precision passed in a clean execution window | VALIDATED ONCE |
| Recoverable exception and retry | `fault_exception_pause_retry.sh` | `fault-exception-pause-retry` | baseline gate passed; exception → 503 → all unhealthy → maskless retry → all healthy, 4 schedulers kept, no EPLB, per-DP precision matched (`gpu3467-r1`) | VALIDATED ONCE |
| Retry after a committed 4-to-3 scale-down | `fault_kill_scale_down_exception_retry.sh` | `fault-kill-scale-down-exception-retry` | local survivor exception, mask reset, no EPLB or re-expansion | VALIDATED ONCE |
| Recoverable exception and whole-DP scale-down | `fault_exception_pause_scale_down.sh` | `fault-exception-pause-scale-down` | four baselines; exception → all unhealthy → scale_down 4-to-3, whole-DP2 kill + forced EPLB, dead route 400, survivor precision matched (`gpu3467-r1`) | VALIDATED ONCE |
| Kill one member when A*C>1 and shut down its complete DP | `fault_tpgt1_whole_dp_shutdown.sh` | `fault-tpgt1-whole-dp-shutdown` | exact-HEAD run in clean window; kill rank2 with rank3 sibling alive, whole-DP1 shutdown + forced EPLB, both ranks gone, survivor precision matched (`gpu3467-r1`) | VALIDATED ONCE |
| Kill an in-flight stream with continue | `fault_kill_continue_inflight.sh` | `fault-kill-continue-inflight` | baseline + rank1 stream observed; kill rank1 → stream interrupted, survivors continue, DP0 precision matched (`gpu3467-r1`) | VALIDATED ONCE |
| Kill two schedulers and scale down both | `fault_kill_pause_double_scale_down.sh` | `fault-kill-pause-double-scale-down` | pre-fault baseline gate passed; two kills accumulated dead ranks, one multi-rank scale_down, both dead routes 400, two survivors precision matched (`gpu3467-r4`) | VALIDATED ONCE |
| Scale down three schedulers sequentially | `fault_kill_pause_continuous_scale_down.sh` | `fault-kill-pause-continuous-scale-down` | repeated explicit commits, final single survivor | VALIDATED ONCE |
| Reject invalid FT API operations | `fault_rejection_contracts.sh` | `fault-rejection-contracts` | incident/empty-target/recover-before-DISABLED errors | VALIDATED ONCE |
| Lose and rejoin a logical node with continue | `fault_kill_continue_whole_node_rejoin.sh` | `fault-kill-continue-whole-node-rejoin` | contract revised 2026-08-09: ProcessUp reports `healthy` with the route closed (HTTP 400) until native recovery; prior `gpu3467-r1` evidence ran the pre-revision dead-state contract | REVALIDATION PENDING |
| Scale down and rejoin a logical node with pause | `fault_kill_pause_scale_down_then_rejoin.sh` | `fault-kill-pause-scale-down-then-rejoin` | contract revised 2026-08-09: ProcessUp → `disabled` with recover rejected (`recover_requires_recovered_ranks`) until native recovery; two exact-HEAD shared-GPU attempts timed out at the pre-fault HTTP 200 startup gate, before scenario execution | BASELINE BLOCKED; REVALIDATION PENDING |
| Recoverable exception with continue/discard | `fault_exception_continue_discard_resume.sh` | `fault-exception-continue-discard-resume` | request discard, healthy status, no pause or retry | VALIDATED ONCE |
| Leave a self-paused exception unattended | `fault_exception_pause_retry_timeout.sh` | `fault-exception-pause-retry-timeout` | exact-HEAD run; exception → all unhealthy, schedulers stay alive, unattended self-pause converges to process-group exit with recorded reason (`gpu3467-r1`) | VALIDATED ONCE |

The legacy kill-to-retry executable contracts are intentionally removed. Killing a process is
outside retry's supported preconditions, so those scenarios must not be run as substitutes
for exception-injection retry. Their historical results remain available only in the
immutable `VALIDATION-*` records.

For a branch-usability round, one bounded cold PASS on the selected source commit is enough to
mark a case `Validated once`. Stability campaigns use independent names and artifact
directories for every cold repetition.

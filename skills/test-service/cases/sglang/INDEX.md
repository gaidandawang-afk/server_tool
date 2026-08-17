# SGLang self-pause and whole-DP FT case index

This is the server_tool-owned index for the four-GPU DP-only FT regression set. The active
contracts target `codex/ft-self-pause-minimal-simplify` and the architecture defined by
`SELF_PAUSE_WHOLE_DP_FT.md`. They must be validated against the exact selected source HEAD.

**Validation state:** historical exact source `b7c6f9229`, 2026-08-10. All fifteen active contracts
have at least one bounded cold PASS on GPU 4,5,6,7. The corrected
`fault-kill-pause-continuous-scale-down` contract passed 38/38 structured assertions in
`continuous-unhealthy-barrier-b7c6f9229-gpu4567-20260810-r2`; together with the other fourteen
contracts, the latest successful runs total 466/466 passing assertions. These results are
historical evidence for the predecessor branch, not validation of the current target branch.

**Historical new-HEAD delta validation:** exact source `27743e8f2`, 2026-08-10. The updated pause rejoin
contract passed 49/49 assertions in
`auto-rejoin-no-recover-27743e8f2-gpu4567-20260810-r4`: DP3 remained `dead` and HTTP 400 while
its replacement process waited for native backend readiness, then automatically became
`healthy` and returned HTTP 200 after process-active, native-active and pending-recovery facts
converged. No FT recover API was called. This is targeted delta evidence; the other fourteen
rows retain their exact `b7c6f9229` evidence until separately revalidated on the new HEAD.

**Current target validation:** on 2026-08-14,
`fault-kill-pause-scale-down-then-rejoin` passed 58/58 assertions in
`formal-ft-rejoin-r1` with SGLang `codex/ft-self-pause-minimal-simplify`, Mooncake
`codex/mooncake-nohca-ft`, DeepSeek-V2-Lite, r64 and GPU 0,1,2,3. Every other row below
retains only its explicitly named historical evidence until revalidated on this target.

The continuous case has two mandatory preconditions. First, shrinking Qwen's 128 logical
experts at EP4 to one survivor requires at least `128 * (4 - 1) = 384` redundant experts.
Second, after every kill, **all candidate survivors must have reached Scheduler self-pause and
report `unhealthy` before `scale_down` is submitted**. A process-DOWN observation or central
HTTP 503 only proves admission is closed; it does not prove every survivor has returned from
the preceding Mooncake operation.

Earlier r384 runs allowed either `healthy` or `unhealthy` survivors and could therefore submit
`scale_down` too early. Delivery debug `9f9a8254d` captured that invalid ordering during 3->2:
DPC sent to both DP0 and DP3, DP0 consumed the command and entered forced EPLB, while DP3 was
still draining Mooncake `op 5` and had not self-paused. Under the corrected ordering, each round
used an in-flight DP0 stream to expose the membership fault, then observed respectively
`0/2/3=unhealthy`, `0/3=unhealthy`, and `0=unhealthy` before apply. All survivor EPLB begin/end
pairs completed, all three scale-down calls returned HTTP 200, and every post-round DP0
precision check matched. Two further independent cold runs,
`continuous-unhealthy-barrier-b7c6f9229-gpu4567-20260810-acceptance-01` and `-02`, each passed
the same 38/38 assertions. The corrected contract therefore satisfies its three-cold-run
branch-usability acceptance gate.

## Architecture contract

- `pause` is a Scheduler-local event-loop state. The control plane closes admission but does
  not publish a `PAUSED` rank state or dispatch a central pause command.
- Public rank states are only `healthy`, `unhealthy`, and `dead`.
- A recoverable exception is the only supported retry trigger. Process or node loss must
  converge through `scale_down`; kill-based retry is not an executable contract.
- `scale_down` kills every Scheduler member of each target DP, waits for the retained watchdog
  process facts, then installs the explicit survivor topology, forces EPLB and updates DPC route.
- Rejoin is always a complete native `nnodes` process-group lifecycle. The replacement
  Scheduler waits in native join before it becomes ready, so survivor recovery-drive precedes
  ProcessUp. Process readiness and native data-plane readiness may be observed in either order;
  a scaled-out DP remains `dead` until both are ready, then FT automatically restores its
  expected membership and DPC route without an explicit recover API.
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
| Scale down three schedulers sequentially | `fault_kill_pause_continuous_scale_down.sh` | `fault-kill-pause-continuous-scale-down` | exact `b7c6f9229`, r384: corrected contract starts an in-flight stream and requires every candidate survivor `unhealthy` before each apply; 4->3->2->1, three forced EPLB rounds, post-round generations and precision passed 38/38 in each of `continuous-unhealthy-barrier-...-r2`, `...-acceptance-01`, and `...-acceptance-02`. Earlier early-apply hangs are retained as negative ordering evidence | VALIDATED THREE COLD RUNS |
| Reject invalid FT API operations | `fault_rejection_contracts.sh` | `fault-rejection-contracts` | historical `b7c6f9229`: status/error-message invariants and post-scale-down precision passed, 35/35 (`20260810-r1`); current contract treats legacy `recover` as an unsupported instruction because rejoin recovery is automatic | HISTORICAL PASS; CURRENT PENDING |
| Lose and rejoin a logical node with continue | `fault_kill_continue_whole_node_rejoin.sh` | `fault-kill-continue-whole-node-rejoin` | exact `b7c6f9229`: replacement `dead` while native join waits; survivor recovery-drive → ready/ProcessUp → automatic healthy route; four-rank precision and cleanup passed, 47/47 assertions (`native-first-20260810-r1`) | VALIDATED ONCE |
| Scale down and rejoin a logical node with pause | `fault_kill_pause_scale_down_then_rejoin.sh` | `fault-kill-pause-scale-down-then-rejoin` | current target: kill and scale-down retained DP3 `dead`; replacement remained unroutable until native recovery; process/native/pending facts converged automatically to four-DP `healthy`; DP3 matched the independently registered #42 rejoin sequence; cleanup and source-clean gates passed, 58/58 (`formal-ft-rejoin-r1`) | VALIDATED ON CURRENT TARGET |
| Recoverable exception with continue/discard | `fault_exception_continue_discard_resume.sh` | `fault-exception-continue-discard-resume` | exact `b7c6f9229`: current request discarded, healthy/no-pause state retained, next forward and precision passed, 22/22 (`20260810-r1`) | VALIDATED ONCE |
| Leave a self-paused exception unattended | `fault_exception_pause_retry_timeout.sh` | `fault-exception-pause-retry-timeout` | exact `b7c6f9229`: exception → all unhealthy, schedulers initially retained, unattended local deadline exited the owned group, 21/21 (`20260810-r1`) | VALIDATED ONCE |

The legacy kill-to-retry executable contracts are intentionally removed. Killing a process is
outside retry's supported preconditions, so those scenarios must not be run as substitutes
for exception-injection retry. Their historical results remain available only in the
immutable `VALIDATION-*` records.

For a branch-usability round, one bounded cold PASS on the selected source commit is enough to
mark a case `Validated once`. Stability campaigns use independent names and artifact
directories for every cold repetition.

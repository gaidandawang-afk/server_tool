# SGLang self-pause and whole-DP FT case index

This is the server_tool-owned index for the four-GPU DP-only FT regression set. The active
contracts target `codex/ft-vllm-api-refactor` and the architecture defined by
`SELF_PAUSE_WHOLE_DP_FT.md`. They must be validated against the exact selected source HEAD.

**Exact target validation:** SGLang `7375c482ba`, 2026-08-25, GPU 4,5,6,7. Fifteen of the
sixteen active contracts passed their latest bounded cold run, totaling 517/517 passing
assertions. Inactive explicit routes now close at admission with HTTP 503 and exact error
`routed_dp_rank=N is not active`; the error envelope may expose that text as either `message`
or `detail`. A killed rank may be `dead` while every survivor remains `healthy`, so pause/rejoin
contracts do not require an unrelated survivor to transiently report `unhealthy`.

**CUDA Graph and status delta validation:** exact SGLang `8a8860da82` with Mooncake `d727290c`,
2026-08-26, GPU 4,5,6,7. `status-requestid-cudagraph-d727-r1` passed 78/78. The scale-down status
reported the accepted request ID on every engine; replacement DP3 prepared its local fast path,
completed decode graph capture before native join, recovered four healthy routes, matched DP3
and DP0 precision, replayed the graph, and cleaned every owned process. The prior
`7375c482ba + 1569df4` failure was an invalid dependency pairing: Mooncake `1569df4` predates
`1ca33d50` (prepare the replacement local fast path before deferred connect) and `d727290c`
(skip inactive peers during graph capture), causing the missing fast-path marker followed by
`cudaErrorStreamCaptureUnjoined`. Historical `f15b89fe4c + d727290c` had already passed the
same in-flight full-graph flow three times at 83/83.

The asynchronous apply API previously had an observability ambiguity:
the accepted response tells clients to poll `/fault_tolerance/status`, but a pre-existing
`healthy,healthy,healthy,dead` state can satisfy that poll before the new scale-down request has
actually completed, and source `7375c482ba` does not expose the accepted request ID on success.
Target commit `8a8860da82` retains successful request IDs in status with four product-code line
changes; server_tool commit `d8ac716` requires the matching ID before accepting a status poll.
The 78/78 delta run above validated the matching request ID end to end.

**Historical new API validation state:** partial validation on exact source `41f28a8031`, 2026-08-25, using
GPU 4,5,6,7. Retry passed 32/32, single scale-down passed 32/32, double scale-down passed
29/29, A*C>1 whole-DP shutdown passed 29/29, and Qwen r384 continuous 4->3->2->1 scale-down
passed 43/43. After excluding rank 0 from fault injection and scale-down targets, the rejection
contract passed 40/40 in
`ft-vllm-rejection-no-rank0-41f28a8031-gpu4567-20260825-r2`; its injected exception and valid
scale-down both targeted DP1, while DP0 remained the surviving precision path.

The originally handed-off source `3126477656` passed the rejection contract 43/43 before the
SGLang branch was amended to `41f28a8031`. That run is retained as historical evidence only and
does not validate the current source HEAD. Historical results below predate both asynchronous
API commits and likewise do not validate the current request/status contract.

**Rejoin delta validation:** exact source `8283227d51`, 2026-08-25, using GPU 4,5,6,7.
`fault-kill-pause-scale-down-then-rejoin` passed 62/62 in
`ft-vllm-rejoin-8283227d51-gpu4567-20260825-r2`: dead DP3 routing returned the expected HTTP
200 inactive-rank abort before and during native recovery, all survivors completed rank-3
recovery, the topology automatically returned to four healthy engines, and recovered DP3/DP0
precision plus owned-process cleanup passed. This behavior is historical: source `7375c482ba`
now rejects inactive routes at admission with HTTP 503; its replacement validation is recorded
above. The remaining historical text is retained only as predecessor evidence.

**Validation state:** historical exact source `b7c6f9229`, 2026-08-10. All fifteen then-active contracts
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

**Current target validation:** on 2026-08-17, fourteen of the fifteen then-active contracts passed a
bounded cold run with SGLang `codex/ft-self-pause-minimal-simplify`, Mooncake
`codex/mooncake-nohca-ft`, DeepSeek-V2-Lite, r64 and GPU 0,1,2,3. The fourteen runs total
435/435 passing assertions. A separate DeepSeek r192 profile and independently attributed
rank-0 precision oracle were then established for the continuous 4-to-1 contract. Its first
cold acceptance run passed 38/38, but the second failed 26/28 after the second scale-down:
the legacy synchronous apply completed and status reported DP0/DP3 healthy, then the immediate DP0 generation
returned HTTP 503 with `Elastic EP membership loss detected before EPLB`. The continuous
contract is therefore not stable on the current target and has not met its three-cold-run gate.

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
pairs completed, all three legacy scale-down calls completed, and every post-round DP0
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

## Timeout contract

The active contracts use the following current FT timeout model. Fixed runtime values are
observed rather than overridden; configurable product deadlines are shortened explicitly for
test runs, with a longer test-side observation window so the harness cannot time out before
the product reports success or its own timeout error.

| Timeout | Product value | Test contract |
| --- | ---: | --- |
| DPC heartbeat interval | 3 s, fixed | No direct wait; contributes to failure observation latency. |
| Manager lease sweep interval | 1 s, fixed | No direct wait. |
| Manager lease timeout | 60 s, fixed | Kill scenarios allow 120 s for `dead`/incident status, covering the worst-case approximately 60–61 s detection plus scheduling margin. |
| Process-exit send timeout | 60 s, fixed; normal heartbeat is nonblocking | The same 120 s incident window accepts either prompt process-exit delivery or lease-expiry fallback. |
| FT control phase timeout | 60 s target default, configurable | Launchers set 60 s explicitly so validation is stable across the default-value rollout. Apply completion waits 90 s and correlates the accepted request ID. Shutdown, command ACK and route ACK remain independently timed phases. |
| Unattended pause timeout | 300 s default, configurable | Ordinary cases keep 300 s. `fault-exception-pause-retry-timeout` sets 30 s and allows 120 s for fail-stop cleanup. |
| Elastic EP scale timeout | 600 s default, configurable | Launchers set 150 s for validation; rejoin recovery waits 180 s. This is independent of the FT API transaction. |
| DPC worker-port exchange | 600 s, fixed | Used only by multi-node startup readiness; it is not accepted as a runtime FT completion signal. |

Every run preserves the effective values in `ft-timeouts.env`. Profiles may override the
configurable test values with `SGLANG_FT_CONTROL_PHASE_TIMEOUT_SEC`,
`SGLANG_FT_CONTROL_WAIT_TIMEOUT_SEC`, `SGLANG_FT_PAUSE_TIMEOUT_SEC`,
`SGLANG_FT_ELASTIC_EP_SCALE_TIMEOUT_SEC` and
`SGLANG_FT_ELASTIC_EP_WAIT_TIMEOUT_SEC`. Each observation timeout must be greater than its
corresponding product timeout.

Scenario audit:

- Exception `continue` cases do not wait for a lease or a control transaction; their bounded
  fault-trigger and status waits are independent of the 60-second node-loss lease.
- Exception `pause` retry/scale-down cases use the 90-second correlated control-completion
  window. The unattended-pause case alone validates expiry with the 30-second override.
- All FT process/node kill cases use a 120-second incident window before applying a command;
  the no-FT native baseline has no Manager lease/status contract.
- Scale-down and retry completion use the correlated 90-second window, including each round
  of continuous scale-down and the valid operation inside the rejection contract.
- Whole-node rejoin cases keep startup/model-readiness bounds separate, then use the
  150-second Elastic EP product timeout and 180-second recovery observation window.

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
| Native Mooncake isolates a killed idle DP while an unaffected stream completes | `fault_kill_noft_status_apply_generate.sh` | `fault-kill-noft-native-inflight` | 19/19 (`suite-7375c482ba-fault-kill-noft-native-inflight-r1`) | PASS ON `7375c482ba` |
| Kill one scheduler and continue on survivors | `fault_kill_continue_status_only.sh` | `fault-kill-continue-status-only` | 30/30 (`suite-7375c482ba-fault-kill-continue-status-only-r2`) | PASS ON `7375c482ba` |
| Kill one idle scheduler and commit whole-DP scale-down | `fault_kill_pause_scale_down.sh` | `fault-kill-pause-scale-down` | 33/33 (`suite-7375c482ba-fault-kill-pause-scale-down-r2`) | PASS ON `7375c482ba` |
| Recoverable exception and retry | `fault_exception_pause_retry.sh` | `fault-exception-pause-retry` | 32/32 (`suite-7375c482ba-fault-exception-pause-retry-r1`) | PASS ON `7375c482ba` |
| Retry after a committed 4-to-3 scale-down | `fault_kill_scale_down_exception_retry.sh` | `fault-kill-scale-down-exception-retry` | 45/45 (`suite-7375c482ba-fault-kill-scale-down-exception-retry-r2`) | PASS ON `7375c482ba` |
| Recoverable exception and whole-DP scale-down | `fault_exception_pause_scale_down.sh` | `fault-exception-pause-scale-down` | 36/36 (`suite-7375c482ba-fault-exception-pause-scale-down-r1`) | PASS ON `7375c482ba` |
| Kill one member when A*C>1 and shut down its complete DP | `fault_tpgt1_whole_dp_shutdown.sh` | `fault-tpgt1-whole-dp-shutdown` | 30/30 (`suite-7375c482ba-fault-tpgt1-whole-dp-shutdown-r2`) | PASS ON `7375c482ba` |
| Kill an in-flight stream with continue | `fault_kill_continue_inflight.sh` | `fault-kill-continue-inflight` | 20/20 (`suite-7375c482ba-fault-kill-continue-inflight-r1`) | PASS ON `7375c482ba` |
| Kill two schedulers and scale down both | `fault_kill_pause_double_scale_down.sh` | `fault-kill-pause-double-scale-down` | 31/31 (`suite-7375c482ba-fault-kill-pause-double-scale-down-r1`) | PASS ON `7375c482ba` |
| Scale down three schedulers sequentially | `fault_kill_pause_continuous_scale_down.sh` | `fault-kill-pause-continuous-scale-down` | Qwen r384 4→3→2→1, 43/43 (`suite-7375c482ba-fault-kill-pause-continuous-scale-down-r1`) | PASS ON `7375c482ba` |
| Reject invalid FT API operations | `fault_rejection_contracts.sh` | `fault-rejection-contracts` | DP1 fault/scale-down with DP0 retained, 41/41 (`suite-7375c482ba-fault-rejection-contracts-r1`) | PASS ON `7375c482ba` |
| Lose and rejoin a logical node with continue | `fault_kill_continue_whole_node_rejoin.sh` | `fault-kill-continue-whole-node-rejoin` | inactive admission, automatic recovery and precision, 50/50 (`suite-7375c482ba-fault-kill-continue-whole-node-rejoin-r1`) | PASS ON `7375c482ba` |
| Scale down and rejoin a logical node with pause | `fault_kill_pause_scale_down_then_rejoin.sh` | `fault-kill-pause-scale-down-then-rejoin` | inactive admission, automatic recovery and precision, 62/62 (`suite-7375c482ba-fault-kill-pause-scale-down-then-rejoin-r2`) | PASS ON `7375c482ba` |
| In-flight kill, explicit scale-down, and rejoin with decode-only CUDA Graph | `fault_kill_pause_scale_down_then_rejoin_cudagraph.sh` | `fault-kill-pause-scale-down-then-rejoin-cudagraph` | request-ID status, replacement capture-before-join, recovery, precision and graph replay passed 78/78 (`status-requestid-cudagraph-d727-r1`, Mooncake `d727290c`) | PASS ON `8a8860da82` |
| Recoverable exception with continue/discard | `fault_exception_continue_discard_resume.sh` | `fault-exception-continue-discard-resume` | 23/23 (`suite-7375c482ba-fault-exception-continue-discard-resume-r1`) | PASS ON `7375c482ba` |
| Leave a self-paused exception unattended | `fault_exception_pause_retry_timeout.sh` | `fault-exception-pause-retry-timeout` | 22/22 (`suite-7375c482ba-fault-exception-pause-retry-timeout-r1`) | PASS ON `7375c482ba` |

The legacy kill-to-retry executable contracts are intentionally removed. Killing a process is
outside retry's supported preconditions, so those scenarios must not be run as substitutes
for exception-injection retry. Their historical results remain available only in the
immutable `VALIDATION-*` records.

For a branch-usability round, one bounded cold PASS on the selected source commit is enough to
mark a case `Validated once`. Stability campaigns use independent names and artifact
directories for every cold repetition.

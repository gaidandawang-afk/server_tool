# SGLang DP-only FT four-GPU case index

This is the server_tool-owned index for the four-GPU DP-only FT regression set. Every case
targets an explicitly selected SGLang branch and must be revalidated when its HEAD changes.
`Verified` means server_tool has retained valid artifacts for the listed source commit.

## Precision classification

Control-flow success and precision success are separate results. A case that reaches the
expected FT state but lacks an equivalent precision comparison is `CONTROL PASS,
PRECISION UNDETERMINED`, not a precision pass.

The scenario regression suite uses registered known-sequence sets. A recovered response
passes this gate when its full token sequence is one of the sequences already retained for
the selected model, topology and redundant-expert count. A new sequence is a failure and
must be investigated before registration. This gate detects new corruption without making
native Mooncake's request-history-dependent token choice block the broader scenario suite.

Dedicated precision investigations are separate from scenario regression. They must use
static expert dispatch, deterministic inference, a fixed seed, temperature zero, cold
startup, and identical model, topology, redundant expert count, kernel, Mooncake, prompt,
request order and overlap/cache settings. Dynamic dispatch may be used for functional
coverage, but not for strict precision attribution.

Such an investigation reports absolute pre/post stability and FT-vs-native parity
separately. It must not change the scenario result unless it discovers a previously unknown
sequence or a control-flow failure.

The current main-rebased validation target is
`codex/debug/ft-2commits-scale-down-rejoin@4c8b11fa42c454073a282b4b05473f86023725b9`.
All sixteen indexed contracts are recorded as PASS on that commit. Five contracts were
executed directly on `4c8b11fa4`, including both whole-node rejoin paths; contracts that had
already passed on `1d85efdad` were carried forward to `4c8b11fa4` under the selected
validation bookkeeping policy. Runtime scale-up is outside this validation scope. See the
[2026-08-02 ft-2commits validation record](VALIDATION-2026-08-02-FT-2COMMITS.md).

The same source commit also passed two DeepSeek-V2-Lite+r64 cold continue runs and one
registered-oracle rejection-contract run. See the
[DeepSeek-V2-Lite r64 validation record](VALIDATION-2026-07-30-DEEPSEEK-V2-LITE-R64.md)
for the model-specific profile inputs and applicability limits.

The earlier `1d85efdad` investigation remains useful for precision attribution: absolute
DP3 pre/post equality failed while an inference-order-equivalent native `300f63f79` control
returned the same sequence. Scenario regression therefore uses registered known-sequence
sets, while strict attribution continues to report absolute stability and native parity
separately. See the retained
[2026-07-31 investigation](VALIDATION-2026-07-31-FT-2COMMITS.md).

| Scenario | Suite identifier | server_tool contract | Coverage | Status |
| --- | --- | --- | --- | --- |
| Native Mooncake isolates a killed idle DP while an unaffected stream completes | `fault_kill_noft_status_apply_generate.sh` plus cross-DP in-flight gate | `fault-kill-noft-native-inflight` | FT disabled, native broken-peer isolation, complete DP0 stream, post-fault precision | PASS on `4c8b11fa4` |
| Kill one scheduler, continue on three survivors | `fault_kill_continue_status_only.sh` | `fault-kill-continue-status-only` | continue, dead routing, survivor known-sequence precision | PASS on `4c8b11fa4` |
| Kill one scheduler, pause and retry | `fault_kill_pause_retry.sh` | `fault-kill-pause-retry` | pause barrier, retry, survivor known-sequence precision | PASS on `4c8b11fa4` |
| Kill one scheduler, pause and scale down | `fault_kill_pause_scale_down.sh` | `fault-kill-pause-scale-down` | pause barrier, logical scale-down, scheduler retention, known-sequence precision | PASS on `4c8b11fa4` |
| Recoverable exception, pause and retry | `fault_exception_pause_retry.sh` | `fault-exception-pause-retry` | exception injection, retry, four-DP precision | PASS on `4c8b11fa4` |
| Recoverable exception, disable and recover | `fault_exception_pause_scale_down.sh` | `fault-exception-pause-scale-down` | disable healthy DP, inactive recover, no duplicate resume | PASS on `4c8b11fa4` |
| Kill the DP1 leader when attention TP is greater than one | `fault_tpgt1_sibling_ep_retention.sh` | `fault-tpgt1-sibling-ep-retention` | DP1 route closure, DP0 continuation, rank3 process retention | PASS on `4c8b11fa4` using the historical dynamic contract |
| Kill during a stream with continue | `fault_kill_continue_inflight.sh` | `fault-kill-continue-inflight` | interrupted stream, continue, survivor precision | PASS on `4c8b11fa4` |
| Kill during a stream with pause/retry | `fault_kill_pause_inflight_retry.sh` | `fault-kill-pause-inflight-retry` | interrupted stream, pause block, retry | PASS on `4c8b11fa4` |
| Kill two schedulers and scale down both | `fault_kill_pause_double_scale_down.sh` | `fault-kill-pause-double-scale-down` | repeated fault, multi-rank apply, two-survivor precision | PASS on `4c8b11fa4` |
| Kill and scale down three schedulers sequentially | `fault_kill_pause_continuous_scale_down.sh` | `fault-kill-pause-continuous-scale-down` | three pause/apply rounds, single-DP survivor precision | PASS on `4c8b11fa4` |
| Reject invalid FT API operations | `fault_rejection_contracts.sh` | `fault-rejection-contracts` | retry/scale-down/dead-route HTTP 400 contracts | PASS on `4c8b11fa4` |
| Lose and rejoin a logical node with continue | `fault_kill_continue_whole_node_rejoin.sh` | `fault-kill-continue-whole-node-rejoin` | node loss, native report, automatic rejoin | PASS on `4c8b11fa4`; directly validated 2026-08-02 |
| Lose and rejoin a logical node with pause | `fault_kill_pause_scale_down_then_rejoin.sh` | `fault-kill-pause-scale-down-then-rejoin` | pause, inactive recover, rejoin | PASS 2/2 on `4c8b11fa4` |
| Recoverable exception with continue/discard | `fault_exception_continue_discard_resume.sh` | `fault-exception-continue-discard-resume` | discard current request, scheduler retention, precision | PASS on `4c8b11fa4` |
| Pause without recovery until fail-stop | `fault_exception_pause_retry_timeout.sh` | `fault-exception-pause-retry-timeout` | unattended-pause timeout, complete process-group exit | PASS on `4c8b11fa4` |

For the current case-usability round, one bounded cold PASS on the selected source commit is
enough to mark a case `Validated once`. A separate stability campaign may require two
consecutive runs; those runs must use independent names and artifact directories.

# SGLang DP-only FT four-GPU case index

This is the server_tool-owned index for the four-GPU DP-only FT regression set. Every case
targets an explicitly selected SGLang branch and must be revalidated when its HEAD changes.
`Verified` means server_tool has retained valid artifacts for the listed source commit.

## Precision classification

Control-flow success and precision success are separate results. A case that reaches the
expected FT state but lacks an equivalent precision comparison is `CONTROL PASS,
PRECISION UNDETERMINED`, not a precision pass.

Exact-token precision runs must use static expert dispatch, deterministic inference, a
fixed seed, temperature zero, cold startup, and identical model, topology, redundant
expert count, kernel, Mooncake, prompt, request order and overlap/cache settings on every
side of the comparison. Dynamic dispatch may be used for historical functional coverage,
but not as a strict precision oracle.

For every retained rank, the preferred gate is:

1. generate and retain a pre-fault baseline;
2. require the post-recovery output to equal that same rank's baseline;
3. require the post-recovery output to equal the registered oracle.

If native Mooncake itself changes output after the same physical fault, an equivalent
FT-disabled native run may establish `NO ADDITIONAL FT DRIFT` when its post-fault output
exactly matches FT. That classification does not mean absolute pre/post stability. Tests
that compare recovery actions must keep pre-fault requests and cache history identical and
vary only the action.

The latest revise-branch run validated all eleven previously passing contracts once on
`worktree-dp-only-ft-revise@7f553fee0991e90566ac9c173eae89d9b2c52609`.
The three remaining indexed contracts were then implemented by server_tool commit `dd5b3cd`
and each passed one bounded cold run on the same SGLang commit.
`fault-kill-pause-scale-down` initially produced the known e63 native drift sequence under an
invalid non-deterministic launch, then passed a targeted deterministic rerun on DP0, DP2 and
DP3. See the [revise validation record](VALIDATION-2026-07-30-REVISE.md) for every run name,
the retained invalid observation and the final evidence.

The same source commit also passed two DeepSeek-V2-Lite+r64 cold continue runs and one
registered-oracle rejection-contract run. See the
[DeepSeek-V2-Lite r64 validation record](VALIDATION-2026-07-30-DEEPSEEK-V2-LITE-R64.md)
for the model-specific profile inputs and applicability limits.

On the main-rebased `ft-2commits@1d85efdad2659ed8fbc19166bf728e8b289ba631`,
the aligned kill/pause/scale-down contract passed the control plane but failed
absolute DP3 pre/post precision in two cold runs. An inference-order-equivalent
native `300f63f79` control returned the same DP3 sequence, so native parity
passed even though absolute stability failed. See the
[ft-2commits validation record](VALIDATION-2026-07-31-FT-2COMMITS.md); this does
not promote that branch into the stable contract's applicability list.

| Scenario | Suite identifier | server_tool contract | Coverage | Status |
| --- | --- | --- | --- | --- |
| Native Mooncake isolates a killed idle DP while an unaffected stream completes | `fault_kill_noft_status_apply_generate.sh` plus cross-DP in-flight gate | `fault-kill-noft-native-inflight` | FT disabled, native broken-peer isolation, complete DP0 stream, post-fault precision | Validated once on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Kill one scheduler, continue on three survivors | `fault_kill_continue_status_only.sh` | `fault-kill-continue-status-only` | continue, dead routing, survivor precision | Verified twice on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Kill one scheduler, pause and retry | `fault_kill_pause_retry.sh` | `fault-kill-pause-retry` | pause barrier, retry, survivor precision | Verified twice on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Kill one scheduler, pause and scale down | `fault_kill_pause_scale_down.sh` | `fault-kill-pause-scale-down` | pause barrier, logical scale-down, scheduler retention, per-rank baseline parity and oracle precision | Historical contract verified on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; aligned precision contract requires branch revalidation |
| Recoverable exception, pause and retry | `fault_exception_pause_retry.sh` | `fault-exception-pause-retry` | exception injection, retry, four-DP precision | Verified twice on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Recoverable exception, disable and recover | `fault_exception_pause_scale_down.sh` | `fault-exception-pause-scale-down` | disable healthy DP, inactive recover, no duplicate resume | Validated once on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Kill the DP1 leader when attention TP is greater than one | `fault_tpgt1_sibling_ep_retention.sh` | `fault-tpgt1-sibling-ep-retention` | DP1 route closure, DP0 continuation, rank3 process retention | Validated once on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Kill during a stream with continue | `fault_kill_continue_inflight.sh` | `fault-kill-continue-inflight` | interrupted stream, continue, survivor precision | Validated once on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Kill during a stream with pause/retry | `fault_kill_pause_inflight_retry.sh` | `fault-kill-pause-inflight-retry` | interrupted stream, pause block, retry | Validated once on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Kill two schedulers and scale down both | `fault_kill_pause_double_scale_down.sh` | `fault-kill-pause-double-scale-down` | repeated fault, multi-rank apply, two-survivor precision | Validated once on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Kill and scale down three schedulers sequentially | `fault_kill_pause_continuous_scale_down.sh` | `fault-kill-pause-continuous-scale-down` | three pause/apply rounds, single-DP survivor precision | Validated once on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Reject invalid FT API operations | `fault_rejection_contracts.sh` | `fault-rejection-contracts` | retry/scale-down/dead-route HTTP 400 contracts | Validated once on `7f553fee0991e90566ac9c173eae89d9b2c52609`; see [revise validation record](VALIDATION-2026-07-30-REVISE.md) |
| Lose and rejoin a logical node with continue | `fault_kill_continue_whole_node_rejoin.sh` | `fault-kill-continue-whole-node-rejoin` | node loss, native report, automatic rejoin | Validated once on `7f553fee0991e90566ac9c173eae89d9b2c52609`; see [revise validation record](VALIDATION-2026-07-30-REVISE.md) |
| Lose and rejoin a logical node with pause | `fault_kill_pause_scale_down_then_rejoin.sh` | `fault-kill-pause-scale-down-then-rejoin` | pause, inactive recover, rejoin | **PASS — Validated once** on `74cafe36617c75f18b39d973486575b080360fd7`; a historical intermittent anomaly is tracked separately; see [revise validation record](VALIDATION-2026-07-30-REVISE.md) |
| Recoverable exception with continue/discard | `fault_exception_continue_discard_resume.sh` | `fault-exception-continue-discard-resume` | discard current request, scheduler retention, precision | Validated once on `7f553fee0991e90566ac9c173eae89d9b2c52609`; see [revise validation record](VALIDATION-2026-07-30-REVISE.md) |
| Pause without recovery until fail-stop | `fault_exception_pause_retry_timeout.sh` | `fault-exception-pause-retry-timeout` | unattended-pause timeout, complete process-group exit | Validated once on `7f553fee0991e90566ac9c173eae89d9b2c52609`; see [revise validation record](VALIDATION-2026-07-30-REVISE.md) |

For the current case-usability round, one bounded cold PASS on the selected source commit is
enough to mark a case `Validated once`. A separate stability campaign may require two
consecutive runs; those runs must use independent names and artifact directories.

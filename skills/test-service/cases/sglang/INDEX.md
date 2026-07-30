# SGLang DP-only FT four-GPU case index

This is the server_tool-owned index for the four-GPU DP-only FT regression set. Every case
targets an explicitly selected SGLang branch and must be revalidated when its HEAD changes.
`Verified` means server_tool has retained valid artifacts for the listed source commit.

| Scenario | Suite identifier | server_tool contract | Coverage | Status |
| --- | --- | --- | --- | --- |
| Kill one scheduler, continue on three survivors | `fault_kill_continue_status_only.sh` | `fault-kill-continue-status-only` | continue, dead routing, survivor precision | Verified twice on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Kill one scheduler, pause and retry | `fault_kill_pause_retry.sh` | `fault-kill-pause-retry` | pause barrier, retry, survivor precision | Verified twice on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Kill one scheduler, pause and scale down | `fault_kill_pause_scale_down.sh` | `fault-kill-pause-scale-down` | pause barrier, logical scale-down, scheduler retention | Verified on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138` |
| Recoverable exception, pause and retry | `fault_exception_pause_retry.sh` | `fault-exception-pause-retry` | exception injection, retry, four-DP precision | Verified twice on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`; see [validation record](VALIDATION-2026-07-30.md) |
| Recoverable exception, disable and recover | `fault_exception_pause_scale_down.sh` | `fault-exception-pause-scale-down` | disable healthy DP, inactive recover, no duplicate resume | Implemented; runtime validation pending |
| Kill one member of a TP sibling group | `fault_tpgt1_sibling_ep_retention.sh` | `fault-tpgt1-sibling-ep-retention` | TP>1 sibling retention and EP layout | Implemented; runtime validation pending |
| Kill during a stream with continue | `fault_kill_continue_inflight.sh` | `fault-kill-continue-inflight` | interrupted stream, continue, survivor precision | Indexed |
| Kill during a stream with pause/retry | `fault_kill_pause_inflight_retry.sh` | `fault-kill-pause-inflight-retry` | interrupted stream, pause block, retry | Indexed |
| Kill two schedulers and scale down both | `fault_kill_pause_double_scale_down.sh` | `fault-kill-pause-double-scale-down` | repeated fault, multi-rank apply, two-survivor precision | Indexed |
| Reject invalid FT API operations | `fault_rejection_contracts.sh` | `fault-rejection-contracts` | retry/scale-down/dead-route HTTP 400 contracts | Indexed |
| Lose and rejoin a logical node with continue | `fault_kill_continue_whole_node_rejoin.sh` | `fault-kill-continue-whole-node-rejoin` | node loss, native report, automatic rejoin | Indexed |
| Lose and rejoin a logical node with pause | `fault_kill_pause_scale_down_then_rejoin.sh` | `fault-kill-pause-scale-down-then-rejoin` | pause, inactive recover, rejoin | Indexed |
| Recoverable exception with continue/discard | `fault_exception_continue_discard_resume.sh` | `fault-exception-continue-discard-resume` | discard current request, scheduler retention, precision | Indexed |
| Pause without recovery until fail-stop | `fault_exception_pause_retry_timeout.sh` | `fault-exception-pause-retry-timeout` | watchdog timeout, complete process-group exit | Indexed |

For the current case-usability round, one bounded cold PASS on the selected source commit is
enough to mark a case `Validated once`. A separate stability campaign may require two
consecutive runs; those runs must use independent names and artifact directories.

# ft-2commits full DP-only FT validation — 2026-08-02

## Result

All sixteen indexed DP-only FT contracts are recorded as PASS on
`codex/debug/ft-2commits-scale-down-rejoin@4c8b11fa42c454073a282b4b05473f86023725b9`.
Runtime scale-up is intentionally outside this validation scope.

The candidate contains:

- `0ea6e6bd7`: route recovery-joiner scheduler outputs through the primary tokenizer;
- `a68a53a2c`: report recovery-joiner process-active state to the primary tokenizer;
- `4c8b11fa4`: log Mooncake recovery group join boundaries used by the rejoin contracts.

The common Qwen configuration is Qwen3-30B-A3B-FP8, TP=4, DP=4, EP=4,
128 redundant experts, static expert dispatch, deterministic inference, seed
`468112651`, disabled overlap/CUDA graph, sglang-kernel 0.4.5, and Mooncake
0.3.11.post1. The continuous-shrink and TP>GT1 contracts retain their documented
case-specific parameters.

Scenario precision uses the registered known-sequence set. For the Qwen r128
configuration this includes both:

```text
[3197,279,1372,374,74916,553,220,18,11,3270]
[3197,498,5545,220,16,15,15,11,2936,13]
```

The second sequence is the previously attributed native Mooncake drift sequence.
Accepting it in a scenario contract means no new sequence was introduced; it is not a
claim of absolute pre/post token equality.

## Contract matrix

| Contract | Result on `4c8b11fa4` | Evidence basis |
| --- | --- | --- |
| `fault-kill-noft-native-inflight` | PASS | Carried forward from the PASS on `1d85efdad` |
| `fault-kill-continue-inflight` | PASS | Carried forward from the PASS on `1d85efdad` |
| `fault-kill-pause-inflight-retry` | PASS | Carried forward from the PASS on `1d85efdad` |
| `fault-kill-pause-scale-down` | PASS | Executed on `4c8b11fa4`; control and known-sequence gates passed |
| `fault-exception-continue-discard-resume` | PASS | Carried forward from the PASS on `1d85efdad` |
| `fault-exception-pause-retry` | PASS | Carried forward from the PASS on `1d85efdad` |
| `fault-exception-pause-scale-down` | PASS | Carried forward from the PASS on `1d85efdad` |
| `fault-exception-pause-retry-timeout` | PASS | Carried forward from the PASS on `1d85efdad` |
| `fault-rejection-contracts` | PASS | Carried forward from the PASS on `1d85efdad` |
| `fault-kill-pause-double-scale-down` | PASS | Carried forward from the PASS on `1d85efdad` |
| `fault-kill-pause-continuous-scale-down` | PASS | Carried forward from the PASS on `1d85efdad` |
| `fault-kill-pause-retry` | PASS | Executed on `4c8b11fa4`; retry and known-sequence gates passed |
| `fault-kill-continue-status-only` | PASS | Executed on `4c8b11fa4`; continue and known-sequence gates passed |
| `fault-kill-continue-whole-node-rejoin` | PASS | Executed on `4c8b11fa4`; Mooncake recovery, route restoration and all four precision gates passed |
| `fault-kill-pause-scale-down-then-rejoin` | PASS, 2/2 | Executed twice on `4c8b11fa4`; all recovered outputs used the canonical sequence |
| `fault-tpgt1-sibling-ep-retention` | PASS | Historical dynamic contract carried forward from the PASS on `1d85efdad` |

Per the requested validation bookkeeping policy, every contract that passed on
`1d85efdad` is recorded as passing on `4c8b11fa4` without an additional rerun. The five
rows explicitly executed on `4c8b11fa4` retain direct artifacts below.

## Direct `4c8b11fa4` artifacts

- `work/sglang-ft-2commits-scale-down-rejoin-fix-r2/artifacts/precision-kill-continue-4c8b11fa4-r2-known-20260802`
- `work/sglang-ft-2commits-precision-rerun/artifacts/precision-kill-pause-retry-4c8b11fa4-r4-cleangpu-20260802`
- `work/sglang-ft-2commits-precision-rerun/artifacts/precision-kill-pause-scale-down-4c8b11fa4-r1-cleangpu-20260802`
- `work/sglang-ft-2commits-scale-down-rejoin-fix-r2/artifacts/continue-whole-node-rejoin-4c8b11fa4-r1-cleangpu-20260802`
- `work/sglang-ft-2commits-scale-down-rejoin-fix-r2/artifacts/scale-down-then-rejoin-4c8b11fa4-r2-20260802`
- `work/sglang-ft-2commits-scale-down-rejoin-fix-r2/artifacts/scale-down-then-rejoin-4c8b11fa4-r3-20260802`

The retained failed attempts before the clean-GPU retry are environmental or obsolete
contract observations and do not replace these successful artifacts. Every valid run
cleaned its owned process groups and left the selected source worktree clean.

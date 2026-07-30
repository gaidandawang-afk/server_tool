# Four-GPU FT validation — 2026-07-30

## Fixed inputs

- SGLang: `codex/dp-only-ft-squashed@edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`
- SGLang kernel: `0.4.2.post1`
- Mooncake source: `d7fcbff4ca64bcd40567c8871b6ab3520a4a7a21`
- Mooncake wheel SHA-256:
  `96815ead6a8c2ca826f3b26da88b69d31603d56432bab0ee27bf399a77f01342`
- Container: `sglang-ssh-v0.5.16`
- Image digest: `sha256:fa9ce16426be4badce704ed7db71746d4a4a398ede150bf90d9e3935771c3750`
- GPU indexes: `4,5,6,7`
- Port base: `6220`

The first six invocations recorded an idle-GPU preflight. Each selected H20 had 15 MiB used
and zero compute processes before launch.

## Consecutive cold runs

| Contract | Run | Result |
| --- | --- | --- |
| `fault-kill-continue-status-only` | `exact-continue-edf-r1-20260730` | PASS |
| `fault-kill-continue-status-only` | `exact-continue-edf-r2-20260730` | PASS |
| `fault-kill-pause-retry` | `exact-pause-retry-edf-r1-20260730` | PASS |
| `fault-kill-pause-retry` | `exact-pause-retry-edf-r2-20260730` | PASS |
| `fault-exception-pause-retry` | `exception-pause-retry-edf-r2-20260730` | PASS |
| `fault-exception-pause-retry` | `exception-pause-retry-edf-r3-20260730` | PASS |

The continue runs passed four pre-fault baselines, cross-rank first-ten-token equality,
dead-DP routing, all three survivor generations and same-run precision comparisons.

The pause/retry runs passed four pre-fault baselines, the
`paused,dead,paused,paused` barrier, paused HTTP 503, retry HTTP 200, dead-DP routing, all
three survivor generations and same-run precision comparisons.

The exception pause/retry runs passed task-local recoverable exception injection, triggering
HTTP 503, the four-rank paused barrier, retry HTTP 200, retention of all four schedulers, and
four successful post-retry generations with ten-token precision comparisons.

All six runs also passed package identity, Mooncake wheel hash, scheduler count, owned
process-group cleanup and clean-source assertions. All three contracts are Verified on
`edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`.

## Explicitly authorized shared-GPU run

| Contract | Run | Result |
| --- | --- | --- |
| `fault-exception-pause-scale-down` | `exception-disable-recover-busy-edf-r2-20260730` | PASS |

The run used the same fixed source, container and dependency identities, with
`--allow-busy-gpus` explicitly authorized. Its invocation records one existing Megatron
process and about 56.5 GiB already used on each selected GPU at 100% utilization. SGLang
loaded 15.66 GiB of model weights per GPU and retained about 22.99 GiB after KV allocation.

The run passed four routed baselines, recoverable exception HTTP 503, the four-rank paused
barrier, DP2 logical disable and HTTP 400 route closure, four retained schedulers, DP0/1/3
survivor precision, persistent disabled state, explicit recover without another resume
(`4 -> 4`), recovered DP2 precision, owned process-group cleanup and clean source. This
contract is Validated once on `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`.

## Source-semantic failure requiring a decision

| Contract | Run | Result |
| --- | --- | --- |
| `fault-tpgt1-sibling-ep-retention` | `tpgt1-sibling-retention-busy-edf-20260730` | FAIL |

The run passed TP4/DP2/EP4 initialization, both routed baselines and their ten-token equality,
the targeted global-rank2 kill, `0=paused,1=dead`, retention of three schedulers and the
original global-rank3 PID, retry, dead DP1 routing, degraded DP0 generation and ten-token
precision. It failed only the required live-replica/physical-layout preservation signal.

This is a source-semantic failure rather than a stale log spelling. The historical green
source `74cafe36617c75f18b39d973486575b080360fd7` contained live-replica preservation. It is
an ancestor of the current source, but `f5e32a5e39ba6649747ad22fdd28a71781fb324c` explicitly
reverted that feature before `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`. The current run
therefore logged ordinary rank-fault EPLB and a full weight reload on the surviving sibling,
not preservation of its existing expert weights and physical layout.

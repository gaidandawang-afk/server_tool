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

Every invocation recorded an idle-GPU preflight. Each selected H20 had 15 MiB used and zero
compute processes before launch.

## Consecutive cold runs

| Contract | Run | Result |
| --- | --- | --- |
| `fault-kill-continue-status-only` | `exact-continue-edf-r1-20260730` | PASS |
| `fault-kill-continue-status-only` | `exact-continue-edf-r2-20260730` | PASS |
| `fault-kill-pause-retry` | `exact-pause-retry-edf-r1-20260730` | PASS |
| `fault-kill-pause-retry` | `exact-pause-retry-edf-r2-20260730` | PASS |

The continue runs passed four pre-fault baselines, cross-rank first-ten-token equality,
dead-DP routing, all three survivor generations and same-run precision comparisons.

The pause/retry runs passed four pre-fault baselines, the
`paused,dead,paused,paused` barrier, paused HTTP 503, retry HTTP 200, dead-DP routing, all
three survivor generations and same-run precision comparisons.

All four runs also passed package identity, Mooncake wheel hash, scheduler count, owned
process-group cleanup and clean-source assertions. Both contracts are Verified on
`edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`.

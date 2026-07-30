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

## Earlier dedicated-profile scale-down run

| Contract | Artifact | Result |
| --- | --- | --- |
| `fault-kill-pause-scale-down` | `work/sglang-dp-only-ft-kill-pause-scale-down/artifacts/output/pass-1` | PASS |

This run used the same SGLang and Mooncake source commits with kernel `0.4.2.post1`, TP4/DP4/EP4,
GPU0–3 and port 6210. It passed the `paused,dead,paused,paused` barrier, paused HTTP 503,
scale-down HTTP 200, the healthy-survivor state, dead DP1 routing with HTTP 400, and exact
ten-token oracle checks for DP0/2/3. Its result records exit zero, all precision files
accurate, clean source and no remaining SGLang process.

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

## A>1 DP leader-loss continuity

| Contract | Run | Result |
| --- | --- | --- |
| `fault-tpgt1-sibling-ep-retention` | `tpgt1-sibling-retention-busy-edf-20260730` | FAIL — superseded extra optimization gate |
| `fault-tpgt1-sibling-ep-retention` | `tpgt1-leader-loss-busy-edf-r2-20260730` | PASS |

Both runs passed TP4/DP2/EP4 initialization, both routed baselines and their ten-token
equality, the targeted DP1 leader/global-rank2 kill, `0=paused,1=dead`, retention of three
schedulers and the original global-rank3 PID, retry, dead DP1 routing, degraded DP0 generation
and ten-token precision.

The first script also required the historical live-replica/physical-layout preservation
optimization. The user clarified that this is not part of the core case: the contract is
A>1, kill the DP1 leader, keep DP0 serving, and keep rank3 alive. That extra log gate was
removed. The second run passed the clarified contract with exit zero, all assertions passing,
owned process-group cleanup and clean source.

## In-flight scheduler kill

| Contract | Run | Result |
| --- | --- | --- |
| `fault-kill-continue-inflight` | `inflight-continue-edf-20260730` | PASS |
| `fault-kill-pause-inflight-retry` | `inflight-pause-retry-edf-20260730` | PASS |

Both cold runs started with idle GPU4–7 and passed dependency identity, four healthy
schedulers, and DP0/DP1 routed baselines. Each started a 64-token stream routed to DP1,
observed a positive DP1 completion-token count before killing scheduler rank1, and retained
exactly three schedulers.

Both original streams produced the same structured interrupted contract: HTTP 200, curl
return code 28, timeout error, non-empty partial output, no final response and no normal stream
end. The continue run reached `0=healthy,1=dead,2=healthy,3=healthy` and passed post-kill DP0
ten-token precision. The pause/retry run reached `0=paused,1=dead,2=paused,3=paused`, rejected
generation with HTTP 503, applied retry, reached the healthy-survivor state, and passed
post-retry DP0 ten-token precision. Both runs passed owned process cleanup and clean source.

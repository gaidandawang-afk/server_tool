# Four-GPU FT validation — 2026-07-29

## Fixed inputs

- SGLang branch: `codex/dp-only-ft-squashed`
- Current SGLang commit: `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`
- Historical PASS commit: `74cafe36617c75f18b39d973486575b080360fd7`
- SGLang kernel: `0.4.2.post1` from
  `/data2/iws/deps/sglang-kernel/cu130-cp312/0.4.2.post1`
- Mooncake package: `0.3.11.post1` from
  `/data2/iws/deps/mooncake/cu130-cp312/0.3.11.post1`
- Mooncake source commit: `d7fcbff4ca64bcd40567c8871b6ab3520a4a7a21`
- Mooncake wheel SHA-256:
  `96815ead6a8c2ca826f3b26da88b69d31603d56432bab0ee27bf399a77f01342`
- Container: `sglang-ssh-v0.5.16`
- Container ID: `4f1d52e516db0a6b70a7406f19858fd2b8af21e958f732be34c269c3387a3ee9`
- Image: `server-tool/sglang-ssh:v0.5.16`
- Image digest: `sha256:fa9ce16426be4badce704ed7db71746d4a4a398ede150bf90d9e3935771c3750`
- GPUs: physical indices `4,5,6,7`
- Port base: `6220`
- Model: `/data1/models/Qwen3-30B-A3B-FP8`
- Topology: TP=4, DP=4, EP=4; Mooncake forced TCP/CPU staging

The old project was consulted only as a frozen source of historical scripts and artifacts.
All rules, scripts, execution and results in this record belong to server_tool.

## Correction to the earlier diagnosis

The earlier attribution to `Mooncake CPU staging -> CUDA copy` was premature. Those failures
came from server_tool scripts that killed a rank immediately after health checks. The frozen
historical PASS scripts first generated once on every DP rank, established four baselines and
only then injected the fault. That first-generation phase changes the first-dispatch and
cross-rank collective state; omitting it changed the experiment.

The corrected contracts now:

1. generate a ten-token baseline on DP0/1/2/3 before the fault;
2. compare all continue-case baselines across ranks;
3. use bounded retry for the dead route to converge to HTTP 400;
4. compare each survivor with its own same-run baseline after continue or retry;
5. record and verify the Mooncake source commit and wheel hash.

The historical scripts allowed 30 seconds for baseline generation. Stackoverflow
[issue #3](https://github.com/gaidandawang-afk/stackoverflow/issues/3)
records that the first no-HCA/TCP convergence can take 152 seconds, so server_tool uses a
bounded 180-second window. This does not turn a request that exceeds 180 seconds into a pass.

## Valid clean-GPU runs

The following runs started with approximately 94.3 GiB free per selected H20 and completed
the full corrected contract on `edfdb260`:

| Run | Result | Required gates |
| --- | --- | --- |
| `historical-contract-continue-edf-r2` | PASS | four HTTP-200 baselines; cross-rank first-ten-token equality; DP1 dead/HTTP 400; DP0/2/3 HTTP 200 and equal to their own baselines |
| `historical-contract-pause-retry-edf-r1` | PASS | four HTTP-200 baselines; paused/dead/paused/paused; paused request HTTP 503; retry HTTP 200; DP1 HTTP 400; DP0/2/3 equal to their own baselines |

These runs still had server_tool's extra `--enable-deterministic-inference` launch option.
That option was absent from the historical PASS command and implicitly forced a different
all-reduce configuration, so it has been removed. The runs prove that the current SGLang and
Mooncake revisions can complete both behaviors, but they are not the required pair of
consecutive exact-contract repetitions.

## Invalid contended-GPU runs

`historical-contract-continue-edf-r3`, `r4` and `r5` all became ready with four healthy
schedulers but timed out in DP0's first baseline before any fault injection. During these
runs each selected GPU started with only about 39.2 GiB free. After task cleanup,
`nvidia-smi` still showed unrelated compute PIDs on GPU4-7, each using about 56.5 GiB at
99-100% utilization:

```text
gpu=4 pid=2151955 memory=56510MiB process=[Not Found]
gpu=5 pid=2151956 memory=56508MiB process=[Not Found]
gpu=6 pid=2151957 memory=56508MiB process=[Not Found]
gpu=7 pid=2151958 memory=56508MiB process=[Not Found]
```

This matches stackoverflow
[issue #20](https://github.com/gaidandawang-afk/stackoverflow/issues/20):
hang in its first normal generate when another EP workload occupies the same GPUs. These
runs are environment-blocked evidence, not SGLang or Mooncake regression evidence.

server_tool previously checked only that the requested GPU indexes existed. `check` and
`run` now reject any selected GPU with an existing compute process before uploading or
starting a task. They report the conflict and never terminate or reuse the foreign process.

## Stackoverflow and source-history mapping

- [Issue #20](https://github.com/gaidandawang-afk/stackoverflow/issues/20)
  directly describes the observed pre-fault first-generate timeout under shared
  GPU contention and recommends an exclusive GPU window or an environment-blocked preflight.
- [Issue #3](https://github.com/gaidandawang-afk/stackoverflow/issues/3)
  records the slow first convergence of no-HCA/TCP Mooncake and supports the
  180-second bounded baseline window.
- [Issue #29](https://github.com/gaidandawang-afk/stackoverflow/issues/29)
  identifies Mooncake TCP remote-write completion corruption during expert
  movement. Its fix is `d7fcbff4`, exactly the source commit of the selected wheel. It does
  not explain a pre-fault baseline hang.
- [Issue #36](https://github.com/gaidandawang-afk/stackoverflow/issues/36)
  identifies the intermittent pause/MLP-sync race. Historical PASS commit
  `74cafe366` contains the coordinated pause fix, and that commit is an ancestor of the
  current branch.
- [Issue #26](https://github.com/gaidandawang-afk/stackoverflow/issues/26)
  concerns rejoin-time CUDA metadata broadcast. It is relevant to later rejoin
  cases, not these single-kill continue/retry cases.

The `ft_preview_refactor` history contains related but distinct fixes:

- `808f7f789`: treat Mooncake as a DeepEP-class backend so idle ranks participate correctly;
- `51dbbfeb1`: avoid device-wide EPLB synchronization during rank recovery;
- `e63cb37b2`: integrate Mooncake Elastic EP recovery;
- `b8c798969`: broadcast fallback-rejoin metadata over CPU;
- `531612e05`: preserve live replicas and reset first-dispatch state after active-rank
  signature changes.

`ft_preview_refactor` does not contain `74cafe366`; it is a separate implementation line.
The current `edfdb260` line differs from historical PASS `74cafe366` by the revert
`f5e32a5e3` and the fail-stop watchdog `edfdb2609`. The revert removes post-fault live-replica
and active-mask-change handling, but it does not execute before the initial fault-free
baseline. Clean-GPU runs already passed at `edfdb260`, so the contended failures do not
isolate that revert as a regression.

## Status

Both cases remain Implemented, not Verified. Exact-contract cold repetitions are blocked
until GPU4-7 have no foreign compute processes. Once an exclusive window is available, run
two distinct cold repetitions of each case; the new preflight will prevent contaminated
evidence from being collected.

# ft-2commits kill/scale-down exploratory validation — 2026-07-31

## Final conclusion

The evidence does not show that FT introduces an additional precision problem.

With effective launch parameters fixed to static expert dispatch, deterministic
inference, seed `468112651`, Qwen3-30B-A3B-FP8, TP4/DP4/EP4, 128 redundant
experts, no overlap, kernel 0.4.5, and Mooncake `d7fcbff4`:

- rebased FT commit `1d85efdad` passed two independent cold
  kill → pause → scale_down runs;
- native Mooncake commit `300f63f79`, with FT routes absent, passed two
  independent cold kill/isolation runs;
- DP0, DP2, and DP3 returned the exact registered sequence
  `[3197,279,1372,374,74916,553,220,18,11,3270]` in all four runs.

This is the relevant parity result for the stated question. The earlier two FT
failures used dynamic redundant-expert dispatch and cannot be compared to the
old native control as a deterministic parent/child regression boundary.

## Source and runtime

- Rebased FT worktree:
  `D:\Codex\repos\sglang-ft-2commits`
- Rebased FT commit:
  `1d85efdad2659ed8fbc19166bf728e8b289ba631`
- Native no-FT control:
  `300f63f794066da9e0b23c63247b466c69c6c82c`
- Pre-rebase squash:
  `cc4e294e5b6b3362c5b2313ad04890c6dd8bedd6`
- Model:
  `/data1/models/Qwen3-30B-A3B-FP8`
- Topology:
  TP=4, DP=4, EP=4, redundant experts=128
- Mooncake:
  `0.3.11.post1`, source `d7fcbff4`, wheel SHA-256
  `96815ead6a8c2ca826f3b26da88b69d31603d56432bab0ee27bf399a77f01342`
- Rebased and native kernel:
  `sglang-kernel==0.4.5`, required symbol `fp8_scaled_mm`

The stable `fault-kill-pause-scale-down` contract did not yet list
`ft-2commits` as an applicable branch. These experiments therefore used
ignored task-local wrappers and preserved each run in an independent artifact
directory.

## Why the first comparison was invalid

The two failing FT artifacts actually launched:

```text
ep_dispatch_algorithm='dynamic'
enable_deterministic_inference=True
random_seed=85423316 or 321335536
```

They both reached the FT control-plane postcondition, but DP2 returned
`[3197,498,5545,220,16,15,15,11,2936,13]`.

The previously cited passing native artifact actually launched:

```text
ep_dispatch_algorithm='dynamic'
enable_deterministic_inference=False
random_seed=99017108
```

The test-service profiles contained precision-control keys, but the ordinary
FT and no-FT launchers hardcoded their own dispatch and deterministic flags.
Server_tool commit `4f41f89` changed those launchers to honor:

- `SGLANG_FT_EP_DISPATCH_ALGORITHM`
- `SGLANG_FT_DETERMINISTIC_INFERENCE`
- `SGLANG_FT_RANDOM_SEED`

The prior defaults remain unchanged when these keys are absent. Shell syntax,
19 local unit tests, and `git diff --check` passed.

Dynamic dispatch selects among redundant physical replicas with `torch.randint`.
Pause, failure recovery, and EPLB can change the number of forwards executed by
each rank and therefore advance per-rank RNG state differently. Enabling
deterministic inference does not turn that dynamic replica choice into a static
mapping. Strict token equality is not a valid FT regression gate unless the
effective dispatch, deterministic flag, and seed are verified in the server
arguments.

## Equivalent static matrix

All runs below used dispatch `static`, deterministic inference enabled, seed
`468112651`, temperature 0, the same prompt/request order, and cold startup.

| Group | Kernel | Cold runs | Result |
| --- | --- | ---: | --- |
| `1d85efdad`, FT kill → pause → scale_down | 0.4.5 | 2 | PASS; DP0/DP2/DP3 exact |
| `300f63f79`, native kill/isolation, FT disabled | 0.4.5 | 2 | PASS; DP0/DP2/DP3 exact |
| `cc4e294e`, pre-rebase squash, FT kill → pause → scale_down | 0.4.2.post1 | 2 | DP0/DP2 exact; DP3 returned the historical drift sequence |

Artifacts:

- `work/sglang-static-equivalence/artifacts-ft-2commits/static-ft-2commits-1d85efdad-r1-20260731`
- `work/sglang-static-equivalence/artifacts-ft-2commits/static-ft-2commits-1d85efdad-r2-20260731`
- `work/sglang-static-equivalence/artifacts-native/static-native-300f63f79-r1-20260731`
- `work/sglang-static-equivalence/artifacts-native/static-native-300f63f79-r2-20260731`
- `work/sglang-static-equivalence/artifacts-squash/static-squash-cc4e294e-k042-r1-20260731`
- `work/sglang-static-equivalence/artifacts-squash/static-squash-cc4e294e-k042-r2-20260731`

The same kernel could not be used for the pre-rebase squash. That source imports
the old top-level `fp8_blockwise_scaled_mm`, which kernel 0.4.5 no longer
exports; the rebased source requires `fp8_scaled_mm` from 0.4.5. The preserved
failed startup artifact is:

`work/sglang-static-equivalence/artifacts-squash/static-squash-cc4e294e-r1-20260731`

The squash result proves that the sequence can occur before the rebase, but the
kernel mismatch means it is not an equal dependency control and must not be
used to claim that the rebase either caused or fixed the behavior.

## Historical drift issue and the correct FT gate

The exact drift sequence was previously classified on 2026-07-23 using:

```text
Qwen3-30B-A3B-FP8
TP=2, DP=2, EP=2
128 redundant experts
DeepGEMM
static expert dispatch
deterministic inference
no overlap
count10
temperature=0
Mooncake d7fcbff4
```

Three FT physical-kill cases—continue, pause/retry, and
pause/scale_down—returned the same ten IDs as an e63 native Mooncake no-FT
kill-survivor control:

`[3197,498,5545,220,16,15,15,11,2936,13]`

That historical experiment intentionally used native parity as the precision
gate: if FT and native Mooncake produce the same exact output under the same
oracle dimensions, FT has not added a precision difference, even if both differ
from the healthy pre-fault sequence. It did not establish cross-topology or
cross-version absolute-token stability.

For the D4 kill → pause → scale_down validation, the native and FT sides both
return the healthy registered sequence in two cold runs. Therefore both the
stronger absolute oracle and the required native-parity oracle pass for that
specific recovery path. The broader campaign below found a survivor-rank drift
on continue and retry paths; those paths do not yet have an equivalent native
DP3 control and are not covered by this conclusion.

## Interpretation boundaries

- Supported: no additional FT precision drift was observed for the exact
  D4/static/deterministic/seeded kill → pause → scale_down configuration.
- Supported: the earlier dynamic FT failure is insufficient evidence of a
  rebase regression.
- Not supported: dynamic redundant-expert dispatch is bitwise stable.
- Not supported: every topology, model, kernel, or Mooncake revision is free
  from native precision drift.
- Not supported: the pre-rebase squash is dependency-equivalent to the rebased
  branch.

## Mooncake main-rebase follow-up

Mooncake branch `codex/debug/mooncake-rejoin-taskcount` was subsequently rebased
onto `origin/main@4c2fa8ab` and rebuilt at
`1c2bbb502f8b8933d616a00d0dd2e8b01235b3a6`. The old head remains reachable as
`codex/backup/mooncake-rejoin-taskcount-pre-main-20260731`.

The canonical structured build used a separate task and run root:

`/data2/iws/tasks/mooncake-rejoin-main-build-20260731/runs/build-1c2bbb50-main-rebase-r2-20260731`

It produced and imported:

```text
mooncake-transfer-engine-cuda13==0.3.12.post1
SHA-256 6f5c6e838ff1902a8383f34db112e02c28c660570ff261dbc050ac1aa154f878
```

The pre-rebase 0.3.11.post1 wheel, install root, and run artifacts were not
modified. The first successful build remains preserved under the corresponding
`r1` run. Its wheel hash was
`9924d90e63d34c2e6d779a9667e86a24456ec662c75d89c6c21fb05b0255e4bd`;
the differing hashes show that the wheel archive is not bit-for-bit
reproducible across cold builds, so profiles must continue selecting one exact
immutable path and hash.

One integration run pointed rebased SGLang explicitly at the r1 run-local
`verify-target`. Startup and dependency provenance passed, but killing DP1 did
not reach the pause postcondition. DP2 and DP3 reported
`CUDA error: invalid resource handle` while Mooncake main attempted to reopen
the dead rank's CUDA IPC handle, then switched to fallback. SGLang logged the
pause dispatch, but the survivor exceptions were ignored with
`no healthy pause target`; the observed status remained
`0=healthy,1=dead,2=healthy,3=healthy`.

Artifact:

`work/sglang-static-equivalence/artifacts-ft-mooncake-main/static-ft-1d85efdad-mooncake-1c2bbb50-r1-20260731`

This failure occurs before post-fault generation, so it is a Mooncake-main
integration/control-path incompatibility, not evidence of a precision mismatch.
The successful FT precision conclusion above remains scoped to Mooncake
`d7fcbff4`; the newly rebased Mooncake cannot yet replace that runtime in this
case.

## Broader pre-rebase PASS regression campaign

The remaining historical PASS contracts were run against rebased SGLang
`1d85efdad2659ed8fbc19166bf728e8b289ba631` while retaining the old immutable
Mooncake runtime:

```text
mooncake-transfer-engine-cuda13==0.3.11.post1
source d7fcbff4
SHA-256 96815ead6a8c2ca826f3b26da88b69d31603d56432bab0ee27bf399a77f01342
```

Except for continuous shrink, the common configuration was Qwen3-30B-A3B-FP8,
TP=4, DP=4, EP=4, 128 redundant experts, static expert dispatch,
deterministic inference, seed `468112651`, no overlap, and kernel 0.4.5.
Continuous shrink retained its historical 384 redundant experts and 0.45
memory fraction.

| Contract | Result | Material observation |
| --- | --- | --- |
| `fault-kill-noft-native-inflight` | PASS | FT disabled; in-flight DP0 completed and post-fault DP0 was exact |
| `fault-kill-continue-inflight` | PASS | In-flight and post-fault DP0 were exact |
| `fault-kill-pause-inflight-retry` | PASS | Retry completed; post-fault DP0 was exact |
| `fault-kill-pause-scale-down` | PASS | Two cold runs; DP0/DP2/DP3 exact |
| `fault-exception-continue-discard-resume` | PASS | Expected 503 discard, one completion, all schedulers healthy, post-exception exact |
| `fault-exception-pause-retry` | PASS | Pause/retry completed and precision assertions passed |
| `fault-exception-pause-scale-down` | PASS | DP0/DP1/DP3 each matched its own baseline |
| `fault-exception-pause-retry-timeout` | PASS | Pause stayed alive at 5 seconds and fail-stopped at 30 seconds |
| `fault-rejection-contracts` | PASS | Invalid apply and dead-route operations were rejected at the required stages |
| `fault-kill-pause-double-scale-down` | PASS | Two ranks removed; remaining DP0/DP3 exact |
| `fault-kill-pause-continuous-scale-down` | PASS | Three shrink rounds; DP0 exact after every round |
| `fault-kill-pause-retry` | FAIL, 2/2 | DP0/DP2 exact; DP3 repeatedly returned the historical drift sequence |
| `fault-kill-continue-status-only` | FAIL | DP0/DP2 exact; DP3 returned the same drift sequence |
| `fault-kill-continue-whole-node-rejoin` | FAIL | Rejoined scheduler appeared, but world-group join did not finish in 180 seconds |
| `fault-tpgt1-sibling-ep-retention` | INVALID | Static dispatch gave unequal DP0/DP1 baselines, so the contract stopped before fault injection |

The retry failure was reproduced in two independent cold starts. In both runs,
the kill → pause → retry control chain passed, the dead DP1 route was rejected,
and DP3 returned:

```text
[3197,498,5545,220,16,15,15,11,2936,13]
```

The continue-only contract returned the same sequence on DP3. This makes the
observation independent of the retry API: retaining DP3 after physical DP1 loss
is the common condition. By contrast, scale_down rebuilt the survivor topology
and DP3 returned the registered healthy sequence.

These results do **not** yet prove that FT introduced the DP3 drift. The existing
no-FT native in-flight contract only asserts DP0, so it is not an equivalent DP3
precision control. The minimum attribution experiment is a no-FT D4/static/
deterministic run with the same seed, physical DP1 kill, request order, and
direct post-fault DP3 request. Native parity, rather than healthy absolute
tokens alone, remains the required FT precision gate.

The whole-node rejoin failure is also separate from precision. Node3 entered
`mooncake_ep.join_group(torch.distributed.group.WORLD)` but did not complete
before the contract timeout. Its later TCPStore reset occurred only after the
contract cleaned the survivor processes.

The TP>GT1 result is not a product failure. That historical contract required
DP0 and DP1 to have equal pre-fault tokens, while static redundant-expert
dispatch gave each rank a stable but different baseline. A static-compatible
revision should compare each retained rank to its own pre-fault baseline.

Representative artifacts:

- `work/sglang-static-equivalence/artifacts-ft-2commits/rebase-1d85ef-kill-pause-retry-static-20260731`
- `work/sglang-static-equivalence/artifacts-ft-2commits/rebase-1d85ef-kill-pause-retry-static-r2-20260731`
- `work/sglang-static-equivalence/artifacts-ft-2commits/rebase-1d85ef-kill-continue-static-20260731`
- `work/sglang-static-equivalence/artifacts-ft-2commits/rebase-1d85ef-continue-whole-node-rejoin-static-20260731`
- `work/sglang-static-equivalence/artifacts-ft-2commits/rebase-1d85ef-exception-continue-discard-static-r2-20260731`
- `work/sglang-static-ft-2commits-continuous-r384/artifacts/rebase-1d85ef-continuous-scale-down-r384-static-20260731`

The exception injector needed compatibility with rebased `ModelRunner` rank
state (`ed8aff2`), and the historical continuous-shrink oracle needed its
rank0/r384 registration (`85c192e`). Both changes are test-service-only and
passed the local SGLang case unit suite.

All completed runs cleaned their owned process groups and left the selected
SGLang worktrees clean.

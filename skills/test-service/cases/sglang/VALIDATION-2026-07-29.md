# Four-GPU FT validation — 2026-07-29

## Fixed inputs

- SGLang branch: `codex/dp-only-ft-squashed`
- SGLang commit: `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`
- SGLang kernel: `0.4.2.post1` from
  `/data2/iws/deps/sglang-kernel/cu130-cp312/0.4.2.post1`
- Mooncake: `0.3.11.post1` from
  `/data2/iws/deps/mooncake/cu130-cp312/0.3.11.post1`
- Container: `sglang-ssh-v0.5.16`
- Container ID: `4f1d52e516db0a6b70a7406f19858fd2b8af21e958f732be34c269c3387a3ee9`
- Image: `server-tool/sglang-ssh:v0.5.16`
- Image digest: `sha256:fa9ce16426be4badce704ed7db71746d4a4a398ede150bf90d9e3935771c3750`
- GPUs: physical indices `4,5,6,7`
- Allocated port base: `6220`
- Model: `/data1/models/Qwen3-30B-A3B-FP8`
- Topology: TP=4, DP=4, EP=4; Mooncake TCP with CPU staging

Both contracts used their committed `TEST.md + run.sh`, a task-owned remote worktree at the
listed commit, bounded execution, exact process-group ownership checks, and fetched artifacts.
Neither result meets the `Verified` definition in [INDEX.md](INDEX.md).

## `fault-kill-continue-status-only`

Actual ordered execution:

1. Imported the selected kernel and Mooncake package from their explicit version roots.
2. Started SGLang with FT strategy `continue`.
3. Reached HTTP health 200, four healthy ranks, and four scheduler processes.
4. Killed the owned global scheduler for DP rank 1.
5. Reached `0=healthy,1=dead,2=healthy,3=healthy` and three scheduler processes.
6. Observed zero pause dispatches.
7. Routed a request to dead DP1 and received the expected HTTP 400.
8. Routed the first survivor request to DP0 and received HTTP 503 instead of HTTP 200.
9. Stopped the owned process group and verified that the source remained clean.

The failure reproduced in two independent runs:

| Run | Passed gates | Failing gate | Local artifact |
| --- | --- | --- | --- |
| `fault-kill-continue-status-only-fix2-01` | package roots; ready; initial status/processes; post-kill status/processes; no pause; DP1 HTTP 400; cleanup; clean source | `generate_dp0`: expected 200, actual 503 | `work/sglang-dp-only-ft-4gpu-regression/artifacts/fault-kill-continue-status-only-fix2-01` |
| `fault-kill-continue-status-only-repro` | same as above | `generate_dp0`: expected 200, actual 503 | `work/sglang-dp-only-ft-4gpu-regression/artifacts/fault-kill-continue-status-only-repro` |

In both logs, Mooncake marked rank 1 as a broken TCP peer and the surviving scheduler discarded
the routed request. This is a reproduced source/runtime behavior, not a passing validation.

## `fault-kill-pause-retry`

Intended ordered execution:

1. Reach four healthy ranks and four scheduler processes.
2. Kill the owned global scheduler for DP rank 1.
3. Reach `0=paused,1=dead,2=paused,3=paused`.
4. Prove paused generation returns HTTP 503.
5. Apply `retry` and require HTTP 200.
6. Reach three healthy survivors, reject DP1 with HTTP 400, and validate exact survivor tokens.

Both independent attempts stopped correctly at the first unmet gate:

| Run | Passed gates | Failing gate | Local artifact |
| --- | --- | --- | --- |
| `fault-kill-pause-retry-01` | package roots; HTTP health 200; cleanup; clean source | `status_initial`: expected all healthy, actual all paused | `work/sglang-dp-only-ft-4gpu-regression/artifacts/fault-kill-pause-retry-01` |
| `fault-kill-pause-retry-after-precompile` | package roots; HTTP health 200; cleanup; clean source | `status_initial`: expected all healthy, actual all paused | `work/sglang-dp-only-ft-4gpu-regression/artifacts/fault-kill-pause-retry-after-precompile` |

Before test fault injection, startup DeepGEMM warmup raised scheduler exceptions and the pause
strategy dispatched `pause` to ranks 0–3. The paused watchdog then performed the expected
fail-stop after 120 seconds.

The branch-provided `sglang.compile_deep_gemm` entry point was also attempted in the same
topology as task `deepgemm-precompile-dp4`. It failed while shutting down scheduler subprocesses
and did not change the second test result. Its stuck, task-owned runner was cleaned only after
matching its recorded PGID and run identity; a final check showed GPUs 4–7 at 18 MiB and port
6220 free.

# Four-GPU FT validation — 2026-07-29

## Fixed inputs

- SGLang branch under test: `codex/dp-only-ft-squashed`
- SGLang commit under test: `edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`
- Control commits: `74cafe36617c75f18b39d973486575b080360fd7` and
  `f5e32a5e39ba6649747ad22fdd28a71781fb324c`
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

All runs used server_tool-owned profiles, worktrees, scripts, status files and fetched artifacts.
The old source suite was consulted only to recover its tested environment contract; no
remote-agent executable or runtime state was used.

## Harness findings and corrections

The first validation attempts were not valid evidence against SGLang because server_tool had
omitted environment inputs used by the previously passing contract. In particular, the image
defaults `SGLANG_JIT_DEEPGEMM_PRECOMPILE=1`; startup compilation raised scheduler exceptions
before fault injection and made the pause strategy enter `paused` immediately.

An A/B run with `SGLANG_JIT_DEEPGEMM_PRECOMPILE=0` reached the intended initial healthy state,
killed DP1, paused the survivors and completed `retry`. It then received transient HTTP 503
from the dead-rank route before that route converged to HTTP 400. The historical contract used
a bounded status retry for this transition, while server_tool used a one-shot request.

The committed harness now:

- fixes the TCP, host, JIT, FT-topology and cache environment in `sg_prepare_dp4_runtime`;
- disables startup DeepGEMM precompile for this fault-injection topology;
- waits up to 30 seconds for the post-retry dead-rank route to converge to HTTP 400;
- keeps precision-sensitive survivor generation one-shot.

## `fault-kill-continue-status-only`

With the corrected environment, the current commit produced both outcomes:

| Run | Result | Decisive evidence |
| --- | --- | --- |
| `ab-continue-full-historical-env` | Failed | DP1 became dead as expected, then Mooncake raised `copyHostToCudaSync ... invalid argument`; DP3, DP2 and DP0 exited in sequence and DP0 generation timed out after 180 seconds |
| `ab-continue-full-historical-env-v2` | Passed | DP1 returned HTTP 400; DP0/2/3 returned HTTP 200 and all exact 10-token oracles matched |

Source-version controls kept the image, package roots, GPUs, port, model and script unchanged:

| Commit | Run | Result |
| --- | --- | --- |
| `74cafe366` | `control-continue-74cafe-full-env-v3` | Runner exit 0; all control, generation and exact-token gates passed |
| `f5e32a5e3` | `control-continue-f5e32-full-env` | Runner exit 0; all control, generation and exact-token gates passed |

This excludes a deterministic test-script failure and does not support a deterministic
regression at either intervening SGLang commit. The observed failure is a nondeterministic
runtime fault. Its direct crash point is Mooncake's `pg_2_11_0.so` CPU-staging-to-CUDA copy;
SGLang detects the resulting scheduler exits and marks ranks inactive. SGLang may affect the
trigger timing, but these runs do not isolate a deterministic SGLang source defect.

The scenario remains not `Verified`: the index requires two consecutive bounded cold passes
on the same source commit, and the corrected current-commit sequence contains one failure and
one pass.

## `fault-kill-pause-retry`

Two corrected-environment runs reached fault injection but failed inside the runtime before
the retry/HTTP convergence correction could decide the result:

| Run | Result | Decisive evidence |
| --- | --- | --- |
| `ab-pause-retry-full-historical-env` | Failed | pause was dispatched to DP0/2/3 but never completed within 120 seconds; survivors remained reported healthy |
| `ab-pause-retry-full-env-route-wait` | Failed | Mooncake copy failures made DP2 and DP3 runtime-inactive; only DP0 acknowledged pause, yielding `0=paused,1=dead,2=dead,3=dead` |

The second run logged the exact order: SGLang dispatched pause to `[0,2,3]`, Mooncake raised
`copyHostToCudaSync ... invalid argument`, SGLang dropped DP2 and DP3 from the pause targets,
and the pause command completed with `acked=[0]`. The script's bounded dead-route wait was
never reached. This is therefore a tested-runtime failure, not an HTTP assertion timing error.

This scenario also remains not `Verified`. A useful next isolation step is a bounded repeated
matrix over SGLang commit and Mooncake build, preserving the same image, GPUs and script, to
measure whether the CPU-staging copy failure follows Mooncake or a SGLang scheduling change.

# ft-2commits kill/scale-down exploratory validation — 2026-07-31

## Scope and fixed inputs

- SGLang worktree: `D:\Codex\repos\sglang-ft-2commits`
- Branch and commit:
  `ft-2commits@1d85efdad2659ed8fbc19166bf728e8b289ba631`
- Rebase base:
  `main@2abb1d2c37441a1b32476b5f23d9f97cf340dff9`
- Feature commits: `300f63f79` and `1d85efdad`
- Model: `/data1/models/Qwen3-30B-A3B-FP8`
- Topology: TP=4, DP=4, EP=4, redundant experts=128
- GPUs: `4,5,6,7`; port range: `6280..6289`
- SGLang kernel: `0.4.5` from
  `/data2/iws/deps/sglang-kernel/cu130-cp312/0.4.5`, required symbol
  `fp8_scaled_mm`
- Mooncake: `0.3.11.post1`, source `d7fcbff4`, with the committed wheel hash
- Artifact root:
  `work/sglang-ft-2commits-kill-scale-down/artifacts`

The stable `fault-kill-pause-scale-down` TEST.md did not yet list `ft-2commits` as an
applicable branch. This validation therefore used an ignored task-local wrapper with the
same mechanical run and gates; it does not mark the stable contract validated on this
branch.

## Environment compatibility findings

The first run,
`ft-2commits-kill-pause-scale-down-1d85efdad-20260731`, used the old
`sglang-kernel==0.4.2.post1` profile. The rebased SGLang requires at least `0.4.5`, so
startup exited before the FT scenario. The result retained nine assertions, seven passing
and two derived failures (`server_ready` and `case_result`).

The second run,
`ft-2commits-kill-pause-scale-down-kernel045-1d85efdad-20260731`, selected the existing
immutable 0.4.5 directory. The old test-service symbol gate still required
`fp8_blockwise_scaled_mm`, which 0.4.5 no longer exports at module top level. The result
retained six assertions, four passing and two derived failures.

Server_tool commit `39c7e55` parameterized the required kernel symbol without weakening
the version or import-root checks. Legacy profiles retain the old default; this main-based
profile explicitly selects `fp8_scaled_mm`. All 18 local unit tests and shell syntax checks
passed before the next remote run.

## Kill, pause, and scale-down result

Run
`ft-2commits-kill-pause-scale-down-kernel045-symbol-1d85efdad-20260731`
reached the behavioral contract and failed precision:

- dependency version, path and symbol assertions passed;
- the service reached four healthy ranks with four schedulers;
- killing DP1 converged in 38 seconds to
  `0=paused,1=dead,2=paused,3=paused`, retaining three schedulers;
- generation while paused returned HTTP 503;
- `scale_down([1])` returned HTTP 200 and reached
  `0=healthy,1=dead,2=healthy,3=healthy`;
- DP1 routing returned HTTP 400;
- DP0 returned HTTP 200 and exactly matched
  `[3197,279,1372,374,74916,553,220,18,11,3270]`;
- DP2 returned HTTP 200 but produced
  `[3197,498,5545,220,16,15,15,11,2936,13]`, failing its exact oracle;
- execution stopped at the DP2 precision gate, so DP3 post-scale-down precision was not
  evaluated;
- owned process cleanup and source-cleanliness assertions passed.

The result contains 22 assertions: 20 passed and two failed (the DP2 precision gate and
the derived `case_result`).

## Pre-fault control

Run `ft-2commits-prefault-baseline-kernel045-1d85efdad-20260731` used the same source,
model, topology, kernel and deterministic launch but injected no fault. It passed all 19
assertions. DP0 through DP3 each returned the registered sequence
`[3197,279,1372,374,74916,553,220,18,11,3270]`.

This control rules out an ordinary pre-fault rank difference and rules out
`sglang-kernel==0.4.5` alone as the direct cause of the observed DP2 drift.

## Analysis

The control plane is usable in this scenario; the failure is localized to the post-fault
data path. Logs show that rank-fault EPLB ran on DP0, DP2 and DP3. DP0 and DP2 both reported
that the model lacked `generate_weight_name_filter`, performed a full disk weight reload,
and completed rebalance. DP0 was exact afterward while DP2 drifted.

The highest-priority review area is therefore the rebased EPLB/Elastic-EP update path,
especially per-rank expert-location consistency and the association between reloaded
physical slots and the updated logical mapping in `update_expert_location_with_recovery`.
This is a localization from one cold run, not yet a proven code-level root cause.

The drift sequence matches a previously observed e63 native-parity sequence, but that older
observation came from a non-deterministic launch. This run explicitly recorded
`enable_deterministic_inference=True`, so the older explanation does not close this issue.
The team issue search returned no exact match for this token sequence plus scale-down.

All remote runs cleaned their owned process groups. Final preflight found GPU `4,5,6,7`
idle at 15 MiB and zero utilization; both the local and remote SGLang worktrees remained
clean at the selected commit.

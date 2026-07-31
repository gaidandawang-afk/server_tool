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

## Exact native control at 300f63f79

An independent worktree at
`300f63f794066da9e0b23c63247b466c69c6c82c` ran native Mooncake with FT disabled,
the same Qwen FP8 model, TP4/DP4/EP4 topology, R128, kernel 0.4.5 and Mooncake
`d7fcbff4`. Run
`ft-300f-native-noft-kill-dp1-300f63f79-20260731-r2` started a DP0 stream, killed
DP1, observed native broken-peer isolation and then checked every surviving rank.

All 21 assertions passed. DP0, DP2 and DP3 each returned
`[3197,279,1372,374,74916,553,220,18,11,3270]`. DP2 and DP3 both recorded
`cached_tokens=0`; DP0 recorded a nine-token cache hit but still returned the exact
oracle. The native recovery log had the same broad EPLB shape as the FT run: DP0 and
DP2 performed full weight reloads, DP3 did not, and all three completed rebalance.

This is the strict control that was absent from the earlier audit. It shows that the
first/native Mooncake integration commit does not reproduce the DP2 drift under this
configuration. The regression boundary is therefore the second FT commit or behavior
activated only by its FT orchestration, not `300f63f79` alone.

## Repetition

Run
`ft-2commits-kill-pause-scale-down-kernel045-symbol-1d85efdad-20260731-r2`
repeated the original FT scenario from a cold start. It reproduced the same result:
DP0 exactly matched the registered oracle and DP2 returned
`[3197,498,5545,220,16,15,15,11,2936,13]`. The DP2 prefill log again recorded
ten new tokens and zero cached tokens. This makes the failure reproducible in two
independent cold runs rather than a single-run flake.

## Historical sequence search

The drift sequence is not new and is not unique to one mechanism. Historical artifacts
contain it in at least these distinct contexts:

- native e63 Mooncake after a process kill, with `cached_tokens=0`;
- FT continue, retry, scale-down and rejoin experiments, also often with
  `cached_tokens=0`;
- same-prefix no-FT radix/KV-cache reuse, where the first request was exact and later
  requests with `cached_tokens=9` returned the drift sequence.

Consequently, token equality alone is not a root-cause signature. The current failure is
not the same-prefix cache case because both reproductions logged `cached_tokens=0`.

## Analysis

The control plane is usable in this scenario; the failure is localized to the post-fault
data path. Logs show that rank-fault EPLB ran on DP0, DP2 and DP3. DP0 and DP2 both reported
that the model lacked `generate_weight_name_filter`, performed a full disk weight reload,
and completed rebalance. DP0 was exact afterward while DP2 drifted.

The highest-priority review area is therefore the interaction between the second commit's
pause handshake and the rebased EPLB/Elastic-EP update path, especially per-rank
expert-location consistency and the association between reloaded physical slots and the
updated logical mapping in `update_expert_location_with_recovery`.

The second commit adds FT action state to the DP-attention MLP synchronization tensor and
uses it to acknowledge pause. The pause request overlaps the rank-fault recovery window,
although both reproduced logs show EPLB rebalance ending before the pause acknowledgement
and subsequent resume. It also adds an inactive-rank CPU fallback and contiguous handling
to expert-location metadata broadcast. The dedicated CPU fallback log did not appear in
either FT run, so that branch is not proven active; the normal metadata path still deserves
hash-level comparison because this area was manually conflict-resolved during rebase.

The next discriminating instrumentation should record, for DP0/DP2/DP3 immediately after
EPLB and again after FT resume:

- hashes of `physical_to_logical_map`, `logical_to_all_physical_map` and the rank-dispatch
  map;
- the missing-logical-expert set returned by `ExpertLocationUpdater.update`;
- hashes for the physical expert slots reloaded on DP0 and DP2;
- the FT action vector gathered by the MLP synchronization barrier.

This is a localization supported by a passing exact parent control and two failing child
runs, not yet a proven code-level root cause.

All remote runs cleaned their owned process groups. Final preflight found GPU `4,5,6,7`
idle at 15 MiB and zero utilization; both the local and remote SGLang worktrees remained
clean at the selected commit.

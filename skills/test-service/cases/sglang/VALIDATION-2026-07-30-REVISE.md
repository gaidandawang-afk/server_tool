# Four-GPU FT revise-branch validation — 2026-07-30

## Fixed inputs

- SGLang checkout: `D:\Codex\repos\sglang-dp-only-ft-revise`
- SGLang branch: `worktree-dp-only-ft-revise`
- SGLang commit: `7f553fee0991e90566ac9c173eae89d9b2c52609`
- Container name: `sglang-ssh-v0.5.16`
- Container ID:
  `4f1d52e516db0a6b70a7406f19858fd2b8af21e958f732be34c269c3387a3ee9`
- Image tag: `server-tool/sglang-ssh:v0.5.16`
- Image digest:
  `sha256:fa9ce16426be4badce704ed7db71746d4a4a398ede150bf90d9e3935771c3750`
- Base image: `lmsysorg/sglang:v0.5.16`
- SGLang kernel: `0.4.2.post1` from
  `/data2/iws/deps/sglang-kernel/cu130-cp312/0.4.2.post1`
- Mooncake: `0.3.11.post1`, source
  `d7fcbff4ca64bcd40567c8871b6ab3520a4a7a21`
- Mooncake wheel SHA-256:
  `96815ead6a8c2ca826f3b26da88b69d31603d56432bab0ee27bf399a77f01342`
- GPU indexes: `4,5,6,7`
- Port base: `6240`
- Artifact root:
  `work/sglang-dp-only-ft-revise-4gpu-regression/artifacts`

The selected GPUs passed the task preflight before the first launch. This branch-usability
round required one bounded cold run per previously validated contract.

## Results

| Contract | Run | Result |
| --- | --- | --- |
| `fault-kill-noft-native-inflight` | `revise-noft-native-inflight-7f553fee-20260730` | PASS |
| `fault-kill-continue-status-only` | `revise-kill-continue-7f553fee-20260730` | PASS |
| `fault-kill-pause-retry` | `revise-kill-pause-retry-7f553fee-20260730` | PASS |
| `fault-kill-pause-scale-down` | `revise-kill-pause-scale-down-deterministic-7f553fee-20260730` | PASS |
| `fault-exception-pause-retry` | `revise-exception-pause-retry-7f553fee-20260730` | PASS |
| `fault-exception-pause-scale-down` | `revise-exception-pause-scale-down-7f553fee-20260730` | PASS |
| `fault-tpgt1-sibling-ep-retention` | `revise-tpgt1-sibling-ep-retention-7f553fee-20260730` | PASS |
| `fault-kill-continue-inflight` | `revise-kill-continue-inflight-7f553fee-20260730` | PASS |
| `fault-kill-pause-inflight-retry` | `revise-kill-pause-inflight-retry-7f553fee-20260730` | PASS |
| `fault-kill-pause-double-scale-down` | `revise-kill-pause-double-scale-down-7f553fee-20260730` | PASS |
| `fault-kill-pause-continuous-scale-down` | `revise-kill-pause-continuous-scale-down-7f553fee-20260730` | PASS |
| `fault-kill-continue-whole-node-rejoin` | `revise-continue-whole-node-rejoin-r2-7f553fee-20260730` | PASS |
| `fault-kill-pause-scale-down-then-rejoin` | `revise-pause-scale-down-rejoin-r2-7f553fee-20260730` | FAIL — restored DP3 generation hangs |

Every PASS artifact records exit zero, all case assertions passing, owned process-group
cleanup and a clean SGLang source worktree.

## Invalid first precision run and targeted rerun

The first `fault-kill-pause-scale-down` run,
`revise-kill-pause-scale-down-7f553fee-20260730`, completed the intended control-plane
sequence:

- initial state was `healthy,healthy,healthy,healthy` with four schedulers;
- killing DP1 reached `paused,dead,paused,paused` with three schedulers;
- generation while paused returned HTTP 503;
- `scale_down([1])` returned HTTP 200;
- the final state was `healthy,dead,healthy,healthy`, retaining three schedulers;
- the dead DP1 route returned HTTP 400;
- DP0 returned HTTP 200 and matched its registered exact-token oracle;
- DP2 returned HTTP 200 with
  `[3197,498,5545,220,16,15,15,11,2936,13]`, matching the known e63 native drift
  sequence instead of the default oracle;
- cleanup and clean-source assertions passed.

That launch recorded `enable_deterministic_inference=False`. The remote-agent precision
contract treats deterministic inference as a suite invariant, so the first run is invalid
for golden precision comparison. Its control-plane evidence remains valid, and its output
can be reported as e63 native parity, but it is neither an absolute precision PASS nor
evidence of a revise-branch regression.

Server_tool commit `ec10c53` restored `--enable-deterministic-inference` to the shared FT
launcher. Per user direction, only the drifting contract was rerun. The targeted rerun
recorded `enable_deterministic_inference=True`, repeated the complete control-plane contract,
and returned the default exact sequence
`[3197,279,1372,374,74916,553,220,18,11,3270]` on DP0, DP2 and DP3. It exited zero with all
assertions passing, owned cleanup and a clean source worktree.

The original revise-branch regression result is therefore eleven of eleven contracts
validated once. The first invalid run remains retained rather than overwritten.

## Whole-node rejoin validation

### Continue strategy: PASS

`revise-continue-whole-node-rejoin-r2-7f553fee-20260730` exited zero with 44 passing
assertions. The run:

- started four independently owned one-GPU nodes and reached four healthy ranks;
- killed the complete node3 process group;
- retained three schedulers and HTTP 200 generation on DP0, DP1 and DP2;
- started a replacement node3 process with `--elastic-ep-rejoin`;
- observed Mooncake world join and `recover ranks [3] done` on every survivor;
- returned to `0=healthy,1=healthy,2=healthy,3=healthy`;
- returned HTTP 200 and the registered exact token sequence on DP0 through DP3;
- cleaned all four owned process groups and left the source worktree clean.

The preceding run `revise-continue-whole-node-rejoin-7f553fee-20260730` is retained as an
invalid test-contract failure: its control-plane and request gates passed, but server_tool
had no DP1 oracle and had made degraded-state precision stricter than the reference
contract. Commits `c5e87e8` and `7c61550` contain the reusable case and corrected gates.

### Pause, scale-down, inactive recover, then rejoin: data-plane FAIL

The first run, `revise-pause-scale-down-rejoin-7f553fee-20260730`, was an invalid
test-script failure. Revise logs no longer include the old `active_mask` field in the
recover-plan line and use `FT command dispatch: command=resume`; commit `61b6046` aligned
the semantic assertions. All behavior before that assertion had passed.

The corrected run `revise-pause-scale-down-rejoin-r2-7f553fee-20260730` reached the
restored topology but failed the required data-plane gate:

- whole-node kill reached `0=paused,1=paused,2=paused,3=dead`;
- generation while paused returned HTTP 503;
- `scale_down([3])` returned HTTP 200 and restored the three survivors;
- DP3 routing returned HTTP 400 while inactive, and DP0 returned the registered exact
  sequence;
- inactive `recover([3])` returned HTTP 200, left DP3 dead and closed, used
  `resume_targets=[]`, and did not add a second resume command (`1` before, `1` after);
- replacement node3 joined every Mooncake group, all three survivors logged
  `recover ranks [3] done`, status became four healthy, and node3 `/health_generate`
  returned HTTP 200;
- the subsequent DP3 `/generate` entered prefill at `06:35:07` but timed out after
  180 seconds with no HTTP response.

This final failure is not caused by the server_tool oracle or an over-tightened gate. Node0
reported `Invalid fallback dispatch token counts: [0, -1, -1, -1], limit=128`, dispatched
pause to all four ranks, and later marked node3 runtime-inactive when the watchdog lease
expired. Node3 retained one request with seven generated tokens and hit its 120-second
scheduler watchdog. The artifact contains 43 assertions; the only behavioral failure is
`recovered_dp3` (the second failed assertion is the derived `case_result`).

The historical reference case passed twice on SGLang `74cafe366` and also routes the
post-rejoin DP3 request through the base-port HTTP server, matching this server_tool case.
The team StackOverflow issue search returned no match for
`Invalid fallback dispatch token counts` plus rejoin. At this stage it was recorded as an
unresolved data-plane implementation failure, not as a usable case PASS. The exact-commit
control below shows that it is not unique to the revise commit under the current launch
conditions.

## Exact-commit control at `74cafe366`

To test whether switching only the SGLang source commit restores the current contract,
server_tool created an independent task for
`codex/debug/sglang-dp-only-ft-4gpu-regression-74cafe-control@74cafe36617c75f18b39d973486575b080360fd7`.
It retained the current comparison environment:

- container `sglang-ssh-v0.5.16`;
- `sglang-kernel==0.4.2.post1`;
- Mooncake `0.3.11.post1` from source `d7fcbff4`;
- static EP dispatch, deterministic inference and a ten-token routed request.

The first run, `baseline-74cafe-pause-scale-down-rejoin-20260730`, is retained as an
invalid test-script failure. The older SGLang log schema includes `active_mask` and an FT
command ID. Server_tool commit `5503470` made the semantic assertions accept both schemas
while still requiring an empty inactive-recover resume target and an unchanged real resume
count.

The corrected run,
`baseline-74cafe-pause-scale-down-rejoin-r2-20260730`, produced the same behavioral failure
as the revise commit:

- every control-plane gate passed, including inactive recover with resume count `1 -> 1`;
- replacement node3 joined and all survivors completed `recover ranks [3] done`;
- status reached four healthy and node3 health returned HTTP 200;
- the routed DP3 request entered prefill, but returned no HTTP response within 180 seconds;
- node0 logged `Invalid fallback dispatch token counts: [0, -1, -1, -1], limit=128`;
- node3 hit the 120-second scheduler watchdog.

The artifact contains 43 assertions; `recovered_dp3` is the only direct behavioral failure,
with `case_result` failing as its aggregate consequence. Therefore changing only SGLang from
`7f553fee` to `74cafe366` does not restore the current contract.

This does not invalidate the two historical PASS artifacts at `74cafe366`. Their recorded
launch uses dynamic EP dispatch, non-deterministic inference, a different prompt and four
generated tokens. The current server_tool contract uses static EP dispatch, deterministic
inference and ten generated tokens. The historical records do not identify the
`sglang-kernel` package version or container image, so they are not an exact environment
control. A historical-condition reproduction must vary those inputs explicitly and must not
be reported as a source-commit-only comparison.

## Intermittent-failure reclassification

Later bounded reruns showed that the static, deterministic, ten-token contract is usable on
the exact `74cafe36617c75f18b39d973486575b080360fd7` source and current environment:

- `reproduce-74cafe-static-det-max10-r1-20260730`: PASS;
- `reproduce-74cafe-static-det-max10-r2-20260730`: PASS;
- `replay-74cafe-failure-seed-468112651-20260730`: PASS with the original failing
  rank-0 random seed.

These runs used container image `server-tool/sglang-ssh:v0.5.16` with digest
`sha256:fa9ce16426be4badce704ed7db71746d4a4a398ede150bf90d9e3935771c3750`,
`sglang-kernel==0.4.2.post1`, and Mooncake `0.3.11.post1` from `d7fcbff4`. The case is
therefore marked `Validated once` for this usability round. The earlier
`baseline-74cafe-pause-scale-down-rejoin-r2-20260730` artifact remains a valid intermittent
failure observation rather than a stable FAIL classification.

The failure is below the HTTP/control-plane layer: the failed run gathered fallback token
counts `[0, -1, -1, -1]`, where `-1` matches top-k padding from the preceding collective,
and the replacement later hit its scheduler watchdog. Fixed-seed replay and repeated
token-length controls did not reproduce it.

Mooncake isolation tests on diagnostic source `d38160187d384e8bc0a761715dc53ab4e9ad9e8c`
and wheel SHA-256
`11be2c62a394c74409f3f1015cab46254fc52761120b093b0bc1ec012d22fd9c` found:

- the committed CUDA PG recovery test passed;
- 25,000 post-recovery fallback-dispatch iterations, approximately 75,000 collectives,
  passed with identical final task counts on all ranks;
- a two-second stagger between rank-0 recovery publication and ranks 1/2 activation also
  passed.

SGLang main PR `#30164` (`77d23a796e94c37f8657bc261856db725fa35891`) adds an
expanded-WORLD readiness barrier before the first forward after runtime scale-up. This is a
relevant synchronization precedent because scale-up reuses the recovery machinery, but the
staggered PG test did not confirm a missing recovery barrier as the cause. Root cause remains
unresolved.

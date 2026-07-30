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
| `fault-kill-pause-scale-down` | `revise-kill-pause-scale-down-7f553fee-20260730` | FAIL — DP2 exact-token mismatch |
| `fault-exception-pause-retry` | `revise-exception-pause-retry-7f553fee-20260730` | PASS |
| `fault-exception-pause-scale-down` | `revise-exception-pause-scale-down-7f553fee-20260730` | PASS |
| `fault-tpgt1-sibling-ep-retention` | `revise-tpgt1-sibling-ep-retention-7f553fee-20260730` | PASS |
| `fault-kill-continue-inflight` | `revise-kill-continue-inflight-7f553fee-20260730` | PASS |
| `fault-kill-pause-inflight-retry` | `revise-kill-pause-inflight-retry-7f553fee-20260730` | PASS |
| `fault-kill-pause-double-scale-down` | `revise-kill-pause-double-scale-down-7f553fee-20260730` | PASS |
| `fault-kill-pause-continuous-scale-down` | `revise-kill-pause-continuous-scale-down-7f553fee-20260730` | PASS |

Every PASS artifact records exit zero, all case assertions passing, owned process-group
cleanup and a clean SGLang source worktree.

## Failure phenomenon

`fault-kill-pause-scale-down` completed the intended control-plane sequence:

- initial state was `healthy,healthy,healthy,healthy` with four schedulers;
- killing DP1 reached `paused,dead,paused,paused` with three schedulers;
- generation while paused returned HTTP 503;
- `scale_down([1])` returned HTTP 200;
- the final state was `healthy,dead,healthy,healthy`, retaining three schedulers;
- the dead DP1 route returned HTTP 400;
- DP0 returned HTTP 200 and matched its registered exact-token oracle;
- DP2 returned HTTP 200, but
  `precision_qwen-fp8-d4t4e4-count10-no-overlap-rank2-r128` reported `mismatch`;
- cleanup and clean-source assertions passed.

This is not a control-plane or test-launch failure. The same contract passed on
`edfdb26091a89b05de9e1c2ac7944a8c3c1fe138`, and the revise commit passed the exception
scale-down, double kill/scale-down and continuous scale-down contracts in this round.
The retained artifact does not contain the DP2 response body or actual token list, so the
root cause is not established. Record this as a revise-branch post-kill DP2 precision
symptom, not as a confirmed SGLang defect.

A targeted search of the team StackOverflow issue pool for SGLang scale-down, DP2 precision,
dynamic EPLB and FP8 found no matching issue. Per the one-run usability rule, the failed case
was not rerun in this round.

# Kill, pause, scale down, and rejoin a whole logical node

Validate whole-node rejoin on the selected SGLang branch with the kernel and Mooncake roots
selected by the task profile. One cold pass is sufficient for the current case-usability
round.

```powershell
python skills\test-service\scripts\run-case.py `
  --profile profiles\<profile>.local.env `
  --case sglang/fault-kill-pause-scale-down-then-rejoin `
  --name fault-kill-pause-scale-down-then-rejoin
```

## Topology

- Model: `Qwen3-30B-A3B-FP8`
- Four independent one-GPU SGLang nodes, one owned process group per node
- TP=4, DP=4, EP=4 with static expert placement
- API ports: `PORT_BASE` through `PORT_BASE+3`
- Distributed initialization port: `PORT_BASE+4`
- Mooncake TCP with CPU staging fallback
- Deterministic inference, overlap and CUDA graph disabled

The default contract uses static EP dispatch, deterministic inference and the registered
ten-token count-up request. Root-cause comparison runs may set all three explicit profile
inputs:

- `SGLANG_FT_EP_DISPATCH_ALGORITHM=dynamic|static`
- `SGLANG_FT_DETERMINISTIC_INFERENCE=0|1`
- `SGLANG_FT_REJOIN_REQUEST_STYLE=historical-count4|current-count10`
- `SGLANG_FT_REJOIN_MAX_TOKENS=1..64` to override only the request length

Every run records the effective values in `case-inputs.env` and asserts the launch log.
Changing any input requires a distinct run name and artifact; a diagnostic variant does not
replace the default contract result. A max-token override compares recovered DP3 and DP0
exactly against the post-scale-down DP0 output for the requested length.

## Ordered gates

1. Import the exact selected `sglang-kernel` version and start four healthy nodes.
2. Kill the complete process group for logical node 3.
3. Trigger fault detection and reach `0=paused,1=paused,2=paused,3=dead`.
4. Observe HTTP 503 while the healthy nodes are paused.
5. Apply `scale_down` for rank 3 and reach
   `0=healthy,1=healthy,2=healthy,3=dead`.
6. Reject explicit DP3 routing with HTTP 400; DP0 returns HTTP 200 and the registered
   deterministic token sequence.
7. Apply inactive `recover([3])`; status remains degraded, DP3 remains closed, and no
   additional resume command is issued.
8. Confirm the runtime applies recover with an empty resume target set and rank 3 still
   inactive. Accept the optional diagnostic `active_mask` field used by older applicable
   SGLang commits without weakening the semantic gate.
9. Restart only node 3 and observe world join plus recovery completion on all survivors.
10. Reach four healthy ranks; DP3 and DP0 return HTTP 200 with their registered token
    sequences.
11. Stop only the four owned process groups and leave the selected source checkout clean.

Every gate must append a structured assertion. Exit zero without assertions is not a pass.

## Required artifacts

- `container.env`, `provenance.env`, `invocation.json`
- container name and ID, image tag and digest, selected source branch and commit
- request and response JSON for every HTTP operation
- FT status JSON and one log plus owned PGID per logical node
- precision JSON for post-scale-down and post-rejoin requests
- `assertions.jsonl` and `result.json`

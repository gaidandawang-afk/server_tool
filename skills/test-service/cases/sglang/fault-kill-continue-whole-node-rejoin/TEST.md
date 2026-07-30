# Continue after whole-node loss and rejoin

Validate `worktree-dp-only-ft-revise` with four logical nodes on one four-GPU host. Kill the
complete node3 process group, retain precise service on nodes 0–2, restart node3 in rejoin
mode, and require native Mooncake recovery to restore its route and exact output.

## Applicability

- Source branch: `worktree-dp-only-ft-revise`
- TP=4, DP=4, EP=4, NNODES=4 with one profile-selected GPU per logical node
- Static EP dispatch, 128 redundant experts, deterministic inference
- API ports: `PORT_BASE..PORT_BASE+3`
- Distributed bootstrap: `PORT_BASE+4`
- Repetition: one bounded cold run for branch usability

## Ordered gates

1. Start four independently owned node process groups and reach four healthy DP ranks.
2. Kill the complete node3 process group; no node3 watchdog remains.
3. Issue one survivor forward to trigger native Mooncake failure detection.
4. Reach `0=healthy,1=healthy,2=healthy,3=dead`; keep one scheduler in each survivor group.
5. Generate successfully on DP0, DP1 and DP2 to prove degraded survivor service.
6. Restart node3 with `--elastic-ep-rejoin` and observe its Mooncake world join.
7. Keep DP3 routed closed with HTTP 400 until survivor forwards complete Mooncake recovery.
8. Reach four healthy ranks and require node3 `/health_generate`.
9. Generate on DP0..DP3 and match every registered exact oracle.
10. Stop all owned process groups and leave the source worktree clean.

## Required artifacts

- provenance, container identity, dependency imports and invocation
- four initial node logs plus the node3 rejoin log
- every request, response, status and precision JSON
- recovery-drive responses, owned PGIDs, assertions and result

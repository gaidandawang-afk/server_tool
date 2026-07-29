---
name: run-service
description: Start, observe, and clean up a service owned entirely by the current task.
---

# Run Service

Use this skill when a task must launch SGLang or another service from its selected source build.

## Rules

1. Read the profile's GPU list, port range, task root and source commit.
2. Fail before launch if selected ports or task paths conflict.
3. Set task variables such as `CUDA_VISIBLE_DEVICES` explicitly.
4. Build `PYTHONPATH` only from the selected source and explicit dependency roots; disable user-site fallback.
5. Before launch, record each selected distribution version and imported module path, and fail if either differs.
6. Start the service detached from the SSH connection and record its PID/PGID.
7. Use bounded readiness checks and save stdout, stderr and launch provenance.
8. The current task owns the complete service lifecycle.
9. Clean up only recorded and ownership-verified PID/PGID values.
10. Never reuse or restart another task's service as an implicit dependency.

Launch parameters specific to a stable test scenario belong with its committed
`skills/test-service/cases/` contract. Exploratory parameters stay in the current task-local
`run.sh` until the behavior is confirmed and promoted.

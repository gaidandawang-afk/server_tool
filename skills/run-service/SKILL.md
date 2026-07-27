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
4. Start the service detached from the SSH connection and record its PID/PGID.
5. Use bounded readiness checks and save stdout, stderr and launch provenance.
6. The current task owns the complete service lifecycle.
7. Clean up only recorded and ownership-verified PID/PGID values.
8. Never reuse or restart another task's service as an implicit dependency.

Launch parameters specific to a branch or test scenario belong with that source branch's
test contract or the current task-local `run.sh`.

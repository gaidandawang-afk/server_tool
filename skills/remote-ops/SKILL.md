---
name: remote-ops
description: Safely inspect and operate task-scoped work on the configured shared SSH server.
---

# Remote Operations

Use this skill for host inspection, task-scoped remote execution, status observation,
artifact retrieval and targeted cleanup.

## Rules

1. Read the selected flat `.local.env` profile and verify all required paths before connecting.
2. Recheck the current host, mounts, GPU state, ports, containers and task directories.
3. Confine mutable state to the profile's roots under `/data2/iws`.
4. Do not touch resources that are not explicitly owned by the current task.
5. Derive the expected source commit from the clean local branch HEAD.
6. Run long work detached from SSH and observe it through bounded short connections.
7. Record task PID/PGID values before allowing cleanup.
8. Fetch output and provenance, not the entire mutable work directory.

This skill owns operational behavior. Generic SSH/SFTP and task-state mechanics belong
in `tools/`, not in skill-specific orchestration scripts.

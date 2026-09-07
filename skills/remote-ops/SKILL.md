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

Use `tools/server_tool.py` for committed-input runs:

- `check` verifies the profile, source HEAD, connection and container manifest.
- `run` uploads a Git bundle, `TEST.md`, `run.sh` and explicit attachments, then starts
  `tools/remote_runner.sh` in a detached process group.
- `status`, `logs`, `wait` and `fetch` use bounded short connections.
- `stop` signals only the recorded process group after checking its run identity.

Never invoke another project's runner. A reference project may inform implementation, but
server_tool must transport and execute only files committed here or in the selected source repo.

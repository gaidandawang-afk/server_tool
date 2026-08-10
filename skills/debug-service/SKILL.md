---
name: debug-service
description: Diagnose a concrete failed test from its artifacts and validate a committed fix.
---

# Debug Service

Use this skill only after a specific test case has failed and produced logs or artifacts.
Do not invoke it for normal session startup, image work, environment installation or successful tests.

## Rules

1. Begin with the failed test's `TEST.md`, result, stdout, stderr and service logs.
2. Load the debug experience pool only now, using the concrete error, component and scenario.
3. Treat prior experience as a hypothesis source, never as proof for the current failure.
4. Add minimal instrumentation locally when evidence is insufficient.
5. Any source modification requires an isolated worktree and temporary debug branch.
6. Commit locally, synchronize the exact commit and rerun the original failing contract.
7. Require bounded repeat success before calling the root cause fixed.
8. Ask the user before adding or voting on experience-pool entries.
9. Do not publish findings externally without explicit user approval.

## Experience pool

This skill exclusively owns the repository-local experience pool and its manager:

- Pool: `skills/debug-service/pool.json`
- Manager: `python skills/debug-service/scripts/manage_pool.py`

Do not read or update a pool in `remote-agent` or any other repository. Run the manager from
the `server_tool` repository root. Useful commands are:

```text
python skills/debug-service/scripts/manage_pool.py list --top 10
python skills/debug-service/scripts/manage_pool.py add --category <category> --title <title> --content <content>
python skills/debug-service/scripts/manage_pool.py vote <id> +1 --reason <reason>
python skills/debug-service/scripts/manage_pool.py summary
```

Pool changes are tracked repository changes and must be committed before the task ends.

Do not create permanent scripts for one failed attempt. Keep exploratory probes task-local
unless repeated use proves they are stable domain leaves.

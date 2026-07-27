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

Do not create permanent scripts for one failed attempt. Keep exploratory probes task-local
unless repeated use proves they are stable domain leaves.

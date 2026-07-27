---
name: build-source
description: Build an exact source branch or debug branch in an isolated task worktree.
---

# Build Source

Use this skill for Mooncake, SGLang or other source builds that belong to a specific task.

## Rules

1. Require a clean local repository and a profile naming the local and remote branches.
2. Derive the expected commit from local HEAD; do not hardcode commit hashes in scripts.
3. Use a task-specific remote worktree under the profile's `REMOTE_PROJECT_ROOT`.
4. Load the shared base environment without copying or modifying it.
5. Keep build directories, logs and outputs inside the current task root.
6. Read the exact branch's build documentation before selecting commands or flags.
7. Keep branch-specific build behavior in the source repository or task-local `run.sh`.
8. Promote only repeated, stable leaf operations into this skill's `scripts/`.
9. Record the commit, build command, environment and acceptance result as output.

If source changes or instrumentation are required, create an isolated local worktree and
temporary debug branch, commit locally, then synchronize the same commit remotely.

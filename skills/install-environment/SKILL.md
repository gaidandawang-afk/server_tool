---
name: install-environment
description: Install and validate the shared base runtime environment used by all tasks.
---

# Install Environment

Use this skill when the shared Python, CUDA-facing dependencies, stable Mooncake installation
or common caches need to be installed for the first time.

## Rules

1. Inspect the container, driver, CUDA, Python, disk and existing environment before writing.
2. Install only shared, task-independent dependencies under `/data2/iws`.
3. Reuse one environment across tasks; do not create environment IDs, version pointers or repair flows.
4. Do not place tested source code, task-specific builds, ports, GPU choices or service state in the shared environment.
5. Use isolated virtual environments where applicable; do not mutate system or user packages implicitly.
6. Record exact package versions, commands and acceptance output.
7. If an installed environment is inconsistent, stop and report it rather than inventing an automatic repair.

Mooncake is part of the shared environment only when it is an installed stable dependency.
A Mooncake branch being developed or tested belongs to `build-source`.

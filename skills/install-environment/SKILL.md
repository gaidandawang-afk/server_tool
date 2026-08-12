---
name: install-environment
description: Install and validate shared runtime dependencies, including immutable parallel versions of ABI-sensitive Python packages selected by task profiles.
---

# Install Environment

Use this skill when the shared Python, CUDA-facing dependencies, stable Mooncake installation
or common caches need to be installed for the first time.

## Rules

1. Inspect the container, driver, CUDA, Python, disk and existing environment before writing.
2. Install only shared, task-independent dependencies under `/data2/iws`.
3. Reuse stable roots across tasks; do not create environment IDs, mutable version pointers or repair flows.
4. Do not place tested source code, task-specific builds, ports, GPU choices or service state in the shared environment.
5. Use isolated virtual environments where applicable; do not mutate system or user packages implicitly.
6. Record exact package versions, commands and acceptance output.
7. If an installed environment is inconsistent, stop and report it rather than inventing an automatic repair.

## Parallel package versions

Install ABI-sensitive versions that must coexist under distinct immutable paths such as
`/data2/iws/deps/sglang-kernel/cu130-cp312/<version>`. Select one exact root in the task
profile. Never overwrite a populated version root or switch a global `current` link.

Use `scripts/install-python-package-version.sh` for a new version root. After installation,
validate the distribution version, imported module path and branch-required symbols.

Mooncake is part of the shared environment only when it is an installed stable dependency.
A Mooncake branch being developed or tested belongs to a task. Use
`build-mooncake-wheel` when that task needs an isolated CUDA EP/PG development wheel.

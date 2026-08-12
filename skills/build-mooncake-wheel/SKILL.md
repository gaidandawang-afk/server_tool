---
name: build-mooncake-wheel
description: Build and verify an isolated CUDA 13 Mooncake development wheel with EP/PG enabled in a server_tool task. Use for exact Mooncake source or debug branches that must coexist with other Mooncake wheels and be consumed from an explicit task-local path. Do not use for PyPI/community release artifacts or shared Mooncake installation.
---

# Build Mooncake Wheel

Build a development wheel without modifying shared Python packages, existing wheels, or
version pointers. Treat the result as valid for the selected container and ABI only.

## Preconditions

1. Use `remote-ops` for the surrounding task lifecycle.
2. Require a clean local Mooncake branch and an isolated profile/worktree.
3. Read the exact branch's build documentation and confirm the r2-style CUDA 13 EP/PG
   build still matches its CMake layout.
4. Select explicit read-only dependency source and prefix directories. Never read
   dependencies from an unrecorded historical task.
5. Start a fresh run. Do not reuse its `work/source`, `work/cmake`, `work/package`,
   `output/wheels`, or `output/verify-target` directories.

## Build

Attach `scripts/` to the run and invoke `build-task-wheel.sh` from a task-local `run.sh`:

```bash
"$SERVER_TOOL_INPUT_ROOT/mooncake-build/build-task-wheel.sh" \
  --dependency-source "$dependency_source" \
  --dependency-prefix "$dependency_prefix" \
  --cuda-arch 9.0 \
  --jobs 4
```

Launch through `tools/server_tool.py run` with:

```text
--attach skills/build-mooncake-wheel/scripts:mooncake-build
```

The script derives the source commit from `SERVER_TOOL_PROJECT_ROOT`, archives it into the
run-local work directory, builds CUDA EP/PG, assembles the wheel explicitly, installs it
with `pip --target`, and records the exact wheel path, SHA-256, build environment, dynamic
dependencies, import path, API acceptance, and source status.

## Acceptance

Require all of the following before binding the wheel into another profile:

- script exit code is zero;
- `output/build-acceptance.env` records `status=pass` and `exit_code=0`;
- `output/transport-build-config.txt` records both
  `ENABLE_MULTI_PROTOCOL:BOOL=ON` and `USE_INTRA_NVLINK:BOOL=ON`;
- `output/wheel.sha256` matches the selected wheel;
- `output/verify-target/mooncake` is the imported package root;
- `mooncake.ep.Buffer` and PG join/recover/state APIs exist;
- no ELF dependency is reported as `not found`;
- `output/source-status.txt` is empty;
- the downstream profile uses exact `MOONCAKE_ROOT`, `MOONCAKE_WHEEL`, version, source
  commit, and SHA-256 values rather than a shared install or pointer.

## Boundaries

- Never run `pip install` without `--target` and `--no-deps`.
- Never upgrade pip, setuptools, wheel, build, auditwheel, or shared dependencies.
- Never overwrite an existing task wheel or verification directory.
- Never create `current` or `latest` links.
- Do not claim distributable/community-wheel portability: this development path does not
  run `auditwheel repair`. Use a separately isolated release workflow when portability is
  the acceptance target.
- Keep SGLang launch, PG/EP behavioral tests, and no-HCA diagnosis outside this skill.

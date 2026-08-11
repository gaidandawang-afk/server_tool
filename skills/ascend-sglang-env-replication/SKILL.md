---
name: ascend-sglang-env-replication
description: Recreate an Ascend (NPU) SGLang container environment on a new server, referencing the historical successful flow instead of rediscovering it.
---

# Ascend SGLang Environment Replication

Use this skill when a task asks to build, launch, or verify an **Ascend / NPU** SGLang
container runtime on a machine, or to reproduce an environment that already works on
another host (for example "build the same environment on <host>").

This is a reference-driven workflow. It exists because the steps, paths, driver, and
pitfalls required to stand up an Ascend container are environment-specific and are
**not derivable from first principles** — they were established once by trial and are now
the record of truth.

## Required reading

Before doing anything, read `references/history-2026-08-11-148-to-145.md`. It is a
timeline of the exact successful flow used to replicate the Ascend SGLang SSH
environment from the reference host onto a second host, with every negative event
inlined at the step where it originally bit.

## Rules

1. Treat the timeline in `references/` as the source of truth for the surviving
   approach and the known pitfalls. Do not re-derive them from first principles.
2. The reference host environment changes over time. Always re-check the actual remote
   state (paths, containers, NPUs, sshd) at the start of work rather than trusting the
   timeline's snapshots as current.
3. An Ascend container is NOT a normal CUDA container. It needs `--privileged=true`
   plus NPU-specific mounts (`/usr/local/Ascend/driver`, `dcmi`, `npu-smi`, `/dev`).
   Do not fall back to `--gpus` / `nvidia-smi` assumptions from `manage-image`.
4. Confirm NPU visibility by calling `torch_npu.npu.device_count()` inside the container
   (or `npu-smi info`), not by assuming the host driver version dictates visibility.
5. Network/proxy reachability must be tested with a real fetch (git, pip, or python
   urllib), never judged from a bare `curl` CONNECT tunnel returning `000` — that alone
   does not mean the proxy is down.
6. Persist replicated data under the same root layout as the reference
   (`/data2` on the new host may need to be created, e.g. as a symlink to `/data`).
7. Record the final container name, image, ssh port, and verified NPU count as the new
   environment's provenance.

## Output

- A launched and verified Ascend SGLang SSH container with NPUs visible over ssh.
- The updated environment facts that should feed back into `references/` so future
  replication rides on this record rather than re-discovering the same pitfalls.

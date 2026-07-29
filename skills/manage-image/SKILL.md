---
name: manage-image
description: Build, deploy, inspect, and verify the SGLang SSH runtime images used by this server.
---

# Manage Image

Use this skill only when the user asks to create, update, deploy or inspect a runtime image.
Ordinary Mooncake builds and SGLang tests use an existing container and do not invoke it.

## Required reading

Read `references/sglang-ssh.md` before changing or deploying the SGLang SSH image.

## Rules

1. Inspect image tags, target container names, ports, data mounts and current users first.
2. Never overwrite an existing container or occupied port implicitly.
3. Store image archives only in `/data1/images`.
4. Keep personal persistent data under `/data2/iws`.
5. Use public-key SSH authentication; never bake passwords or private keys into images.
6. Preserve NVIDIA initialization and verify GPU visibility from an external SSH client.
7. Treat `assets/` as image source and `scripts/` as stable, parameterized lifecycle leaves.
8. Commit image source changes before synchronizing or building them remotely.
9. Deployment must write a readable container manifest containing only container name/ID,
   image tag/digest and base image for later test provenance.

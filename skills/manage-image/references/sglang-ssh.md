# SGLang SSH image

The image is a thin derivative of an explicit `lmsysorg/sglang:<version>` base.
It adds key-only root SSH access while preserving the NVIDIA entrypoint.

## Persistent paths

- Image archives: `/data1/images`
- Personal root: `/data2/iws`
- Authorized keys: `/data2/iws/ssh/authorized_keys`
- SSH host keys: `/data2/iws/ssh/host-keys`
- Workspace: `/data2/iws/workspace`
- Caches: `/data2/iws/cache`

## Build

Pass every requested version explicitly:

```bash
skills/manage-image/scripts/build.sh v0.5.13.post1 v0.5.16
```

The base images must already exist in Docker. If direct pulling fails, use a user-approved
registry mirror and write any `docker-archive` output under `/data1/images`.

## Deploy

Pass the exact image and container name. Resource values come from the selected profile:

```bash
SSH_PORT=6200 \
PERSIST_ROOT=/data2/iws \
GPU_IDS=all \
skills/manage-image/scripts/deploy.sh \
  server-tool/sglang-ssh:v0.5.16 \
  sglang-ssh-v0.5.16
```

Verify container status, SSH authentication policy, host-key fingerprint, SGLang version,
GPU visibility, `CUDA_VISIBLE_DEVICES`, `/data1`, `/data2` and `/workspace`.

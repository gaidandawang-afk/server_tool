# SGLang SSH images

This repository builds SSH-enabled variants of official SGLang images and runs
one isolated development container on a shared GPU server.

## Images

The build script creates both images without changing the upstream images:

- `server-tool/sglang-ssh:v0.5.13.post1`
- `server-tool/sglang-ssh:v0.5.16`

```bash
./scripts/build-images.sh
```

## Runtime

The runtime uses root public-key authentication only. Before starting it, place
the generated public key in:

```text
/data2/iws/ssh/authorized_keys
```

Start the latest image:

```bash
SSH_PORT=6200 \
CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 \
./scripts/run-latest.sh
```

The container mounts `/data1` and `/data2` at the same paths and uses
`/data2/iws` for its workspace, caches, SSH host keys, and other persistent
state.

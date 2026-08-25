# Build guide: sgl-kernel-npu on Ascend

Verified command chain for compiling the SGLang NPU kernels inside an Ascend container.
Follow this from a task-local remote worktree; record every command and the resulting
wheels. All compilation goes through the fixed proxy `http://80.253.24.60:8080`.

## Prerequisites inside the container

- An Ascend environment with `ASCEND_TOOLKIT` pointing at the toolkit, whose
  `set_env.sh` sets up `ascend_acl`, compilers and the runtime libraries.
- Network access to the proxy `http://80.253.24.60:8080` for git, pip and submodule
  fetches.
- The repository already checked out at the exact commit derived from local `HEAD`.
  Prefer a task worktree under the profile's `REMOTE_PROJECT_ROOT`.

## Build steps

```bash
# 1. Route all compilation through the fixed proxy.
export http_proxy=http://80.253.24.60:8080
export https_proxy=http://80.253.24.60:8080

# 2. Initialize submodules before anything else.
git submodule update --init --recursive

# 3. Load the Ascend build environment.
#    $ASCEND_TOOLKIT must point at the Ascend toolkit root containing set_env.sh.
source "$ASCEND_TOOLKIT/set_env.sh"

# 4. Build. SOC is the target: Ascend910 or a3.
bash build.sh a3
```

## Outputs

The build writes the four wheels under `output/` in the repository root:

- `sgl_kernel_npu-*.whl`
- `deep_ep-*.whl`
- `attentions-*.whl`
- `torch_memory_saver-*.whl`

Collect only `output/` wheels into the task's output directory and write a `sha256`
manifest next to them. The NPU `MoeDistributeDispatchV2` custom operator is registered
from the `deep_ep` wheel's compiled `deep_ep_cpp*.so`, so a change to that operator's
call chain primarily rebuilds `deep_ep`.

## Install a version root

Install a chosen subset of the four wheels into a fresh immutable root, mirroring
`install-environment`'s `install-python-package-version.sh` staging/immutable/atomic
pattern but for multiple wheels at once:

```bash
skills/build-sgl-kernel-npu/scripts/build.sh "$SOURCE_ROOT" "$OUTPUT_DIR" a3

skills/build-sgl-kernel-npu/scripts/install-wheels.sh \
  /data2/iws/deps/sgl-kernel-npu/a3-cp311/0.0.1 \
  "$OUTPUT_DIR/sgl_kernel_npu-0.0.1*.whl" \
  "$OUTPUT_DIR/deep_ep-0.0.1*.whl"
```

`install-wheels.sh` refuses overwrite of an existing root, forbids `/current` and
`/latest`, makes the root immutable (`chmod -R a-w`) and writes a multi-wheel SHA256
`server-tool-install.txt`.

**Prefix constraint / data-root adapter.** `install-wheels.sh` hard-checks the target
version-root against the literal prefix `/data2/iws/deps/sgl-kernel-npu/*`. When a
host's authoritative data root is not `/data2` (e.g. an Ascend node whose tooling
uses `/new_data/iws`, with the container mounting `/new_data` at `/data2`), run the
installer **inside the container** so `/data2/iws/deps/...` resolves to the host's
real root; the resulting root still lives under the host data root. Do not
silently bypass the overwrite-refusal or immutability checks. Also check the shipped
script for CRLF line endings on a Windows git checkout (bash rejects
`set -Eeuo pipefail\r`); convert CRLF→LF before running if needed.

## Runtime selection

There is no environment variable for kernel selection and no sglang source change.
SGLang loads `sgl_kernel_npu`, `deep_ep` and `attentions` by ordinary Python import, so
selecting a build is purely a `PYTHONPATH` ordering concern:

```bash
export PYTHONNOUSERSITE=1
export PYTHONPATH="$SERVER_TOOL_PROJECT_ROOT/python:/data2/iws/deps/sgl-kernel-npu/a3-cp311/<version>:$PYTHONPATH"
```

Verify the import actually comes from the selected root before trusting it:

```bash
python -c "import sgl_kernel_npu, deep_ep; print(sgl_kernel_npu.__file__); print(deep_ep.__file__)"
```

The optional top-level symbol check (`SGLANG_KERNEL_NPU_REQUIRED_SYMBOL`) uses the
`sgl_kernel_npu` import namespace as the authoritative surface. Keep it empty unless the
symbol is a real top-level attribute of `sgl_kernel_npu`: `MoeDistributeDispatchV2` is
registered as a torch_npu custom op (`torch_npu.npu_moe_distribute_dispatch_v2`) by the
`deep_ep` wheel (`deep_ep/strategies/low_latency_strategy.py`), so it is NOT a top-level
`hasattr` target and should not be set here. Module import + version + path are the
authoritative validation.

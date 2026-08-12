#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
usage: build-task-wheel.sh \
  --dependency-source DIR \
  --dependency-prefix DIR \
  --cuda-arch ARCH \
  [--cuda-root DIR] [--python-bin FILE] [--jobs N]

Build an isolated CUDA 13 Mooncake EP/PG development wheel inside a server_tool run.
EOF
}

dependency_source=""
dependency_prefix=""
cuda_arch=""
cuda_root="/usr/local/cuda"
python_bin="/usr/bin/python3"
jobs="4"

while (($#)); do
  case "$1" in
    --dependency-source)
      dependency_source="${2:?missing value for --dependency-source}"
      shift 2
      ;;
    --dependency-prefix)
      dependency_prefix="${2:?missing value for --dependency-prefix}"
      shift 2
      ;;
    --cuda-arch)
      cuda_arch="${2:?missing value for --cuda-arch}"
      shift 2
      ;;
    --cuda-root)
      cuda_root="${2:?missing value for --cuda-root}"
      shift 2
      ;;
    --python-bin)
      python_bin="${2:?missing value for --python-bin}"
      shift 2
      ;;
    --jobs)
      jobs="${2:?missing value for --jobs}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

: "${SERVER_TOOL_PROJECT_ROOT:?SERVER_TOOL_PROJECT_ROOT is required}"
: "${SERVER_TOOL_WORK_ROOT:?SERVER_TOOL_WORK_ROOT is required}"
: "${SERVER_TOOL_OUTPUT_ROOT:?SERVER_TOOL_OUTPUT_ROOT is required}"
: "${dependency_source:?--dependency-source is required}"
: "${dependency_prefix:?--dependency-prefix is required}"
: "${cuda_arch:?--cuda-arch is required}"

case "$jobs" in
  ''|*[!0-9]*) echo "--jobs must be a positive integer" >&2; exit 2 ;;
esac
((jobs > 0)) || { echo "--jobs must be a positive integer" >&2; exit 2; }

readonly project_root="$(realpath "$SERVER_TOOL_PROJECT_ROOT")"
readonly work_root="$(realpath "$SERVER_TOOL_WORK_ROOT")"
readonly output_root="$(realpath "$SERVER_TOOL_OUTPUT_ROOT")"
readonly dependency_source_root="$(realpath "$dependency_source")"
readonly dependency_prefix_root="$(realpath "$dependency_prefix")"
readonly cuda_root_abs="$(realpath "$cuda_root")"
readonly python_bin_abs="$(realpath "$python_bin")"

readonly source_root="$work_root/source"
readonly build_root="$work_root/cmake"
readonly package_root="$work_root/package"
readonly wheel_root="$output_root/wheels"
readonly verify_root="$output_root/verify-target"
readonly acceptance_file="$output_root/build-acceptance.env"

for fresh_path in \
  "$source_root" "$build_root" "$package_root" "$wheel_root" "$verify_root" \
  "$acceptance_file"; do
  if [[ -e "$fresh_path" ]]; then
    echo "refusing to overwrite existing path: $fresh_path" >&2
    exit 3
  fi
done

record_acceptance() {
  local exit_code="$?"
  trap - EXIT
  if ((exit_code == 0)); then
    printf 'status=pass\nexit_code=0\n' >"$acceptance_file"
  else
    printf 'status=fail\nexit_code=%s\n' "$exit_code" >"$acceptance_file"
  fi
  exit "$exit_code"
}
trap record_acceptance EXIT

test "$(git -C "$project_root" rev-parse --is-inside-work-tree)" = "true"
test -z "$(git -C "$project_root" status --porcelain)"
test -d "$dependency_source_root/pybind11"
test -d "$dependency_source_root/yalantinglibs"
test -d "$dependency_prefix_root/include"
test -d "$dependency_prefix_root/lib"
test -x "$python_bin_abs"
test -x "$cuda_root_abs/bin/nvcc"
"$python_bin_abs" -c 'import build, setuptools, torch, wheel'

readonly cuda_release="$($cuda_root_abs/bin/nvcc --version | sed -n 's/.*release \([0-9][0-9]*\)\..*/\1/p' | tail -1)"
if [[ "$cuda_release" != "13" ]]; then
  echo "CUDA 13 is required, found major version: ${cuda_release:-unknown}" >&2
  exit 4
fi

readonly source_commit="$(git -C "$project_root" rev-parse HEAD)"
readonly torch_prefix="$($python_bin_abs -c 'import torch.utils; print(torch.utils.cmake_prefix_path)')"
readonly torch_lib_dir="$($python_bin_abs -c 'import pathlib, torch; print(pathlib.Path(torch.__file__).parent / "lib")')"

mkdir -p "$source_root/extern" "$build_root" "$package_root" "$wheel_root"
git -C "$project_root" archive --format=tar "$source_commit" | tar -xf - -C "$source_root"
cp -a "$dependency_source_root/pybind11" "$source_root/extern/"
cp -a "$dependency_source_root/yalantinglibs" "$source_root/extern/"

export PATH="$cuda_root_abs/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export CUDA_HOME="$cuda_root_abs"
export CUDA_PATH="$cuda_root_abs"
export CUDAHOSTCXX=/usr/bin/g++
export CC=/usr/bin/gcc
export CXX=/usr/bin/g++
export TORCH_CUDA_ARCH_LIST="$cuda_arch"
export C_INCLUDE_PATH="$dependency_prefix_root/include:$cuda_root_abs/include"
export CPLUS_INCLUDE_PATH="$C_INCLUDE_PATH"
export LD_LIBRARY_PATH="$torch_lib_dir:$dependency_prefix_root/lib:$cuda_root_abs/lib64:/usr/local/lib:/usr/lib/x86_64-linux-gnu"
export LIBRARY_PATH="$torch_lib_dir:$dependency_prefix_root/lib:$cuda_root_abs/lib64:/usr/local/lib:/usr/lib/x86_64-linux-gnu"

cmake_args=(
  -S "$source_root"
  -B "$build_root"
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_C_COMPILER=/usr/bin/gcc
  -DCMAKE_CXX_COMPILER=/usr/bin/g++
  "-DCMAKE_PREFIX_PATH=$dependency_prefix_root;$torch_prefix;/usr/local;/usr;$cuda_root_abs"
  "-DCMAKE_LIBRARY_PATH=$torch_lib_dir;$dependency_prefix_root/lib;/usr/local/lib;/usr/lib/x86_64-linux-gnu;$cuda_root_abs/lib64"
  "-DCMAKE_INCLUDE_PATH=$dependency_prefix_root/include;/usr/local/include;/usr/include;$cuda_root_abs/include"
  "-DCMAKE_CUDA_COMPILER=$cuda_root_abs/bin/nvcc"
  "-DCUDAToolkit_ROOT=$cuda_root_abs"
  "-DPython_EXECUTABLE=$python_bin_abs"
  "-DTORCH_CUDA_ARCH_LIST=$cuda_arch"
  -DUSE_CUDA=ON -DUSE_TCP=ON -DUSE_HTTP=ON
  -DWITH_EP=ON -DWITH_TE=ON -DWITH_STORE=OFF
  -DWITH_STORE_RUST=OFF -DWITH_STORE_GO=OFF -DWITH_P2P_STORE=OFF
  -DBUILD_UNIT_TESTS=OFF -DBUILD_BENCHMARK=OFF -DBUILD_EXAMPLES=ON
  -DUSE_ETCD=OFF -DSTORE_USE_ETCD=OFF -DSTORE_USE_REDIS=OFF
  -DSTORE_USE_K8S_LEASE=OFF -DWITH_METRICS=OFF -DUSE_UB=OFF -DUSE_EFA=OFF
)

{
  printf 'source_commit=%s\n' "$source_commit"
  printf 'python=%s\n' "$($python_bin_abs --version 2>&1)"
  printf 'torch=%s\n' "$($python_bin_abs -c 'import torch; print(torch.__version__)')"
  printf 'cuda=%s\n' "$($cuda_root_abs/bin/nvcc --version | tail -1)"
  printf 'cc=%s\n' "$(/usr/bin/gcc --version | head -1)"
  printf 'cxx=%s\n' "$(/usr/bin/g++ --version | head -1)"
  printf 'dependency_source=%s\n' "$dependency_source_root"
  printf 'dependency_prefix=%s\n' "$dependency_prefix_root"
  printf 'cuda_arch=%s\n' "$cuda_arch"
  printf 'jobs=%s\n' "$jobs"
} >"$output_root/build.env"
printf '%q ' cmake "${cmake_args[@]}" >"$output_root/cmake-command.txt"
printf '\n' >>"$output_root/cmake-command.txt"

cmake "${cmake_args[@]}"
cmake --build "$build_root" --parallel "$jobs"

cp -a "$source_root/mooncake-wheel/." "$package_root/"
cp "$source_root/README.md" "$package_root/README.md"
readonly package="$package_root/mooncake"
cp "$source_root/mooncake-integration/fabric_allocator_utils.py" "$package/"
cp "$source_root/mooncake-integration/allocator.py" "$package/"
readonly engine_built="$(find "$build_root/mooncake-integration" -maxdepth 1 -type f -name 'engine.*.so' -print -quit)"
test -n "$engine_built"
rm -- "$package/engine.so"
cp "$engine_built" "$package/engine.so"
cp "$build_root/mooncake-common/libasio.so" "$package/"
cp "$build_root/mooncake-transfer-engine/nvlink-allocator/nvlink_allocator.so" "$package/"
cp "$build_root/mooncake-transfer-engine/example/transfer_engine_bench" "$package/"
cp "$build_root/mooncake-pg/src/libmooncake_pg.so" "$package/"
cp "$build_root"/ep_pg_staging/*.so "$package/"

grep -Fqx 'name = "mooncake-transfer-engine"' "$package_root/pyproject.toml"
sed -i 's/name = "mooncake-transfer-engine"/name = "mooncake-transfer-engine-cuda13"/' "$package_root/pyproject.toml"

(cd "$package_root" && "$python_bin_abs" -m build --wheel --no-isolation --outdir "$wheel_root")
mapfile -t wheels < <(find "$wheel_root" -maxdepth 1 -type f -name '*.whl' -print)
if ((${#wheels[@]} != 1)); then
  echo "expected exactly one wheel, found ${#wheels[@]}" >&2
  exit 5
fi
readonly wheel="${wheels[0]}"

"$python_bin_abs" -m pip install --no-deps --target "$verify_root" "$wheel"
export LD_LIBRARY_PATH="$verify_root/mooncake:$LD_LIBRARY_PATH"
PYTHONPATH="$verify_root" "$python_bin_abs" - "$verify_root" \
  >"$output_root/import-path.txt" <<'PY'
import pathlib
import sys

expected_root = pathlib.Path(sys.argv[1]).resolve()
import mooncake
import mooncake.ep as ep
import mooncake.pg as pg

module_path = pathlib.Path(mooncake.__file__).resolve()
module_path.relative_to(expected_root)
assert hasattr(ep, "Buffer")
assert all(hasattr(pg, name) for name in ("join_group", "recover_ranks", "get_peer_state"))
print(module_path)
PY
PYTHONPATH="$verify_root" "$python_bin_abs" -c \
  'import importlib.metadata; print(importlib.metadata.version("mooncake-transfer-engine-cuda13"))' \
  >"$output_root/package-version.txt"
"$python_bin_abs" -m zipfile -l "$wheel" >"$output_root/wheel-contents.txt"

: >"$output_root/ldd.txt"
while IFS= read -r -d '' shared_object; do
  printf 'FILE %s\n' "$shared_object" >>"$output_root/ldd.txt"
  ldd "$shared_object" >>"$output_root/ldd.txt"
done < <(find "$verify_root/mooncake" -maxdepth 1 -type f -name '*.so' -print0)
if grep -Fq 'not found' "$output_root/ldd.txt"; then
  echo "wheel has unresolved ELF dependencies" >&2
  exit 6
fi

sha256sum "$wheel" | tee "$output_root/wheel.sha256"
printf '%s\n' "$wheel" >"$output_root/wheel-path.txt"
printf '%s\n' "$source_commit" >"$output_root/source-commit.txt"
git -C "$project_root" status --porcelain | tee "$output_root/source-status.txt"
test ! -s "$output_root/source-status.txt"

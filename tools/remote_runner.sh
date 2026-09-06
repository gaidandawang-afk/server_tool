#!/usr/bin/env bash
set -Eeuo pipefail

: "${SERVER_TOOL_RUN_ROOT:?}"
readonly input_root="$SERVER_TOOL_RUN_ROOT/input"
readonly output_root="$SERVER_TOOL_RUN_ROOT/output"
readonly control_root="$SERVER_TOOL_RUN_ROOT/control"
readonly work_root="$SERVER_TOOL_RUN_ROOT/work"

source "$input_root/runtime.env"

mkdir -p "$output_root" "$work_root"
printf '%s\n' "$SERVER_TOOL_RUN_ID" >"$control_root/run.id"
printf '%s\n' "$$" >"$control_root/runner.pgid"
printf '%s\n' "$(date --iso-8601=seconds)" >"$control_root/started_at"
printf '%s\n' running >"$control_root/state"

finish() {
  local code="$?"
  trap - EXIT
  set +e
  local finished_at state
  finished_at="$(date --iso-8601=seconds)"
  if test "$code" -eq 0; then state=succeeded; else state=failed; fi
  printf '%s\n' "$code" >"$control_root/exit_code"
  printf '%s\n' "$finished_at" >"$control_root/finished_at"
  printf '%s\n' "$state" >"$control_root/state"
  RUN_EXIT_CODE="$code" RUN_FINISHED_AT="$finished_at" RUN_ID="$SERVER_TOOL_RUN_ID" \
    python3 - "$output_root" <<'PY'
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
def read_env(path):
    values = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if raw and not raw.startswith("#") and "=" in raw:
            key, value = raw.split("=", 1)
            values[key] = value
    return values

assertions = []
assertion_path = root / "assertions.jsonl"
if assertion_path.exists():
    for line in assertion_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.strip():
            assertions.append(json.loads(line))
result = {
    "schema_version": "server-tool.test-result.v1",
    "run_id": os.environ["RUN_ID"],
    "exit_code": int(os.environ["RUN_EXIT_CODE"]),
    "finished_at": os.environ["RUN_FINISHED_AT"],
    "source": read_env(root / "provenance.env"),
    "container": read_env(root / "container.env"),
    "assertions": assertions,
    "assertions_pass": bool(assertions) and all(item.get("pass") is True for item in assertions),
}
result["python_packages"] = [
    json.loads(path.read_text(encoding="utf-8"))
    for path in sorted(root.glob("python-*.json"))
]
result["pass"] = result["exit_code"] == 0 and result["assertions_pass"]
(root / "result.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
  exit "$code"
}
trap finish EXIT
trap 'exit 143' TERM INT

cp "$input_root/invocation.json" "$output_root/invocation.json"
python3 - "$input_root" >>"$output_root/preparation.log" 2>&1 <<'PY'
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
invocation = json.loads((root / "invocation.json").read_text())
manifest = invocation.get("git_inputs")
if manifest:
    repo = root / "tools-repo"
    subprocess.run(["git", "init", str(repo)], check=True, timeout=30)
    subprocess.run(["git", "-C", str(repo), "fetch", "--depth=1", "--",
                    invocation["tools_git_url"], manifest["head"]], check=True, timeout=180)
    subprocess.run(["git", "-C", str(repo), "checkout", "--detach", "FETCH_HEAD"], check=True, timeout=60)
    actual = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    if actual != manifest["head"]:
        raise ValueError("server_tool commit mismatch")
    for item in manifest["files"]:
        source = repo / item["source"]
        target = root / item["destination"]
        if not source.resolve().is_relative_to(repo.resolve()) or not target.resolve().is_relative_to(root.resolve()):
            raise ValueError("Git input path escapes input root")
        if source.is_symlink() or hashlib.sha256(source.read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError("Git input content mismatch: " + item["source"])
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    print("verified_tools_commit=" + actual, flush=True)
PY

cp "$input_root/TEST.md" "$output_root/TEST.md"
sha256sum "$input_root"/* >"$output_root/input-sha256.txt" 2>/dev/null || true

test -r "$CONTAINER_MANIFEST"
cp "$CONTAINER_MANIFEST" "$output_root/container.env"
grep -Fqx "container_name=$CONTAINER_NAME" "$output_root/container.env"

if test -e "$SERVER_TOOL_PROJECT_ROOT"; then
  test -d "$SERVER_TOOL_PROJECT_ROOT/.git"
  test -f "$SERVER_TOOL_PROJECT_ROOT/.git/server-tool-owner"
  grep -Fqx "profile=$PROFILE_NAME" "$SERVER_TOOL_PROJECT_ROOT/.git/server-tool-owner"
else
  if [[ -n "${SERVER_TOOL_SOURCE_GIT_URL:-}" ]]; then
    {
      git init "$SERVER_TOOL_PROJECT_ROOT"
      timeout 180 git -C "$SERVER_TOOL_PROJECT_ROOT" fetch --depth=1 -- \
        "$SERVER_TOOL_SOURCE_GIT_URL" "$SERVER_TOOL_EXPECTED_HEAD"
      git -C "$SERVER_TOOL_PROJECT_ROOT" checkout -b "$SERVER_TOOL_SOURCE_BRANCH" FETCH_HEAD
    } >>"$output_root/preparation.log" 2>&1
  else
    git clone --branch "$SERVER_TOOL_SOURCE_BRANCH" --single-branch \
      "$input_root/source.bundle" "$SERVER_TOOL_PROJECT_ROOT"
  fi
  printf 'profile=%s\n' "$PROFILE_NAME" >"$SERVER_TOOL_PROJECT_ROOT/.git/server-tool-owner"
fi
test "$(git -C "$SERVER_TOOL_PROJECT_ROOT" rev-parse HEAD)" = "$SERVER_TOOL_EXPECTED_HEAD"
test -z "$(git -C "$SERVER_TOOL_PROJECT_ROOT" status --porcelain)"

{
  printf 'source_branch=%s\n' "$SERVER_TOOL_SOURCE_BRANCH"
  printf 'source_commit=%s\n' "$SERVER_TOOL_EXPECTED_HEAD"
  printf 'project_root=%s\n' "$SERVER_TOOL_PROJECT_ROOT"
  printf 'sglang_kernel_root=%s\n' "$SGLANG_KERNEL_ROOT"
  printf 'sglang_kernel_version=%s\n' "$SGLANG_KERNEL_VERSION"
  printf 'sglang_kernel_required_symbol=%s\n' \
    "${SGLANG_KERNEL_REQUIRED_SYMBOL:-fp8_blockwise_scaled_mm}"
  printf 'mooncake_root=%s\n' "${MOONCAKE_ROOT:-}"
  printf 'mooncake_version=%s\n' "${MOONCAKE_VERSION:-}"
  printf 'mooncake_wheel=%s\n' "${MOONCAKE_WHEEL:-}"
  printf 'mooncake_source_commit=%s\n' "${MOONCAKE_SOURCE_COMMIT:-}"
  printf 'mooncake_wheel_sha256=%s\n' "${MOONCAKE_WHEEL_SHA256:-}"
  printf 'model_path=%s\n' "${MODEL_PATH:-}"
  printf 'ft_ep_num_redundant_experts=%s\n' \
    "${SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS:-128}"
  printf 'ft_mem_fraction_static=%s\n' "${SGLANG_FT_MEM_FRACTION_STATIC:-0.75}"
  printf 'ft_moe_runner_backend=%s\n' "${SGLANG_FT_MOE_RUNNER_BACKEND:-deep_gemm}"
  printf 'deepep_bf16_dispatch=%s\n' "${SGLANG_DEEPEP_BF16_DISPATCH:-0}"
  printf 'ft_precision_oracle_family=%s\n' \
    "${SGLANG_FT_PRECISION_ORACLE_FAMILY:-qwen-fp8-d4t4e4-count10-no-overlap}"
  printf 'ft_reliable_oracle_id=%s\n' \
    "${SGLANG_FT_RELIABLE_ORACLE_ID:-qwen-fp8-reliable-inference-count4}"
  printf 'gpu_ids=%s\n' "$GPU_IDS"
  printf 'port_base=%s\n' "$PORT_BASE"
  printf 'port_count=%s\n' "$PORT_COUNT"
} >"$output_root/provenance.env"

export SERVER_TOOL_INPUT_ROOT="$input_root"
export SERVER_TOOL_OUTPUT_ROOT="$output_root"
export SERVER_TOOL_WORK_ROOT="$work_root"

set +e
timeout --signal=TERM --kill-after=60s \
  "${SERVER_TOOL_RUN_TIMEOUT_SEC}s" bash "$input_root/run.sh" \
  >"$output_root/stdout.log" 2>"$output_root/stderr.log"
code="$?"
set -e
exit "$code"

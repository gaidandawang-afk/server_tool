#!/usr/bin/env bash

st_log() {
  printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

st_assert() {
  local label="$1"
  local passed="$2"
  local expected="${3:-}"
  local actual="${4:-}"
  python3 - "$SERVER_TOOL_OUTPUT_ROOT/assertions.jsonl" "$label" "$passed" "$expected" "$actual" <<'PY'
import json
import sys

path, label, passed, expected, actual = sys.argv[1:]
record = {
    "label": label,
    "pass": passed == "true",
    "expected": expected,
    "actual": actual,
}
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(record, sort_keys=True) + "\n")
PY
  st_log "ASSERT label=$label pass=$passed expected=$expected actual=$actual"
  test "$passed" = true
}

st_record_python_package() {
  local distribution="$1"
  local module="$2"
  local expected_version="$3"
  local expected_root="$4"
  local required_symbol="${5:-}"
  local output="$SERVER_TOOL_OUTPUT_ROOT/python-${distribution}.json"
  set +e
  python3 - "$distribution" "$module" "$expected_version" "$expected_root" "$required_symbol" "$output" <<'PY'
import importlib
import importlib.metadata
import json
import pathlib
import sys

distribution, module_name, expected_version, expected_root, required_symbol, output = sys.argv[1:]
module = importlib.import_module(module_name)
version = importlib.metadata.version(distribution)
module_path = str(pathlib.Path(module.__file__).resolve())
root = str(pathlib.Path(expected_root).resolve())
record = {
    "distribution": distribution,
    "module": module_name,
    "version": version,
    "module_path": module_path,
    "expected_version": expected_version,
    "expected_root": root,
    "required_symbol": required_symbol,
    "symbol_present": not required_symbol or hasattr(module, required_symbol),
}
record["pass"] = (
    version == expected_version
    and (module_path == root or module_path.startswith(root + "/"))
    and record["symbol_present"]
)
pathlib.Path(output).write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
print(json.dumps(record, sort_keys=True))
raise SystemExit(0 if record["pass"] else 1)
PY
  local code=$?
  set -e
  if [[ "$code" -eq 0 ]]; then
    st_assert "python_package_${distribution}" true "$expected_version@$expected_root" "matched"
  else
    st_assert "python_package_${distribution}" false "$expected_version@$expected_root" "mismatch"
  fi
}

st_http_json() {
  local method="$1"
  local url="$2"
  local request_path="$3"
  local response_path="$4"
  local expected_code="$5"
  local label="$6"
  local timeout_sec="${7:-60}"
  local -a args=(
    curl -sS --connect-timeout 5 --max-time "$timeout_sec"
    -o "$response_path" -w "%{http_code}" -X "$method"
  )
  if [[ -n "$request_path" ]]; then
    args+=(-H "Content-Type: application/json" --data-binary "@$request_path")
  fi
  local code rc
  set +e
  code="$("${args[@]}" "$url")"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 && "$code" == "$expected_code" ]]; then
    st_assert "$label" true "HTTP $expected_code" "HTTP $code"
  else
    st_assert "$label" false "HTTP $expected_code" "curl_rc=$rc HTTP=${code:-none}"
  fi
}

st_wait_http_ready() {
  local port="$1"
  local timeout_sec="$2"
  local end=$((SECONDS + timeout_sec))
  while (( SECONDS < end )); do
    if curl -fsS --connect-timeout 2 --max-time 5 "http://127.0.0.1:${port}/health" >/dev/null; then
      st_assert server_ready true "HTTP 200" "HTTP 200"
      return 0
    fi
    sleep 1
  done
  st_assert server_ready false "HTTP 200 within ${timeout_sec}s" timeout
}

st_launch_process_group() {
  local log_path="$1"
  shift
  setsid "$@" >"$log_path" 2>&1 &
  ST_LAST_PGID="$!"
  export ST_LAST_PGID
  printf '%s\n' "$ST_LAST_PGID" >>"$SERVER_TOOL_OUTPUT_ROOT/owned-pgids.txt"
  st_log "PROCESS_GROUP_START pgid=$ST_LAST_PGID command=$(printf '%q ' "$@")"
}

st_process_group_rows() {
  local pgid="$1"
  ps -eo pid=,ppid=,pgid=,stat=,args= --sort=pid | awk -v pg="$pgid" '$3 == pg'
}

st_assert_process_count() {
  local pgid="$1"
  local pattern="$2"
  local expected="$3"
  local label="$4"
  local actual
  actual="$(st_process_group_rows "$pgid" | grep -c -- "$pattern" || true)"
  if [[ "$actual" == "$expected" ]]; then
    st_assert "$label" true "$expected" "$actual"
  else
    st_process_group_rows "$pgid" || true
    st_assert "$label" false "$expected" "$actual"
  fi
}

st_kill_owned_process() {
  local pgid="$1"
  local pattern="$2"
  local signal="$3"
  local label="$4"
  local pid
  pid="$(
    st_process_group_rows "$pgid" |
      awk -v pattern="$pattern" 'index($0, pattern) {print $1; exit}'
  )"
  test -n "$pid"
  test "$(ps -o pgid= -p "$pid" | tr -d ' ')" = "$pgid"
  kill "-$signal" "$pid"
  st_log "PROCESS_KILL label=$label pid=$pid pgid=$pgid signal=$signal"
}

st_stop_owned_pgid() {
  local pgid="$1"
  local label="$2"
  [[ "$pgid" =~ ^[1-9][0-9]*$ ]]
  local actual
  actual="$(ps -o pgid= -p "$pgid" 2>/dev/null | tr -d ' ')"
  if [[ -z "$actual" ]]; then
    st_assert "$label" true gone gone
    return
  fi
  test "$actual" = "$pgid"
  tr '\0' '\n' <"/proc/$pgid/environ" | grep -Fqx "SERVER_TOOL_RUN_ID=$SERVER_TOOL_RUN_ID"
  kill -TERM -- "-$pgid"
  local end=$((SECONDS + 30))
  while (( SECONDS < end )); do
    if ! ps -g "$pgid" >/dev/null 2>&1; then
      st_assert "$label" true gone gone
      return
    fi
    sleep 1
  done
  kill -KILL -- "-$pgid"
  sleep 1
  if ps -g "$pgid" >/dev/null 2>&1; then
    st_assert "$label" false gone still_running
  else
    st_assert "$label" true gone killed
  fi
}

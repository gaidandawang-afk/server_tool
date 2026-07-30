#!/usr/bin/env bash

st_log() {
  printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

st_preserve_run_dir_files() {
  local st_run_dir="$1"
  if [[ -d "$st_run_dir" ]]; then
    find "$st_run_dir" -maxdepth 1 -type f \
      -exec cp -f {} "$SERVER_TOOL_OUTPUT_ROOT/" \;
  fi
}

st_assert() {
  local st_label="$1"
  local st_passed="$2"
  local st_expected="${3:-}"
  local st_actual="${4:-}"
  python3 - "$SERVER_TOOL_OUTPUT_ROOT/assertions.jsonl" "$st_label" "$st_passed" "$st_expected" "$st_actual" <<'PY'
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
  st_log "ASSERT label=$st_label pass=$st_passed expected=$st_expected actual=$st_actual"
  test "$st_passed" = true
}

st_record_python_package() {
  local st_distribution="$1"
  local st_module="$2"
  local st_expected_version="$3"
  local st_expected_root="$4"
  local st_required_symbol="${5:-}"
  local st_output="$SERVER_TOOL_OUTPUT_ROOT/python-${st_distribution}.json"
  set +e
  python3 - "$st_distribution" "$st_module" "$st_expected_version" "$st_expected_root" "$st_required_symbol" "$st_output" <<'PY'
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
  local st_code=$?
  set -e
  if [[ "$st_code" -eq 0 ]]; then
    st_assert "python_package_${st_distribution}" true "$st_expected_version@$st_expected_root" "matched"
  else
    st_assert "python_package_${st_distribution}" false "$st_expected_version@$st_expected_root" "mismatch"
  fi
}

st_http_json() {
  local st_method="$1"
  local st_url="$2"
  local st_request_path="$3"
  local st_response_path="$4"
  local st_expected_code="$5"
  local st_label="$6"
  local st_timeout_sec="${7:-60}"
  local -a st_args=(
    curl -sS --connect-timeout 5 --max-time "$st_timeout_sec"
    -o "$st_response_path" -w "%{http_code}" -X "$st_method"
  )
  if [[ -n "$st_request_path" ]]; then
    st_args+=(-H "Content-Type: application/json" --data-binary "@$st_request_path")
  fi
  local st_code st_rc
  set +e
  st_code="$("${st_args[@]}" "$st_url")"
  st_rc=$?
  set -e
  if [[ "$st_rc" -eq 0 && "$st_code" == "$st_expected_code" ]]; then
    st_assert "$st_label" true "HTTP $st_expected_code" "HTTP $st_code"
  else
    st_assert "$st_label" false "HTTP $st_expected_code" "curl_rc=$st_rc HTTP=${st_code:-none}"
  fi
}

st_wait_http_json() {
  local st_method="$1"
  local st_url="$2"
  local st_request_path="$3"
  local st_response_path="$4"
  local st_expected_code="$5"
  local st_label="$6"
  local st_timeout_sec="${7:-30}"
  local st_end=$((SECONDS + st_timeout_sec))
  local st_code="" st_rc=0
  while (( SECONDS < st_end )); do
    set +e
    st_code="$(
      curl -sS --connect-timeout 5 --max-time 15 \
        -o "$st_response_path" -w "%{http_code}" -X "$st_method" \
        -H "Content-Type: application/json" --data-binary "@$st_request_path" \
        "$st_url"
    )"
    st_rc=$?
    set -e
    if [[ "$st_rc" -eq 0 && "$st_code" == "$st_expected_code" ]]; then
      st_assert "$st_label" true "HTTP $st_expected_code" "HTTP $st_code"
      return 0
    fi
    sleep 1
  done
  st_assert "$st_label" false "HTTP $st_expected_code" \
    "curl_rc=$st_rc HTTP=${st_code:-none}"
}

st_wait_http_ready() {
  local st_port="$1"
  local st_timeout_sec="$2"
  local st_end=$((SECONDS + st_timeout_sec))
  while (( SECONDS < st_end )); do
    if curl -fsS --connect-timeout 2 --max-time 5 "http://127.0.0.1:${st_port}/health" >/dev/null; then
      st_assert server_ready true "HTTP 200" "HTTP 200"
      return 0
    fi
    sleep 1
  done
  st_assert server_ready false "HTTP 200 within ${st_timeout_sec}s" timeout
}

st_launch_process_group() {
  local st_log_path="$1"
  shift
  setsid "$@" >"$st_log_path" 2>&1 &
  ST_LAST_PGID="$!"
  export ST_LAST_PGID
  printf '%s\n' "$ST_LAST_PGID" >>"$SERVER_TOOL_OUTPUT_ROOT/owned-pgids.txt"
  st_log "PROCESS_GROUP_START pgid=$ST_LAST_PGID command=$(printf '%q ' "$@")"
}

st_process_group_rows() {
  local st_pgid="$1"
  ps -eo pid=,ppid=,pgid=,stat=,args= --sort=pid | awk -v pg="$st_pgid" '$3 == pg'
}

st_assert_process_count() {
  local st_pgid="$1"
  local st_pattern="$2"
  local st_expected="$3"
  local st_label="$4"
  local st_actual
  st_actual="$(st_process_group_rows "$st_pgid" | grep -c -- "$st_pattern" || true)"
  if [[ "$st_actual" == "$st_expected" ]]; then
    st_assert "$st_label" true "$st_expected" "$st_actual"
  else
    st_process_group_rows "$st_pgid" || true
    st_assert "$st_label" false "$st_expected" "$st_actual"
  fi
}

st_kill_owned_process() {
  local st_pgid="$1"
  local st_pattern="$2"
  local st_signal="$3"
  local st_label="$4"
  local st_pid
  st_pid="$(
    st_process_group_rows "$st_pgid" |
      awk -v pattern="$st_pattern" 'index($0, pattern) {print $1; exit}'
  )"
  test -n "$st_pid"
  test "$(ps -o pgid= -p "$st_pid" | tr -d ' ')" = "$st_pgid"
  kill "-$st_signal" "$st_pid"
  st_log "PROCESS_KILL label=$st_label pid=$st_pid pgid=$st_pgid signal=$st_signal"
}

st_stop_owned_pid() {
  local st_pid="$1"
  local st_label="$2"
  [[ "$st_pid" =~ ^[1-9][0-9]*$ ]]
  if ! kill -0 "$st_pid" 2>/dev/null; then
    st_assert "$st_label" true gone gone
    return
  fi
  tr '\0' '\n' <"/proc/$st_pid/environ" |
    grep -Fqx "SERVER_TOOL_RUN_ID=$SERVER_TOOL_RUN_ID"
  kill -TERM "$st_pid"
  st_assert "$st_label" true stopped stopped
}

st_stop_owned_pgid() {
  local st_pgid="$1"
  local st_label="$2"
  [[ "$st_pgid" =~ ^[1-9][0-9]*$ ]]
  local st_actual
  st_actual="$(ps -o pgid= -p "$st_pgid" 2>/dev/null | tr -d ' ')"
  if [[ -z "$st_actual" ]]; then
    st_assert "$st_label" true gone gone
    return
  fi
  test "$st_actual" = "$st_pgid"
  tr '\0' '\n' <"/proc/$st_pgid/environ" | grep -Fqx "SERVER_TOOL_RUN_ID=$SERVER_TOOL_RUN_ID"
  kill -TERM -- "-$st_pgid"
  local st_end=$((SECONDS + 30))
  while (( SECONDS < st_end )); do
    if ! ps -g "$st_pgid" >/dev/null 2>&1; then
      st_assert "$st_label" true gone gone
      return
    fi
    sleep 1
  done
  kill -KILL -- "-$st_pgid"
  sleep 1
  if ps -g "$st_pgid" >/dev/null 2>&1; then
    st_assert "$st_label" false gone still_running
  else
    st_assert "$st_label" true gone killed
  fi
}

st_kill_owned_pgid() {
  local st_pgid="$1"
  local st_label="$2"
  local st_timeout_sec="${3:-30}"
  [[ "$st_pgid" =~ ^[1-9][0-9]*$ ]]
  test "$(ps -o pgid= -p "$st_pgid" | tr -d ' ')" = "$st_pgid"
  tr '\0' '\n' <"/proc/$st_pgid/environ" |
    grep -Fqx "SERVER_TOOL_RUN_ID=$SERVER_TOOL_RUN_ID"
  kill -KILL -- "-$st_pgid"
  set +e
  wait "$st_pgid" 2>/dev/null
  set -e
  local st_end=$((SECONDS + st_timeout_sec))
  while (( SECONDS < st_end )); do
    if ! ps -g "$st_pgid" >/dev/null 2>&1; then
      st_assert "$st_label" true gone gone
      return
    fi
    sleep 1
  done
  st_assert "$st_label" false gone still_running
}

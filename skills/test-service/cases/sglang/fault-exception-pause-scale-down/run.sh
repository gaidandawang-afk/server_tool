#!/usr/bin/env bash
set -Eeuo pipefail

source "$SERVER_TOOL_INPUT_ROOT/units/test_ops.sh"
source "$SERVER_TOOL_INPUT_ROOT/units/sglang_ft_ops.sh"

readonly port="$PORT_BASE"
readonly run_dir="$SERVER_TOOL_WORK_ROOT/case"
readonly log_path="$SERVER_TOOL_OUTPUT_ROOT/server.log"
readonly trigger_file="$run_dir/recoverable-fault.trigger"
readonly done_file="$run_dir/recoverable-fault.done"
server_pgid=""
declare -a concurrent_pids=()

cleanup() {
  local original_code="$?"
  trap - EXIT
  set +e
  if [[ -d "$run_dir" ]]; then
    cp "$run_dir"/*.json "$run_dir"/*.status "$run_dir"/*.rc \
      "$run_dir"/*.stderr "$SERVER_TOOL_OUTPUT_ROOT/" 2>/dev/null || true
  fi
  for pid in "${concurrent_pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      st_stop_owned_pid "$pid" concurrent_request_cleanup
    fi
  done
  if [[ -n "$server_pgid" ]]; then
    st_stop_owned_pgid "$server_pgid" server_process_group_cleanup
  fi
  if [[ -z "$(git -C "$SERVER_TOOL_PROJECT_ROOT" status --porcelain)" ]]; then
    st_assert source_clean true clean clean
  else
    st_assert source_clean false clean dirty
  fi
  if [[ "$original_code" -eq 0 ]]; then
    st_assert case_result true pass pass
  else
    st_assert case_result false pass "exit_$original_code"
  fi
  exit "$original_code"
}
trap cleanup EXIT

mkdir -p "$run_dir"
sg_prepare_dp4_runtime

run_concurrent_burst() {
  local phase="$1"
  shift
  local -a ranks=("$@")
  local -a responses=()
  local -a statuses=()
  local -a return_codes=()
  local rank slot index=0
  concurrent_pids=()

  for rank in "${ranks[@]}"; do
    for slot in 0 1; do
      local request="$run_dir/${phase}-request-dp${rank}-${slot}.json"
      local response="$run_dir/${phase}-response-dp${rank}-${slot}.json"
      local error="$run_dir/${phase}-response-dp${rank}-${slot}.stderr"
      local status="$run_dir/${phase}-response-dp${rank}-${slot}.status"
      local return_code="$run_dir/${phase}-response-dp${rank}-${slot}.rc"
      sg_write_rank_request "$request" "$rank" 64
      (
        set +e
        code="$(curl -sS --connect-timeout 5 --max-time 120 \
          -o "$response" -w '%{http_code}' -X POST \
          -H 'Content-Type: application/json' --data-binary "@$request" \
          "http://127.0.0.1:${port}/generate" 2>"$error")"
        rc="$?"
        printf '%s\n' "$code" >"$status"
        printf '%s\n' "$rc" >"$return_code"
        exit 0
      ) &
      concurrent_pids+=("$!")
      responses+=("$response")
      statuses+=("$status")
      return_codes+=("$return_code")
      index=$((index + 1))
    done
  done

  local alive=0 pid
  for pid in "${concurrent_pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      alive=$((alive + 1))
    fi
  done
  if (( alive >= 2 )); then
    st_assert "${phase}_concurrent_inflight" true ">=2" "$alive"
  else
    st_assert "${phase}_concurrent_inflight" false ">=2" "$alive"
  fi

  for index in "${!concurrent_pids[@]}"; do
    wait "${concurrent_pids[$index]}"
    local code rc label="${phase}_request_${index}"
    code="$(<"${statuses[$index]}")"
    rc="$(<"${return_codes[$index]}")"
    if [[ "$rc" == 0 && "$code" == 200 ]]; then
      st_assert "$label" true "HTTP 200" "HTTP $code"
    else
      st_assert "$label" false "HTTP 200" "curl_rc=$rc HTTP=${code:-none}"
    fi
    if python3 - "${responses[$index]}" \
      "$run_dir/${label}-contract.json" <<'PY'
import json
import pathlib
import sys

response_path, output_path = map(pathlib.Path, sys.argv[1:])
response = json.loads(response_path.read_text())
meta_info = response.get("meta_info", {})
output_ids = response.get("output_ids")
record = {
    "finish_reason": meta_info.get("finish_reason"),
    "completion_tokens": meta_info.get("completion_tokens"),
    "output_token_count": len(output_ids) if isinstance(output_ids, list) else None,
}
record["pass"] = (
    record["finish_reason"] is not None
    and record["completion_tokens"] == 64
    and record["output_token_count"] == 64
)
output_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
raise SystemExit(0 if record["pass"] else 1)
PY
    then
      st_assert "${label}_complete" true "finish_reason+64_tokens" matched
    else
      st_assert "${label}_complete" false "finish_reason+64_tokens" mismatch
    fi
  done
  concurrent_pids=()
}

declare -a requests=()
declare -a baselines=()
for rank in 0 1 2 3; do
  requests[$rank]="$run_dir/request-dp${rank}.json"
  baselines[$rank]="$run_dir/baseline-dp${rank}.json"
  sg_write_rank_request "${requests[$rank]}" "$rank" 10
done

sg_launch_dp4_ft pause "$port" "$log_path" 2 "$trigger_file" "$done_file"
server_pgid="$ST_LAST_PGID"
if [[ "${SGLANG_FT_OVERLAP_SCHEDULE:-0}" == 1 ]]; then
  st_assert overlap_schedule_mode true enabled enabled
else
  st_assert overlap_schedule_mode true disabled disabled
fi

st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial
for rank in 0 1 2 3; do
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "${requests[$rank]}" "${baselines[$rank]}" 200 "baseline_dp${rank}" 90
done
run_concurrent_burst before_fault 0 1 2 3

sg_start_recoverable_fault "$trigger_file"
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[2]}" "$run_dir/trigger-response.json" 503 discard_current 180
sg_wait_recoverable_fault_done "$done_file" 1 60 recoverable_fault_done
sg_wait_ft_status "$port" "$run_dir/status-unhealthy.json" \
  "0=unhealthy,1=unhealthy,2=unhealthy,3=unhealthy" 120 status_unhealthy
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_after_exception
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[0]}" "$run_dir/admission-closed.json" 503 \
  admission_blocks_generate 90

eplb_count_before="$(sg_log_count "$log_path" '\[EPLBManager\] rebalance end')"
sg_apply_scale_down \
  "$port" 2 "$run_dir/scale-down-request.json" "$run_dir/scale-down-response.json" \
  "$run_dir/status-scaled-down.json" "0=healthy,1=healthy,2=dead,3=healthy" \
  "$SGLANG_FT_CONTROL_WAIT_TIMEOUT_SEC" status_scaled_down
sg_assert_log_count_increased "$log_path" '\[EPLBManager\] rebalance end' \
  "$eplb_count_before" whole_dp2_forced_eplb
st_assert_process_count "$server_pgid" "sglang::scheduler" 3 \
  whole_dp2_shutdown_process_count
dp2_pid="$(sg_find_scheduler_pid_by_global_rank "$server_pgid" 2)"
if [[ -z "$dp2_pid" ]]; then
  st_assert global_rank2_shutdown true absent absent
else
  st_assert global_rank2_shutdown false absent "$dp2_pid"
fi
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[2]}" "$run_dir/dead-dp2.json" 503 dead_dp2_closed 180
sg_assert_inactive_route_error "$run_dir/dead-dp2.json" 2 dead_dp2_inactive_error

for rank in 0 1 3; do
  response="$run_dir/after-scale-down-dp${rank}.json"
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "${requests[$rank]}" "$response" 200 "generate_dp${rank}" 90
  sg_assert_output_ids_equal \
    "${baselines[$rank]}" "$response" \
    "$run_dir/after-scale-down-dp${rank}-precision.json" \
    "after_scale_down_dp${rank}" 10
done
run_concurrent_burst after_scale_down 0 1 3

cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"
cp "$run_dir"/*.status "$run_dir"/*.rc "$run_dir"/*.stderr \
  "$SERVER_TOOL_OUTPUT_ROOT/"
cp "$trigger_file" "$done_file" "$SERVER_TOOL_OUTPUT_ROOT/"

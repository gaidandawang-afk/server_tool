#!/usr/bin/env bash
set -Eeuo pipefail

source "$SERVER_TOOL_INPUT_ROOT/units/test_ops.sh"
source "$SERVER_TOOL_INPUT_ROOT/units/sglang_ft_ops.sh"

readonly port="$PORT_BASE"
readonly run_dir="$SERVER_TOOL_WORK_ROOT/case"
readonly log_path="$SERVER_TOOL_OUTPUT_ROOT/server.log"
server_pgid=""

cleanup() {
  local original_code="$?"
  trap - EXIT
  set +e
  st_preserve_run_dir_files "$run_dir"
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
sg_prepare_ft_runtime 4 2 4

readonly request_dp0="$run_dir/request-dp0.json"
readonly request_dp1="$run_dir/request-dp1.json"
readonly baseline_dp0="$run_dir/baseline-dp0.json"
readonly baseline_dp1="$run_dir/baseline-dp1.json"
sg_write_rank_request "$request_dp0" 0 10
sg_write_rank_request "$request_dp1" 1 10

sg_launch_ft pause "$port" "$log_path" 4 2 4
server_pgid="$ST_LAST_PGID"

st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$request_dp0" "$baseline_dp0" 200 baseline_dp0 90
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$request_dp1" "$baseline_dp1" 200 baseline_dp1 90

rank3_pid="$(sg_find_scheduler_pid_by_global_rank "$server_pgid" 3)"
if [[ -n "$rank3_pid" ]]; then
  st_assert rank3_sibling_present true present "$rank3_pid"
else
  st_assert rank3_sibling_present false present absent
fi
sg_kill_scheduler_global_rank "$server_pgid" 2 global_rank2_dp1
sg_wait_ft_status "$port" "$run_dir/status-incident.json" \
  "0=healthy,1=dead" 120 status_dp1_dead
st_assert_process_count "$server_pgid" "sglang::scheduler" 3 schedulers_after_kill
rank3_before_apply="$(sg_find_scheduler_pid_by_global_rank "$server_pgid" 3)"
if [[ "$rank3_before_apply" == "$rank3_pid" ]]; then
  st_assert rank3_alive_before_scale_down true "$rank3_pid" "$rank3_before_apply"
else
  st_assert rank3_alive_before_scale_down false "$rank3_pid" "${rank3_before_apply:-absent}"
fi
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$request_dp0" "$run_dir/incident-dp0.json" 503 admission_closed 90

eplb_count_before="$(sg_log_count "$log_path" '\[EPLBManager\] rebalance start')"
sg_apply_scale_down \
  "$port" 1 "$run_dir/scale-down-request.json" "$run_dir/scale-down-response.json" \
  "$run_dir/status-scaled-down.json" "0=healthy,1=dead" 120 status_scaled_down
sg_assert_log_count_increased "$log_path" '\[EPLBManager\] rebalance start' \
  "$eplb_count_before" whole_dp_scale_down_forced_eplb
st_assert_process_count "$server_pgid" "sglang::scheduler" 2 schedulers_after_scale_down
global_rank2_pid="$(sg_find_scheduler_pid_by_global_rank "$server_pgid" 2)"
if [[ -z "$global_rank2_pid" ]]; then
  st_assert global_rank2_shutdown true absent absent
else
  st_assert global_rank2_shutdown false absent "$global_rank2_pid"
fi
global_rank3_pid="$(sg_find_scheduler_pid_by_global_rank "$server_pgid" 3)"
if [[ -z "$global_rank3_pid" ]]; then
  st_assert global_rank3_shutdown true absent absent
else
  st_assert global_rank3_shutdown false absent "$global_rank3_pid"
fi

st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$request_dp1" "$run_dir/dead-route-dp1.json" 400 dp1_unroutable 90
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$request_dp0" "$run_dir/post-scale-down-dp0.json" 200 post_scale_down_dp0 90
sg_assert_output_ids_equal \
  "$baseline_dp0" "$run_dir/post-scale-down-dp0.json" \
  "$run_dir/whole-dp-shutdown-precision.json" whole_dp_shutdown 10

cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"

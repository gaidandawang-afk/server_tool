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
sg_prepare_dp4_runtime
declare -a requests=()
for rank in 0 1 2 3; do
  requests[$rank]="$run_dir/request-dp${rank}.json"
  sg_write_rank_request "${requests[$rank]}" "$rank" 10
done

sg_launch_dp4_ft pause "$port" "$log_path"
server_pgid="$ST_LAST_PGID"
st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[0]}" "$run_dir/baseline-inference.json" 200 \
  baseline_inference 180

st_kill_owned_process "$server_pgid" "_TP1_EP" KILL kill_dp1
sg_wait_ft_status "$port" "$run_dir/status-after-dp1-kill.json" \
  "0=healthy,1=dead,2=healthy,3=healthy" 120 status_after_dp1_kill
st_assert_process_count "$server_pgid" "sglang::scheduler" 3 schedulers_after_dp1_kill

st_kill_owned_process "$server_pgid" "_TP2_EP" KILL kill_dp2
sg_wait_ft_status "$port" "$run_dir/status-after-double-kill.json" \
  "0=healthy,1=dead,2=dead,3=healthy" 120 status_after_double_kill
st_assert_process_count "$server_pgid" "sglang::scheduler" 2 schedulers_after_double_kill
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[0]}" "$run_dir/admission-closed.json" 503 \
  admission_blocks_generate 90

eplb_count_before="$(sg_log_count "$log_path" '\[EPLBManager\] rebalance start')"
sg_apply_scale_down_ranks "$port" "1,2" \
  "$run_dir/scale-down-request.json" "$run_dir/scale-down-response.json" \
  "$run_dir/status-scaled-down.json" "0=healthy,1=dead,2=dead,3=healthy" \
  120 status_scaled_down
sg_assert_log_count_increased "$log_path" '\[EPLBManager\] rebalance start' \
  "$eplb_count_before" multi_rank_scale_down_forced_eplb
st_assert_process_count "$server_pgid" "sglang::scheduler" 2 schedulers_after_scale_down

for rank in 1 2; do
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "${requests[$rank]}" "$run_dir/dead-dp${rank}.json" 400 "dead_dp${rank}_closed" 90
done
for rank in 0 3; do
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "${requests[$rank]}" "$run_dir/survivor-dp${rank}.json" 200 \
    "survivor_dp${rank}" 180
  sg_assert_known_output_ids \
    "$run_dir/survivor-dp${rank}.json" \
    "$(sg_precision_oracle_id "$rank")" \
    "$run_dir/survivor-dp${rank}-precision.json"
done

cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"

#!/usr/bin/env bash
set -Eeuo pipefail

source "$SERVER_TOOL_INPUT_ROOT/units/test_ops.sh"
source "$SERVER_TOOL_INPUT_ROOT/units/sglang_ft_ops.sh"

readonly port="$PORT_BASE"
readonly run_dir="$SERVER_TOOL_WORK_ROOT/case"
readonly log_path="$SERVER_TOOL_OUTPUT_ROOT/server.log"
readonly request_dp0="$run_dir/request-dp0.json"
server_pgid=""

cleanup() {
  local original_code="$?"
  trap - EXIT
  set +e
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
sg_write_rank_request "$request_dp0" 0 10

sg_launch_dp4_ft pause "$port" "$log_path"
server_pgid="$ST_LAST_PGID"
st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial

declare -a paused_states=(
  "0=paused,1=dead,2=paused,3=paused"
  "0=paused,1=dead,2=dead,3=paused"
  "0=paused,1=dead,2=dead,3=dead"
)
declare -a healthy_states=(
  "0=healthy,1=dead,2=healthy,3=healthy"
  "0=healthy,1=dead,2=dead,3=healthy"
  "0=healthy,1=dead,2=dead,3=dead"
)

for target in 1 2 3; do
  index=$((target - 1))
  st_kill_owned_process "$server_pgid" "_TP${target}_EP" KILL "kill_dp${target}"
  sg_wait_ft_status "$port" "$run_dir/status-dp${target}-paused.json" \
    "${paused_states[$index]}" 120 "status_dp${target}_paused"
  st_assert_process_count "$server_pgid" "sglang::scheduler" "$((4 - target))" \
    "schedulers_after_dp${target}_kill"
  sg_apply_scale_down "$port" "$target" \
    "$run_dir/scale-down-dp${target}-request.json" \
    "$run_dir/scale-down-dp${target}-response.json"
  sg_wait_ft_status "$port" "$run_dir/status-dp${target}-scaled-down.json" \
    "${healthy_states[$index]}" 120 "status_dp${target}_scaled_down"
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "$request_dp0" "$run_dir/after-dp${target}-dp0.json" 200 \
    "after_dp${target}_dp0" 180
  sg_assert_output_ids \
    "$run_dir/after-dp${target}-dp0.json" \
    qwen-fp8-d4t4e4-count10-no-overlap-rank0-r128 \
    "$run_dir/after-dp${target}-dp0-precision.json"
done

st_assert_process_count "$server_pgid" "sglang::scheduler" 1 schedulers_final
cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"

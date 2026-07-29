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

sg_launch_dp4_ft continue "$port" "$log_path"
server_pgid="$ST_LAST_PGID"

st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial

st_kill_owned_process "$server_pgid" "_TP1_EP" KILL kill_dp1
sg_wait_ft_status "$port" "$run_dir/status-after-kill.json" \
  "0=healthy,1=dead,2=healthy,3=healthy" 120 status_after_kill
st_assert_process_count "$server_pgid" "sglang::scheduler" 3 schedulers_after_kill
sg_assert_log_count "$log_path" "FT command dispatch:.*command=pause" 0 continue_has_no_pause

st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[1]}" "$run_dir/dead-dp1.json" 400 dead_dp1_closed 180
for rank in 0 2 3; do
  response="$run_dir/after-fault-dp${rank}.json"
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "${requests[$rank]}" "$response" 200 "generate_dp${rank}" 180
  sg_assert_output_ids \
    "$response" "qwen-fp8-d4t4e4-count10-no-overlap-rank${rank}-r128" \
    "$run_dir/after-fault-dp${rank}-precision.json"
done

cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"

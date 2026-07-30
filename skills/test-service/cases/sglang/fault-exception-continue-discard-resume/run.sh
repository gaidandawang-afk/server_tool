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
sg_write_rank_request "$run_dir/request-dp0.json" 0 10

sg_launch_dp4_ft continue "$port" "$log_path" 0 "$trigger_file" "$done_file"
server_pgid="$ST_LAST_PGID"

st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$run_dir/request-dp0.json" "$run_dir/baseline-dp0.json" 200 baseline_dp0 180
sg_assert_output_ids \
  "$run_dir/baseline-dp0.json" \
  qwen-fp8-d4t4e4-count10-no-overlap-rank0-r128 \
  "$run_dir/baseline-dp0-precision.json"

sg_start_recoverable_fault "$trigger_file"
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$run_dir/request-dp0.json" "$run_dir/discarded-dp0.json" \
  503 discard_current_dp0 180
sg_wait_recoverable_fault_done "$done_file" 1 60 recoverable_fault_done
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 \
  schedulers_after_exception
sg_wait_ft_status "$port" "$run_dir/status-after-discard.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 30 status_after_discard
sg_assert_log_count "$log_path" "FT command dispatch:.*command=pause" 0 \
  continue_has_no_pause

st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$run_dir/request-dp0.json" "$run_dir/post-exception-dp0.json" \
  200 post_exception_dp0 180
sg_assert_output_ids \
  "$run_dir/post-exception-dp0.json" \
  qwen-fp8-d4t4e4-count10-no-overlap-rank0-r128 \
  "$run_dir/post-exception-dp0-precision.json"

#!/usr/bin/env bash
set -Eeuo pipefail

source "$SERVER_TOOL_INPUT_ROOT/units/test_ops.sh"
source "$SERVER_TOOL_INPUT_ROOT/units/sglang_ft_ops.sh"

readonly port="$PORT_BASE"
readonly run_dir="$SERVER_TOOL_WORK_ROOT/case"
readonly log_path="$SERVER_TOOL_OUTPUT_ROOT/server.log"
readonly request_dp0="$run_dir/request-dp0.json"
readonly request_dp1="$run_dir/request-dp1.json"
readonly stream_request="$run_dir/stream-request-dp1.json"
readonly stream_output="$run_dir/stream-dp1.out"
readonly stream_error="$run_dir/stream-dp1.err"
server_pgid=""
stream_pid=""

cleanup() {
  local original_code="$?"
  trap - EXIT
  set +e
  if [[ -n "$stream_pid" ]] && kill -0 "$stream_pid" 2>/dev/null; then
    st_stop_owned_pid "$stream_pid" stream_process_cleanup
  fi
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
sg_write_rank_request "$request_dp1" 1 10
sg_write_stream_rank_request "$stream_request" 1 64

sg_launch_dp4_ft continue "$port" "$log_path"
server_pgid="$ST_LAST_PGID"
st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$request_dp0" "$run_dir/baseline-dp0.json" 200 baseline_dp0 90
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$request_dp1" "$run_dir/baseline-dp1.json" 200 baseline_dp1 90

sg_start_stream_request "$port" "$stream_request" "$stream_output" "$stream_error" 60
stream_pid="$ST_LAST_STREAM_PID"
sg_wait_stream_decode_rank "$stream_output" 1 60
st_kill_owned_process "$server_pgid" "_TP1_EP" KILL kill_dp1_inflight
sg_wait_ft_status "$port" "$run_dir/status-rank1-dead.json" \
  "0=healthy,1=dead,2=healthy,3=healthy" 120 status_rank1_dead
st_assert_process_count "$server_pgid" "sglang::scheduler" 3 schedulers_after_kill
sg_capture_interrupted_stream_contract \
  "$stream_pid" "$stream_output" "$stream_error" \
  "$run_dir/continue-inflight-contract.json" 70 continue_rank1_after_kill
stream_pid=""

st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$request_dp0" "$run_dir/post-kill-dp0.json" 200 post_kill_dp0 90
sg_assert_output_ids_equal \
  "$run_dir/baseline-dp0.json" "$run_dir/post-kill-dp0.json" \
  "$run_dir/post-kill-precision.json" post_kill_dp0 10

cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"
cp "$stream_output" "$stream_error" "$SERVER_TOOL_OUTPUT_ROOT/"

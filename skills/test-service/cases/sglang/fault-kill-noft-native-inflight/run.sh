#!/usr/bin/env bash
set -Eeuo pipefail

source "$SERVER_TOOL_INPUT_ROOT/units/test_ops.sh"
source "$SERVER_TOOL_INPUT_ROOT/units/sglang_ft_ops.sh"

readonly port="$PORT_BASE"
readonly run_dir="$SERVER_TOOL_WORK_ROOT/case"
readonly log_path="$SERVER_TOOL_OUTPUT_ROOT/server.log"
readonly stream_request="$run_dir/stream-request-dp0.json"
readonly stream_output="$run_dir/stream-dp0.out"
readonly stream_error="$run_dir/stream-dp0.err"
readonly post_request="$run_dir/post-fault-request-dp0.json"
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
sg_write_stream_rank_request "$stream_request" 0 64
sg_write_rank_request "$post_request" 0 10

sg_launch_dp4_mooncake_noft "$port" "$log_path"
server_pgid="$ST_LAST_PGID"
st_wait_http_ready "$port" 180
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial
st_http_json GET "http://127.0.0.1:${port}/fault_tolerance/status" \
  "" "$run_dir/ft-status-disabled.json" 503 ft_status_disabled 30

sg_start_stream_request "$port" "$stream_request" "$stream_output" "$stream_error" 180
stream_pid="$ST_LAST_STREAM_PID"
sg_wait_stream_decode_rank "$stream_output" 0 60
st_kill_owned_process "$server_pgid" "_TP1_EP" KILL kill_dp1_during_dp0_stream
sg_capture_completed_stream_contract \
  "$stream_pid" "$stream_output" "$stream_error" \
  "$run_dir/stream-contract.json" "$run_dir/stream-final-response.json" \
  190 64 native_dp0_stream_after_dp1_kill
stream_pid=""
st_assert_process_count "$server_pgid" "sglang::scheduler" 3 schedulers_after_kill
sg_assert_log_contains \
  "$log_path" "marking peer 1 as broken|learned peer 1 is broken" \
  native_mooncake_isolated_rank1

st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$post_request" "$run_dir/post-fault-dp0.json" 200 post_fault_dp0 180
sg_assert_output_ids \
  "$run_dir/post-fault-dp0.json" \
  qwen-fp8-d4t4e4-count10-no-overlap-rank0-r128 \
  "$run_dir/post-fault-dp0-precision.json"

cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"
cp "$stream_output" "$stream_error" "$SERVER_TOOL_OUTPUT_ROOT/"

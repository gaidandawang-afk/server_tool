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

sg_write_rank_request "$run_dir/request-dp0.json" 0 10
sg_write_rank_request "$run_dir/request-dp1.json" 1 10
cat >"$run_dir/retry-request.json" <<'JSON'
{"fault_tolerance_instruction":"retry","fault_tolerance_timeout":180}
JSON
cat >"$run_dir/scale-down-no-paused-request.json" <<'JSON'
{"fault_tolerance_instruction":"scale_down","fault_tolerance_timeout":180,"fault_tolerance_params":{"ranks":[1]}}
JSON

sg_launch_dp4_ft pause "$port" "$log_path"
server_pgid="$ST_LAST_PGID"

st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$run_dir/request-dp0.json" "$run_dir/baseline-dp0.json" 200 baseline_dp0 180
sg_assert_known_output_ids \
  "$run_dir/baseline-dp0.json" \
  "$(sg_precision_oracle_id 0)" \
  "$run_dir/baseline-dp0-precision.json"

st_http_json POST "http://127.0.0.1:${port}/fault_tolerance/apply" \
  "$run_dir/retry-request.json" "$run_dir/retry-no-paused-response.json" \
  400 retry_no_paused 60
sg_assert_ft_failure_message \
  "$run_dir/retry-no-paused-response.json" no_paused_rank \
  retry_no_paused_reason
st_http_json POST "http://127.0.0.1:${port}/fault_tolerance/apply" \
  "$run_dir/scale-down-no-paused-request.json" \
  "$run_dir/scale-down-no-paused-response.json" \
  400 scale_down_no_paused 60
sg_assert_ft_failure_message \
  "$run_dir/scale-down-no-paused-response.json" no_paused_rank \
  scale_down_no_paused_reason
sg_wait_ft_status "$port" "$run_dir/status-after-healthy-rejections.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 30 \
  status_unchanged_after_healthy_rejections

st_kill_owned_process "$server_pgid" "_TP1_EP" KILL kill_dp1
sg_wait_ft_status "$port" "$run_dir/status-paused.json" \
  "0=paused,1=dead,2=paused,3=paused" 120 status_paused
st_assert_process_count "$server_pgid" "sglang::scheduler" 3 schedulers_after_kill

sg_apply_scale_down "$port" 1 \
  "$run_dir/scale-down-request.json" "$run_dir/scale-down-response.json"
sg_wait_ft_status "$port" "$run_dir/status-scaled-down.json" \
  "0=healthy,1=dead,2=healthy,3=healthy" 120 status_scaled_down
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$run_dir/request-dp0.json" "$run_dir/post-scale-down-dp0.json" \
  200 post_scale_down_dp0 180
sg_assert_known_output_ids \
  "$run_dir/post-scale-down-dp0.json" \
  "$(sg_precision_oracle_id 0)" \
  "$run_dir/post-scale-down-dp0-precision.json"

st_http_json POST "http://127.0.0.1:${port}/fault_tolerance/apply" \
  "$run_dir/retry-request.json" "$run_dir/retry-after-scale-down-response.json" \
  400 retry_after_scale_down 60
sg_assert_ft_failure_message \
  "$run_dir/retry-after-scale-down-response.json" no_paused_rank \
  retry_after_scale_down_reason
sg_wait_ft_status "$port" "$run_dir/status-after-retry-rejection.json" \
  "0=healthy,1=dead,2=healthy,3=healthy" 30 \
  status_unchanged_after_retry_rejection

st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$run_dir/request-dp1.json" "$run_dir/dead-dp1-response.json" \
  400 dead_dp1_rejected 60
sg_wait_ft_status "$port" "$run_dir/status-after-dead-route-rejection.json" \
  "0=healthy,1=dead,2=healthy,3=healthy" 30 \
  status_unchanged_after_dead_route_rejection

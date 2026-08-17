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
sg_write_rank_request "$run_dir/request-dp1.json" 1 10
cat >"$run_dir/scale-down-no-incident-request.json" <<'JSON'
{"instruction":"scale_down","params":{"timeout":180,"ranks":[1]}}
JSON
cat >"$run_dir/scale-down-empty-request.json" <<'JSON'
{"instruction":"scale_down","params":{"timeout":180,"ranks":[]}}
JSON
cat >"$run_dir/recover-request.json" <<'JSON'
{"instruction":"recover","params":{"timeout":180,"ranks":[1]}}
JSON

sg_launch_dp4_ft pause "$port" "$log_path" 0 "$trigger_file" "$done_file"
server_pgid="$ST_LAST_PGID"

st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$run_dir/request-dp0.json" "$run_dir/baseline-dp0.json" 200 baseline_dp0 180
sg_assert_known_output_ids \
  "$run_dir/baseline-dp0.json" "$(sg_precision_oracle_id 0)" \
  "$run_dir/baseline-dp0-precision.json"

st_http_json POST "http://127.0.0.1:${port}/fault_tolerance/apply" \
  "$run_dir/scale-down-no-incident-request.json" \
  "$run_dir/scale-down-no-incident-response.json" 400 \
  scale_down_requires_incident 60
sg_assert_ft_failure_message \
  "$run_dir/scale-down-no-incident-response.json" scale_down_requires_incident \
  scale_down_requires_incident_reason
st_http_json POST "http://127.0.0.1:${port}/fault_tolerance/apply" \
  "$run_dir/recover-request.json" "$run_dir/recover-before-disabled-response.json" \
  400 recover_before_disabled 60
sg_assert_ft_failure_message \
  "$run_dir/recover-before-disabled-response.json" \
  "unsupported instruction: recover" recover_before_disabled_reason
sg_wait_ft_status "$port" "$run_dir/status-after-steady-rejections.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 30 \
  status_unchanged_after_steady_rejections

sg_start_recoverable_fault "$trigger_file"
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$run_dir/request-dp0.json" "$run_dir/trigger-response.json" 503 \
  discard_current 180
sg_wait_recoverable_fault_done "$done_file" 1 60 recoverable_fault_done
sg_wait_ft_status "$port" "$run_dir/status-unhealthy.json" \
  "0=unhealthy,1=unhealthy,2=unhealthy,3=unhealthy" 120 status_unhealthy
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$run_dir/request-dp0.json" "$run_dir/admission-closed.json" 503 \
  admission_blocks_generate 60

st_http_json POST "http://127.0.0.1:${port}/fault_tolerance/apply" \
  "$run_dir/scale-down-empty-request.json" "$run_dir/scale-down-empty-response.json" \
  400 scale_down_empty 60
sg_assert_ft_failure_message \
  "$run_dir/scale-down-empty-response.json" scale_down_requires_ranks \
  scale_down_empty_reason
sg_wait_ft_status "$port" "$run_dir/status-after-empty-rejection.json" \
  "0=unhealthy,1=unhealthy,2=unhealthy,3=unhealthy" 30 \
  status_unchanged_after_empty_rejection

sg_apply_scale_down "$port" 1 \
  "$run_dir/scale-down-request.json" "$run_dir/scale-down-response.json"
sg_wait_ft_status "$port" "$run_dir/status-scaled-down.json" \
  "0=healthy,1=dead,2=healthy,3=healthy" 120 status_scaled_down
st_assert_process_count "$server_pgid" "sglang::scheduler" 3 \
  whole_dp1_shutdown_process_count

st_http_json POST "http://127.0.0.1:${port}/fault_tolerance/apply" \
  "$run_dir/recover-request.json" "$run_dir/recover-before-rejoin-response.json" \
  400 recover_before_rejoin 60
sg_assert_ft_failure_message \
  "$run_dir/recover-before-rejoin-response.json" \
  "unsupported instruction: recover" recover_before_rejoin_reason
sg_wait_ft_status "$port" "$run_dir/status-after-recover-rejection.json" \
  "0=healthy,1=dead,2=healthy,3=healthy" 30 \
  status_unchanged_after_recover_rejection
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$run_dir/request-dp1.json" "$run_dir/dead-dp1-response.json" 400 \
  dead_dp1_rejected 60
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$run_dir/request-dp0.json" "$run_dir/post-scale-down-dp0.json" 200 \
  post_scale_down_dp0 180
sg_assert_known_output_ids \
  "$run_dir/post-scale-down-dp0.json" "$(sg_precision_oracle_id 0)" \
  "$run_dir/post-scale-down-dp0-precision.json"

cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"
cp "$trigger_file" "$done_file" "$SERVER_TOOL_OUTPUT_ROOT/"

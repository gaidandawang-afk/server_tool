#!/usr/bin/env bash
set -Eeuo pipefail

source "$SERVER_TOOL_INPUT_ROOT/units/test_ops.sh"
source "$SERVER_TOOL_INPUT_ROOT/units/sglang_ft_ops.sh"

readonly port="$PORT_BASE"
readonly run_dir="$SERVER_TOOL_WORK_ROOT/case"
readonly log_path="$SERVER_TOOL_OUTPUT_ROOT/server.log"
readonly request_dp0="$run_dir/request-dp0.json"
readonly stream_request_dp0="$run_dir/stream-request-dp0.json"
readonly incident_state_schema="${SGLANG_FT_INCIDENT_STATE_SCHEMA:-self-pause}"
server_pgid=""
stream_pid=""

export SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS="${SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS:-384}"
export SGLANG_FT_MEM_FRACTION_STATIC="${SGLANG_FT_MEM_FRACTION_STATIC:-0.45}"

cleanup() {
  local original_code="$?"
  trap - EXIT
  set +e
  if [[ -n "$stream_pid" ]]; then
    st_stop_owned_pid "$stream_pid" stream_request_cleanup
  fi
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
sg_write_rank_request "$request_dp0" 0 10
sg_write_stream_rank_request "$stream_request_dp0" 0 64

sg_launch_dp4_ft pause "$port" "$log_path"
server_pgid="$ST_LAST_PGID"
st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "$request_dp0" "$run_dir/baseline-dp0.json" 200 baseline_dp0 180
sg_assert_known_output_ids \
  "$run_dir/baseline-dp0.json" \
  "$(sg_precision_oracle_id 0)" \
  "$run_dir/baseline-dp0-precision.json"

case "$incident_state_schema" in
  self-pause)
    declare -a incident_states=(
      "0=unhealthy,1=dead,2=unhealthy,3=unhealthy"
      "0=unhealthy,1=dead,2=dead,3=unhealthy"
      "0=unhealthy,1=dead,2=dead,3=dead"
    )
    ;;
  legacy-paused)
    declare -a incident_states=(
      "0=paused,1=dead,2=paused,3=paused"
      "0=paused,1=dead,2=dead,3=paused"
      "0=paused,1=dead,2=dead,3=dead"
    )
    ;;
  *)
    st_assert incident_state_schema false "self-pause|legacy-paused" \
      "$incident_state_schema"
    exit 1
    ;;
esac
printf 'incident_state_schema=%s\n' "$incident_state_schema" \
  >"$SERVER_TOOL_OUTPUT_ROOT/case-inputs.env"
declare -a healthy_states=(
  "0=healthy,1=dead,2=healthy,3=healthy"
  "0=healthy,1=dead,2=dead,3=healthy"
  "0=healthy,1=dead,2=dead,3=dead"
)

for target in 1 2 3; do
  index=$((target - 1))
  stream_output="$run_dir/inflight-dp${target}.jsonl"
  stream_error="$run_dir/inflight-dp${target}.stderr"
  sg_start_stream_request "$port" "$stream_request_dp0" \
    "$stream_output" "$stream_error" 60
  stream_pid="$ST_LAST_STREAM_PID"
  sg_wait_stream_decode_rank "$stream_output" 0 60
  st_kill_owned_process "$server_pgid" "_TP${target}_EP" KILL "kill_dp${target}"
  sg_wait_ft_status "$port" "$run_dir/status-dp${target}-incident.json" \
    "${incident_states[$index]}" 120 "status_dp${target}_incident"
  if kill -0 "$stream_pid" 2>/dev/null; then
    st_stop_owned_pid "$stream_pid" "inflight_dp${target}_request_cleanup"
  fi
  set +e
  wait "$stream_pid" 2>/dev/null
  set -e
  stream_pid=""
  st_assert_process_count "$server_pgid" "sglang::scheduler" "$((4 - target))" \
    "schedulers_after_dp${target}_kill"
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "$request_dp0" "$run_dir/admission-closed-dp${target}.json" 503 \
    "admission_closed_dp${target}" 90
  sg_apply_scale_down "$port" "$target" \
    "$run_dir/scale-down-dp${target}-request.json" \
    "$run_dir/scale-down-dp${target}-response.json"
  sg_wait_ft_status "$port" "$run_dir/status-dp${target}-scaled-down.json" \
    "${healthy_states[$index]}" 120 "status_dp${target}_scaled_down"
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "$request_dp0" "$run_dir/after-dp${target}-dp0.json" 200 \
    "after_dp${target}_dp0" 180
  sg_assert_known_output_ids \
    "$run_dir/after-dp${target}-dp0.json" \
    "$(sg_precision_oracle_id 0)" \
    "$run_dir/after-dp${target}-dp0-precision.json"
done

st_assert_process_count "$server_pgid" "sglang::scheduler" 1 schedulers_final
cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"

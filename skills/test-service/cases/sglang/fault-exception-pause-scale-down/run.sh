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
declare -a baselines=()
for rank in 0 1 2 3; do
  requests[$rank]="$run_dir/request-dp${rank}.json"
  baselines[$rank]="$run_dir/baseline-dp${rank}.json"
  sg_write_rank_request "${requests[$rank]}" "$rank" 10
done

sg_launch_dp4_ft pause "$port" "$log_path" 2 "$trigger_file" "$done_file"
server_pgid="$ST_LAST_PGID"

st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial
for rank in 0 1 2 3; do
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "${requests[$rank]}" "${baselines[$rank]}" 200 "baseline_dp${rank}" 90
done

sg_start_recoverable_fault "$trigger_file"
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[2]}" "$run_dir/trigger-response.json" 503 discard_current 180
sg_wait_recoverable_fault_done "$done_file" 1 60 recoverable_fault_done
sg_wait_ft_status "$port" "$run_dir/status-paused.json" \
  "0=paused,1=paused,2=paused,3=paused" 120 status_paused
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_paused

sg_apply_scale_down \
  "$port" 2 "$run_dir/scale-down-request.json" "$run_dir/scale-down-response.json"
sg_wait_ft_status "$port" "$run_dir/status-disabled.json" \
  "0=healthy,1=healthy,2=disabled,3=healthy" 120 status_disabled
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 logical_scale_down_keeps_scheduler
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[2]}" "$run_dir/disabled-dp2.json" 400 disabled_dp2_closed 180

for rank in 0 1 3; do
  response="$run_dir/after-scale-down-dp${rank}.json"
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "${requests[$rank]}" "$response" 200 "generate_dp${rank}" 90
  sg_assert_output_ids_equal \
    "${baselines[$rank]}" "$response" \
    "$run_dir/after-scale-down-dp${rank}-precision.json" \
    "after_scale_down_dp${rank}" 10
done
sg_wait_ft_status "$port" "$run_dir/status-disabled-persisted.json" \
  "0=healthy,1=healthy,2=disabled,3=healthy" 120 disabled_persists

resume_count_before="$(grep -c 'DPC forwarding FT command:.*command=resume' "$log_path" || true)"
sg_apply_recover \
  "$port" 2 "$run_dir/recover-request.json" "$run_dir/recover-response.json"
sg_wait_ft_status "$port" "$run_dir/status-recovered.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_recovered
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 recover_keeps_all_schedulers
sleep 2
resume_count_after="$(grep -c 'DPC forwarding FT command:.*command=resume' "$log_path" || true)"
if [[ "$resume_count_after" == "$resume_count_before" ]]; then
  st_assert recover_has_no_resume true "$resume_count_before" "$resume_count_after"
else
  st_assert recover_has_no_resume false "$resume_count_before" "$resume_count_after"
fi

st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[2]}" "$run_dir/recovered-dp2.json" 200 recovered_dp2 90
sg_assert_output_ids_equal \
  "${baselines[2]}" "$run_dir/recovered-dp2.json" \
  "$run_dir/recovered-dp2-precision.json" recovered_dp2 10

cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"
cp "$trigger_file" "$done_file" "$SERVER_TOOL_OUTPUT_ROOT/"

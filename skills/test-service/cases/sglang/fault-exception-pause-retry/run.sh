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
for rank in 0 1 2 3; do
  requests[$rank]="$run_dir/request-dp${rank}.json"
  sg_write_rank_request "${requests[$rank]}" "$rank" 10
done

sg_launch_dp4_ft pause "$port" "$log_path" 0 "$trigger_file" "$done_file"
server_pgid="$ST_LAST_PGID"

st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial

sg_start_recoverable_fault "$trigger_file"
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[0]}" "$run_dir/trigger-response.json" 503 discard_current 180
sg_wait_recoverable_fault_done "$done_file" 1 60 recoverable_fault_done
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_after_exception
sg_wait_ft_status "$port" "$run_dir/status-unhealthy.json" \
  "0=unhealthy,1=unhealthy,2=unhealthy,3=unhealthy" 120 status_unhealthy
st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[1]}" "$run_dir/admission-closed-response.json" 503 \
  admission_blocks_generate 180

eplb_count_before="$(grep -c 'EPLB due to' "$log_path" 2>/dev/null || true)"
sg_apply_retry "$port" "$run_dir/retry-request.json" "$run_dir/retry-response.json"
sg_wait_ft_status "$port" "$run_dir/status-after-retry.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_after_retry
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 retry_keeps_all_schedulers
eplb_count_after="$(grep -c 'EPLB due to' "$log_path" 2>/dev/null || true)"
if [[ "$eplb_count_after" == "$eplb_count_before" ]]; then
  st_assert retry_does_not_run_eplb true "$eplb_count_before" "$eplb_count_after"
else
  st_assert retry_does_not_run_eplb false "$eplb_count_before" "$eplb_count_after"
fi

for rank in 0 1 2 3; do
  response="$run_dir/after-retry-dp${rank}.json"
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "${requests[$rank]}" "$response" 200 "generate_dp${rank}" 180
done
sg_assert_known_output_ids \
  "$run_dir/after-retry-dp0.json" \
  "$(sg_precision_oracle_id 0)" \
  "$run_dir/after-retry-dp0-precision.json"
for rank in 1 2 3; do
  sg_assert_output_ids_equal \
    "$run_dir/after-retry-dp0.json" "$run_dir/after-retry-dp${rank}.json" \
    "$run_dir/after-retry-dp0-dp${rank}-precision.json" \
    "after_retry_dp0_dp${rank}" 10
done

cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"
cp "$trigger_file" "$done_file" "$SERVER_TOOL_OUTPUT_ROOT/"

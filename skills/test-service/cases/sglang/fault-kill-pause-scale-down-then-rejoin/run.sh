#!/usr/bin/env bash
set -Eeuo pipefail

source "$SERVER_TOOL_INPUT_ROOT/units/test_ops.sh"
source "$SERVER_TOOL_INPUT_ROOT/units/sglang_ft_ops.sh"

readonly base_port="$PORT_BASE"
readonly dist_init_addr="127.0.0.1:$((PORT_BASE + 4))"
readonly run_dir="$SERVER_TOOL_WORK_ROOT/case"
readonly resume_pattern="FT command dispatch:.*command=resume"
readonly dispatch_algorithm="${SGLANG_FT_EP_DISPATCH_ALGORITHM:-static}"
readonly deterministic_inference="${SGLANG_FT_DETERMINISTIC_INFERENCE:-1}"
readonly request_style="${SGLANG_FT_REJOIN_REQUEST_STYLE:-current-count10}"
declare -a node_pgids=()
declare -a node_logs=()
declare -a requests=()
request_tokens=""
request_text=""
oracle_id=""

cleanup() {
  local original_code="$?"
  local node pgid
  trap - EXIT
  set +e
  st_preserve_run_dir_files "$run_dir"
  for node in 0 1 2 3; do
    pgid="${node_pgids[$node]:-}"
    if [[ -n "$pgid" ]]; then
      st_stop_owned_pgid "$pgid" "node${node}_process_group_cleanup"
    fi
  done
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
case "$request_style" in
  current-count10)
    request_tokens=10
    request_text="Count upward slowly, writing one integer per line."
    ;;
  historical-count4)
    request_tokens=4
    request_text="Write one short sentence about reliable inference."
    oracle_id="qwen-fp8-reliable-inference-count4"
    ;;
  *)
    st_assert request_style false "current-count10|historical-count4" "$request_style"
    exit 1
    ;;
esac
{
  printf 'ep_dispatch_algorithm=%s\n' "$dispatch_algorithm"
  printf 'deterministic_inference=%s\n' "$deterministic_inference"
  printf 'request_style=%s\n' "$request_style"
  printf 'request_tokens=%s\n' "$request_tokens"
  printf 'request_text=%s\n' "$request_text"
} >"$SERVER_TOOL_OUTPUT_ROOT/case-inputs.env"
for rank in 0 1 2 3; do
  requests[$rank]="$run_dir/request-dp${rank}.json"
  sg_write_rank_request \
    "${requests[$rank]}" "$rank" "$request_tokens" "$request_text"
  node_logs[$rank]="$SERVER_TOOL_OUTPUT_ROOT/node${rank}.log"
done
sg_write_rank_request \
  "$run_dir/fault-trigger-request.json" 0 2 "$request_text"

for node in 0 1 2 3; do
  sg_launch_dp4_ft_rejoin_node pause "$((base_port + node))" \
    "${node_logs[$node]}" "$node" "$dist_init_addr" 0
  node_pgids[$node]="$ST_LAST_PGID"
done

st_wait_http_ready "$base_port" 600
for node in 1 2 3; do
  sg_wait_health_generate "$((base_port + node))" "${node_pgids[$node]}" 600 \
    "node${node}_health_generate"
done
sg_wait_ft_status "$base_port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
sg_assert_log_contains "${node_logs[0]}" \
  "ep_dispatch_algorithm='${dispatch_algorithm}'" launch_dispatch_algorithm
if [[ "$deterministic_inference" == 1 ]]; then
  expected_deterministic=True
else
  expected_deterministic=False
fi
sg_assert_log_contains "${node_logs[0]}" \
  "enable_deterministic_inference=${expected_deterministic}" \
  launch_deterministic_inference
for node in 0 1 2 3; do
  st_assert_process_count "${node_pgids[$node]}" "sglang::scheduler" 1 \
    "node${node}_scheduler_initial"
done

st_kill_owned_pgid "${node_pgids[3]}" node3_process_group_killed 30
node_pgids[3]=""
sg_issue_generate_fault_trigger \
  "$base_port" "$run_dir/fault-trigger-request.json" \
  "$run_dir/fault-trigger-response.json" mooncake_fault_trigger
sg_wait_ft_status "$base_port" "$run_dir/status-paused.json" \
  "0=paused,1=paused,2=paused,3=dead" 120 status_paused
st_http_json POST "http://127.0.0.1:${base_port}/generate" \
  "${requests[0]}" "$run_dir/paused-generate.json" 503 \
  paused_blocks_generate 180

sg_apply_scale_down "$base_port" 3 \
  "$run_dir/scale-down-request.json" "$run_dir/scale-down-response.json"
sg_wait_ft_status "$base_port" "$run_dir/status-scaled-down.json" \
  "0=healthy,1=healthy,2=healthy,3=dead" 120 status_scaled_down
for node in 0 1 2; do
  st_assert_process_count "${node_pgids[$node]}" "sglang::scheduler" 1 \
    "node${node}_scheduler_after_scale_down"
done
st_http_json POST "http://127.0.0.1:${base_port}/generate" \
  "${requests[3]}" "$run_dir/scaled-down-dp3.json" 400 \
  scaled_down_dp3_closed 60
st_http_json POST "http://127.0.0.1:${base_port}/generate" \
  "${requests[0]}" "$run_dir/after-scale-down-dp0.json" 200 \
  after_scale_down_dp0 180
sg_assert_output_ids \
  "$run_dir/after-scale-down-dp0.json" \
  "${oracle_id:-qwen-fp8-d4t4e4-count10-no-overlap-rank0-r128}" \
  "$run_dir/after-scale-down-dp0-precision.json"

resume_count_before="$(grep -Ec -- "$resume_pattern" "${node_logs[0]}" 2>/dev/null || true)"
sg_apply_recover "$base_port" 3 \
  "$run_dir/recover-request.json" "$run_dir/recover-response.json"
sg_wait_ft_status "$base_port" "$run_dir/status-after-inactive-recover.json" \
  "0=healthy,1=healthy,2=healthy,3=dead" 120 status_after_inactive_recover
st_http_json POST "http://127.0.0.1:${base_port}/generate" \
  "${requests[3]}" "$run_dir/after-inactive-recover-dp3.json" 400 \
  inactive_recover_keeps_dp3_closed 60
resume_count_after="$(grep -Ec -- "$resume_pattern" "${node_logs[0]}" 2>/dev/null || true)"
st_assert inactive_recover_no_duplicate_resume \
  "$([[ "$resume_count_after" == "$resume_count_before" ]] && echo true || echo false)" \
  "$resume_count_before" "$resume_count_after"
sg_assert_log_contains "${node_logs[0]}" \
  "Fault tolerance apply plan: instruction=recover (active_mask=\\[True, True, True, False\\] )?resume_targets=\\[\\] ranks=\\[3\\]" \
  inactive_recover_plan

node_logs[3]="$SERVER_TOOL_OUTPUT_ROOT/node3-rejoin.log"
sg_launch_dp4_ft_rejoin_node pause "$((base_port + 3))" \
  "${node_logs[3]}" 3 "$dist_init_addr" 1
node_pgids[3]="$ST_LAST_PGID"
sg_wait_scheduler_count "${node_pgids[3]}" 1 180 rejoin_scheduler
sg_wait_log_contains "${node_logs[3]}" \
  "Recovered rank joining Mooncake backend default_world" 180 rejoin_world_join
for node in 0 1 2; do
  sg_drive_generate_until_log \
    "$base_port" "${requests[$node]}" "${node_logs[$node]}" \
    "recover ranks \\[3\\] done" "$run_dir/recovery-drive-node${node}" 600 \
    "node${node}_recovery_observed"
done
sg_wait_ft_status "$base_port" "$run_dir/status-recovered.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_recovered
sg_wait_health_generate "$((base_port + 3))" "${node_pgids[3]}" 600 \
  node3_rejoined_health_generate

for rank in 3 0; do
  st_http_json POST "http://127.0.0.1:${base_port}/generate" \
    "${requests[$rank]}" "$run_dir/recovered-dp${rank}.json" 200 \
    "recovered_dp${rank}" 180
  sg_assert_output_ids \
    "$run_dir/recovered-dp${rank}.json" \
    "${oracle_id:-qwen-fp8-d4t4e4-count10-no-overlap-rank${rank}-r128}" \
    "$run_dir/recovered-dp${rank}-precision.json"
done

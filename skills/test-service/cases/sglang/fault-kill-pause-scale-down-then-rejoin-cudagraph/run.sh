#!/usr/bin/env bash
set -Eeuo pipefail

source "$SERVER_TOOL_INPUT_ROOT/units/test_ops.sh"
source "$SERVER_TOOL_INPUT_ROOT/units/sglang_ft_ops.sh"

export SGLANG_FT_CUDA_GRAPH_MODE=decode-only

readonly base_port="$PORT_BASE"
readonly dist_init_addr="127.0.0.1:$((PORT_BASE + 4))"
readonly run_dir="$SERVER_TOOL_WORK_ROOT/case"
readonly dispatch_algorithm="${SGLANG_FT_EP_DISPATCH_ALGORITHM:-static}"
readonly deterministic_inference="${SGLANG_FT_DETERMINISTIC_INFERENCE:-1}"
readonly request_style="${SGLANG_FT_REJOIN_REQUEST_STYLE:-current-count10}"
readonly request_tokens_override="${SGLANG_FT_REJOIN_MAX_TOKENS:-}"
readonly random_seed="${SGLANG_FT_RANDOM_SEED:-auto}"
readonly stream_request_dp0="$run_dir/stream-request-dp0.json"
readonly initial_node3_log="$SERVER_TOOL_OUTPUT_ROOT/node3.log"
declare -a node_pgids=()
declare -a node_logs=()
declare -a requests=()
request_tokens=""
request_text=""
oracle_id=""
stream_pid=""

cleanup() {
  local original_code="$?"
  local node pgid
  trap - EXIT
  set +e
  if [[ -n "$stream_pid" ]]; then
    st_stop_owned_pid "$stream_pid" stream_request_cleanup
  fi
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
    oracle_id="${SGLANG_FT_RELIABLE_ORACLE_ID:-qwen-fp8-reliable-inference-count4}"
    ;;
  *)
    st_assert request_style false "current-count10|historical-count4" "$request_style"
    exit 1
    ;;
esac
if [[ -n "$request_tokens_override" ]]; then
  if ! [[ "$request_tokens_override" =~ ^[1-9][0-9]*$ ]] ||
    (( request_tokens_override > 64 )); then
    st_assert request_tokens false "1..64" "$request_tokens_override"
    exit 1
  fi
  request_tokens="$request_tokens_override"
  oracle_id=""
fi
{
  printf 'cuda_graph_mode=%s\n' "$SGLANG_FT_CUDA_GRAPH_MODE"
  printf 'ep_dispatch_algorithm=%s\n' "$dispatch_algorithm"
  printf 'deterministic_inference=%s\n' "$deterministic_inference"
  printf 'request_style=%s\n' "$request_style"
  printf 'request_tokens=%s\n' "$request_tokens"
  printf 'request_text=%s\n' "$request_text"
  printf 'random_seed=%s\n' "$random_seed"
} >"$SERVER_TOOL_OUTPUT_ROOT/case-inputs.env"
for rank in 0 1 2 3; do
  requests[$rank]="$run_dir/request-dp${rank}.json"
  sg_write_rank_request \
    "${requests[$rank]}" "$rank" "$request_tokens" "$request_text"
  node_logs[$rank]="$SERVER_TOOL_OUTPUT_ROOT/node${rank}.log"
done
sg_write_stream_rank_request "$stream_request_dp0" 0 64 "$request_text"

for node in 0 1 2 3; do
  sg_launch_dp4_ft_rejoin_node pause "$((base_port + node))" \
    "${node_logs[$node]}" "$node" "$dist_init_addr" 0
  node_pgids[$node]="$ST_LAST_PGID"
done

for node in 0 1 2 3; do
  sg_wait_log_contains "${node_logs[$node]}" \
    "Using TCP host transport with intra-node NVLink" 180 \
    "node${node}_tcp_host_transport"
  sg_wait_log_contains "${node_logs[$node]}" \
    "Using Intra-Node NVLink transport" 30 \
    "node${node}_intra_node_nvlink_transport"
  sg_wait_log_contains "${node_logs[$node]}" \
    "Capture target decode CUDA graph end" 180 \
    "node${node}_initial_decode_graph_captured"
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
for node in 0 1 2 3; do
  st_assert_process_count "${node_pgids[$node]}" "sglang::scheduler" 1 \
    "node${node}_scheduler_initial"
done
st_http_json POST "http://127.0.0.1:${base_port}/generate" \
  "${requests[0]}" "$run_dir/baseline-inference.json" 200 \
  baseline_inference 600

sg_start_stream_request "$base_port" "$stream_request_dp0" \
  "$run_dir/inflight-dp3.jsonl" "$run_dir/inflight-dp3.stderr" 60
stream_pid="$ST_LAST_STREAM_PID"
sg_wait_stream_decode_rank "$run_dir/inflight-dp3.jsonl" 0 60
node3_owner_pgid="${node_pgids[3]}"
st_stop_owned_pgid "$node3_owner_pgid" node3_owner_process_group_killed
st_wait_process_group_exit "$node3_owner_pgid" 30 \
  node3_owner_process_group_confirmed_gone
node_pgids[3]=""
declare -a incident_states=(
  "0=unhealthy,1=unhealthy,2=unhealthy,3=dead"
  "0=unhealthy,1=unhealthy,2=healthy,3=dead"
  "0=unhealthy,1=healthy,2=unhealthy,3=dead"
  "0=healthy,1=unhealthy,2=unhealthy,3=dead"
  "0=unhealthy,1=healthy,2=healthy,3=dead"
  "0=healthy,1=unhealthy,2=healthy,3=dead"
  "0=healthy,1=healthy,2=unhealthy,3=dead"
  "0=healthy,1=healthy,2=healthy,3=dead"
)
sg_wait_ft_status "$base_port" "$run_dir/status-incident.json" \
  "$(IFS='|'; echo "${incident_states[*]}")" 120 status_incident
if kill -0 "$stream_pid" 2>/dev/null; then
  st_stop_owned_pid "$stream_pid" inflight_dp3_request_cleanup
fi
set +e
wait "$stream_pid" 2>/dev/null
set -e
stream_pid=""
st_http_json POST "http://127.0.0.1:${base_port}/generate" \
  "${requests[0]}" "$run_dir/admission-closed.json" 503 \
  admission_blocks_generate 180

sg_apply_scale_down "$base_port" 3 \
  "$run_dir/scale-down-request.json" "$run_dir/scale-down-response.json" \
  "$run_dir/status-scaled-down.json" "0=healthy,1=healthy,2=healthy,3=dead" \
  120 status_scaled_down
for node in 0 1 2; do
  st_assert_process_count "${node_pgids[$node]}" "sglang::scheduler" 1 \
    "node${node}_scheduler_after_scale_down"
done
st_http_json POST "http://127.0.0.1:${base_port}/generate" \
  "${requests[3]}" "$run_dir/scaled-down-dp3.json" 503 \
  scaled_down_dp3_closed 60
sg_assert_inactive_route_error \
  "$run_dir/scaled-down-dp3.json" 3 scaled_down_dp3_inactive_error
st_http_json POST "http://127.0.0.1:${base_port}/generate" \
  "${requests[0]}" "$run_dir/after-scale-down-dp0.json" 200 \
  after_scale_down_dp0 180
if [[ -n "$request_tokens_override" ]]; then
  sg_assert_output_ids_equal \
    "$run_dir/after-scale-down-dp0.json" \
    "$run_dir/after-scale-down-dp0.json" \
    "$run_dir/after-scale-down-dp0-token-count.json" \
    after_scale_down_dp0_token_count "$request_tokens"
else
  sg_assert_known_output_ids \
    "$run_dir/after-scale-down-dp0.json" \
    "${oracle_id:-$(sg_precision_oracle_id 0)}" \
    "$run_dir/after-scale-down-dp0-precision.json"
fi

node_logs[3]="$SERVER_TOOL_OUTPUT_ROOT/node3-rejoin.log"
sg_launch_dp4_ft_rejoin_node pause "$((base_port + 3))" \
  "${node_logs[3]}" 3 "$dist_init_addr" 1
node_pgids[3]="$ST_LAST_PGID"
sg_wait_scheduler_count "${node_pgids[3]}" 1 180 rejoin_scheduler
sg_wait_ft_status "$base_port" "$run_dir/status-rejoin-waiting.json" \
  "0=healthy,1=healthy,2=healthy,3=dead" 30 rejoin_waits_for_native_recovery
st_http_json POST "http://127.0.0.1:${base_port}/generate" \
  "${requests[3]}" "$run_dir/rejoin-waiting-dp3.json" 503 \
  rejoin_waiting_keeps_dp3_closed 60
sg_assert_inactive_route_error "$run_dir/rejoin-waiting-dp3.json" 3 \
  rejoin_waiting_dp3_inactive_error
sg_wait_log_contains "${node_logs[3]}" \
  "Prepared deferred local EP fast path: fallback=False" 180 \
  replacement_native_fast_path
sg_wait_log_contains "${node_logs[3]}" \
  "Capture target decode CUDA graph end" 180 \
  replacement_decode_graph_captured
sg_wait_log_contains "${node_logs[3]}" \
  "Elastic EP recovery join process groups begin" 180 \
  rejoin_ready_for_recovery_forward

sg_drive_generate_until_log \
  "$base_port" "${requests[0]}" "${node_logs[0]}" \
  "recover ranks \\[3\\] done" "$run_dir/recovery-stage-drive" 600 \
  recovery_done_observed
for node in 1 2; do
  sg_wait_log_contains "${node_logs[$node]}" \
    "recover ranks \\[3\\] done" 180 "node${node}_recovery_done"
done
st_http_json POST "http://127.0.0.1:${base_port}/generate" \
  "${requests[0]}" "$run_dir/recovery-eplb-forward.json" 200 \
  recovery_eplb_second_forward 600
sg_wait_ft_status "$base_port" "$run_dir/status-recovered.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_auto_recovered
sg_wait_health_generate "$((base_port + 3))" "${node_pgids[3]}" 600 \
  node3_rejoined_health_generate

for rank in 3 0; do
  st_http_json POST "http://127.0.0.1:${base_port}/generate" \
    "${requests[$rank]}" "$run_dir/recovered-dp${rank}.json" 200 \
    "recovered_dp${rank}" 180
  if [[ -n "$request_tokens_override" ]]; then
    sg_assert_output_ids_equal \
      "$run_dir/after-scale-down-dp0.json" \
      "$run_dir/recovered-dp${rank}.json" \
      "$run_dir/recovered-dp${rank}-precision.json" \
      "recovered_dp${rank}" "$request_tokens"
  else
    sg_assert_known_output_ids \
      "$run_dir/recovered-dp${rank}.json" \
      "${oracle_id:-$(sg_precision_oracle_id "$rank")}" \
      "$run_dir/recovered-dp${rank}-precision.json"
  fi
done

sg_assert_log_contains "${node_logs[0]}" "cuda graph: True" \
  primary_decode_graph_replay
for graph_node in 0 1 2; do
  graph_count="$(grep -c "Capture target decode CUDA graph begin" \
    "${node_logs[$graph_node]}" || true)"
  if [[ "$graph_count" == 1 ]]; then
    st_assert "survivor_node${graph_node}_capture_count" true 1 "$graph_count"
  else
    st_assert "survivor_node${graph_node}_capture_count" false 1 "$graph_count"
  fi
done
replacement_graph_count="$(grep -c "Capture target decode CUDA graph begin" \
  "${node_logs[3]}" || true)"
if [[ "$replacement_graph_count" == 1 ]]; then
  st_assert replacement_capture_count true 1 "$replacement_graph_count"
else
  st_assert replacement_capture_count false 1 "$replacement_graph_count"
fi
replacement_capture_end_line="$(grep -n -m1 \
  "Capture target decode CUDA graph end" "${node_logs[3]}" | cut -d: -f1)"
replacement_join_begin_line="$(grep -n -m1 \
  "Elastic EP recovery join process groups begin" "${node_logs[3]}" | cut -d: -f1)"
if [[ -n "$replacement_capture_end_line" && -n "$replacement_join_begin_line" &&
  "$replacement_capture_end_line" -lt "$replacement_join_begin_line" ]]; then
  st_assert replacement_capture_before_join true true \
    "capture=$replacement_capture_end_line join=$replacement_join_begin_line"
else
  st_assert replacement_capture_before_join false true \
    "capture=${replacement_capture_end_line:-missing} join=${replacement_join_begin_line:-missing}"
fi
for graph_log in "${node_logs[0]}" "${node_logs[1]}" "${node_logs[2]}" \
  "$initial_node3_log" "${node_logs[3]}"; do
  if grep -Eq "CUDA_ERROR_ILLEGAL_ADDRESS|an illegal memory access|_fallback_dispatch" \
    "$graph_log"; then
    st_assert "graph_log_clean_$(basename "$graph_log")" false true forbidden_error
  else
    st_assert "graph_log_clean_$(basename "$graph_log")" true true clean
  fi
done

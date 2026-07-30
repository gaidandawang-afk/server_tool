#!/usr/bin/env bash
set -Eeuo pipefail

source "$SERVER_TOOL_INPUT_ROOT/units/test_ops.sh"
source "$SERVER_TOOL_INPUT_ROOT/units/sglang_ft_ops.sh"

readonly base_port="$PORT_BASE"
readonly dist_init_addr="127.0.0.1:$((PORT_BASE + 4))"
readonly run_dir="$SERVER_TOOL_WORK_ROOT/case"
declare -a node_pgids=()
declare -a node_logs=()
declare -a requests=()

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
for rank in 0 1 2 3; do
  requests[$rank]="$run_dir/request-dp${rank}.json"
  sg_write_rank_request "${requests[$rank]}" "$rank" 10
  node_logs[$rank]="$SERVER_TOOL_OUTPUT_ROOT/node${rank}.log"
done
sg_write_rank_request "$run_dir/fault-trigger-request.json" 0 2

for node in 0 1 2 3; do
  sg_launch_dp4_ft_rejoin_node continue "$((base_port + node))" \
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
for node in 0 1 2 3; do
  st_assert_process_count "${node_pgids[$node]}" "sglang::scheduler" 1 \
    "node${node}_scheduler_initial"
done

st_kill_owned_pgid "${node_pgids[3]}" node3_process_group_killed 30
node_pgids[3]=""
sg_issue_generate_fault_trigger \
  "$base_port" "$run_dir/fault-trigger-request.json" \
  "$run_dir/fault-trigger-response.json" mooncake_fault_trigger
sg_wait_ft_status "$base_port" "$run_dir/status-degraded.json" \
  "0=healthy,1=healthy,2=healthy,3=dead" 120 status_degraded
for node in 0 1 2; do
  st_assert_process_count "${node_pgids[$node]}" "sglang::scheduler" 1 \
    "node${node}_scheduler_survives"
  st_http_json POST "http://127.0.0.1:${base_port}/generate" \
    "${requests[$node]}" "$run_dir/degraded-dp${node}.json" 200 \
    "degraded_dp${node}" 180
done

node_logs[3]="$SERVER_TOOL_OUTPUT_ROOT/node3-rejoin.log"
sg_launch_dp4_ft_rejoin_node continue "$((base_port + 3))" \
  "${node_logs[3]}" 3 "$dist_init_addr" 1
node_pgids[3]="$ST_LAST_PGID"
sg_wait_scheduler_count "${node_pgids[3]}" 1 180 rejoin_scheduler
sg_wait_log_contains "${node_logs[3]}" \
  "Recovered rank joining Mooncake backend default_world" 180 rejoin_world_join
sg_wait_ft_status "$base_port" "$run_dir/status-before-recovery.json" \
  "0=healthy,1=healthy,2=healthy,3=dead" 120 status_before_recovery
st_http_json POST "http://127.0.0.1:${base_port}/generate" \
  "${requests[3]}" "$run_dir/before-recovery-dp3.json" 400 \
  before_recovery_dp3_closed 60

for node in 0 1 2; do
  sg_drive_generate_until_log \
    "$base_port" "${requests[$node]}" "${node_logs[$node]}" \
    "recover ranks \[3\] done" "$run_dir/recovery-drive-node${node}" 600 \
    "node${node}_recovery_observed"
done
sg_wait_ft_status "$base_port" "$run_dir/status-recovered.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_recovered
sg_wait_health_generate "$((base_port + 3))" "${node_pgids[3]}" 600 \
  node3_rejoined_health_generate

for rank in 0 1 2 3; do
  st_http_json POST "http://127.0.0.1:${base_port}/generate" \
    "${requests[$rank]}" "$run_dir/recovered-dp${rank}.json" 200 \
    "recovered_dp${rank}" 180
  sg_assert_output_ids \
    "$run_dir/recovered-dp${rank}.json" \
    "$(sg_precision_oracle_id "$rank")" \
    "$run_dir/recovered-dp${rank}-precision.json"
done

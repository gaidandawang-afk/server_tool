#!/usr/bin/env bash
set -Eeuo pipefail

source "$SERVER_TOOL_INPUT_ROOT/units/test_ops.sh"
source "$SERVER_TOOL_INPUT_ROOT/units/sglang_ft_ops.sh"

: "${MODEL_PATH:?}"
: "${SGLANG_KERNEL_ROOT:?}"
: "${SGLANG_KERNEL_VERSION:?}"
: "${MOONCAKE_ROOT:?}"
: "${MOONCAKE_VERSION:?}"

readonly port="$PORT_BASE"
readonly run_dir="$SERVER_TOOL_WORK_ROOT/case"
readonly log_path="$SERVER_TOOL_OUTPUT_ROOT/server.log"
readonly expected_kernel_version="$SGLANG_KERNEL_VERSION"
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
export PYTHONNOUSERSITE=1
export PYTHONPATH="$SERVER_TOOL_PROJECT_ROOT/python:$SGLANG_KERNEL_ROOT:$MOONCAKE_ROOT"
export CUDA_VISIBLE_DEVICES="$GPU_IDS"
export MOONCAKE_PROTOCOL=tcp
export MOONCAKE_EP_FORCE_FALLBACK=1
export SGLANG_ENABLE_TP_MEMORY_INBALANCE_CHECK=false

st_record_python_package \
  sglang-kernel sgl_kernel "$expected_kernel_version" "$SGLANG_KERNEL_ROOT" \
  fp8_blockwise_scaled_mm
st_record_python_package \
  mooncake-transfer-engine-cuda13 mooncake "$MOONCAKE_VERSION" "$MOONCAKE_ROOT"

declare -a requests=()
for rank in 0 1 2 3; do
  requests[$rank]="$run_dir/request-dp${rank}.json"
  sg_write_rank_request "${requests[$rank]}" "$rank" 10
done

cd "$SERVER_TOOL_PROJECT_ROOT"
st_launch_process_group "$log_path" \
  python3 -u -m sglang.launch_server \
  --model-path "$MODEL_PATH" \
  --host 0.0.0.0 \
  --port "$port" \
  --dtype auto \
  --load-format auto \
  --tp-size 4 \
  --dp-size 4 \
  --enable-dp-attention \
  --enable-dp-lm-head \
  --ep-size 4 \
  --moe-dense-tp-size 1 \
  --moe-a2a-backend mooncake \
  --enable-eplb \
  --eplb-algorithm elasticity_aware \
  --ep-dispatch-algorithm dynamic \
  --ep-num-redundant-experts 128 \
  --elastic-ep-backend mooncake \
  --deepep-mode low_latency \
  --moe-runner-backend deep_gemm \
  --attention-backend triton \
  --sampling-backend pytorch \
  --mem-fraction-static 0.75 \
  --max-running-requests 8 \
  --max-total-tokens 4096 \
  --context-length 1024 \
  --watchdog-timeout 120 \
  --disable-custom-all-reduce \
  --enable-deterministic-inference \
  --disable-overlap-schedule \
  --disable-cuda-graph \
  --disable-piecewise-cuda-graph \
  --skip-server-warmup \
  --enable-fault-tolerance \
  --fault-tolerance-on-error-strategy pause \
  --fault-tolerance-timeout 600
server_pgid="$ST_LAST_PGID"

st_wait_http_ready "$port" 180
sg_wait_ft_status "$port" "$run_dir/status-initial.json" \
  "0=healthy,1=healthy,2=healthy,3=healthy" 120 status_initial
st_assert_process_count "$server_pgid" "sglang::scheduler" 4 schedulers_initial

st_kill_owned_process "$server_pgid" "_TP1_EP" KILL kill_dp1
sg_wait_ft_status "$port" "$run_dir/status-paused.json" \
  "0=paused,1=dead,2=paused,3=paused" 120 status_paused
st_assert_process_count "$server_pgid" "sglang::scheduler" 3 schedulers_after_kill

st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[0]}" "$run_dir/paused-generate.json" 503 paused_blocks_generate 180
sg_apply_scale_down "$port" 1 "$run_dir/scale-down-request.json" "$run_dir/scale-down-response.json"
sg_wait_ft_status "$port" "$run_dir/status-scaled-down.json" \
  "0=healthy,1=dead,2=healthy,3=healthy" 120 status_scaled_down
st_assert_process_count "$server_pgid" "sglang::scheduler" 3 logical_scale_down_retains_survivors

st_http_json POST "http://127.0.0.1:${port}/generate" \
  "${requests[1]}" "$run_dir/scaled-down-dp1.json" 400 scaled_down_dp1_closed 180
for rank in 0 2 3; do
  response="$run_dir/after-scale-down-dp${rank}.json"
  st_http_json POST "http://127.0.0.1:${port}/generate" \
    "${requests[$rank]}" "$response" 200 "generate_dp${rank}" 180
  sg_assert_output_ids \
    "$response" "qwen-fp8-d4t4e4-count10-no-overlap-rank${rank}-r128" \
    "$run_dir/after-scale-down-dp${rank}-precision.json"
done

cp "$run_dir"/*.json "$SERVER_TOOL_OUTPUT_ROOT/"

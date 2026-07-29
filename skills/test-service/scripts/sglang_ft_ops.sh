#!/usr/bin/env bash

sg_prepare_dp4_runtime() {
  : "${MODEL_PATH:?}"
  : "${SGLANG_KERNEL_ROOT:?}"
  : "${SGLANG_KERNEL_VERSION:?}"
  : "${MOONCAKE_ROOT:?}"
  : "${MOONCAKE_VERSION:?}"

  export PYTHONNOUSERSITE=1
  export PYTHONPATH="$SERVER_TOOL_PROJECT_ROOT/python:$SGLANG_KERNEL_ROOT:$MOONCAKE_ROOT"
  export CUDA_VISIBLE_DEVICES="$GPU_IDS"
  export MOONCAKE_PROTOCOL=tcp
  export MOONCAKE_EP_FORCE_FALLBACK=1
  export SGLANG_ENABLE_TP_MEMORY_INBALANCE_CHECK=false

  st_record_python_package \
    sglang-kernel sgl_kernel "$SGLANG_KERNEL_VERSION" "$SGLANG_KERNEL_ROOT" \
    fp8_blockwise_scaled_mm
  st_record_python_package \
    mooncake-transfer-engine-cuda13 mooncake "$MOONCAKE_VERSION" "$MOONCAKE_ROOT"
}

sg_launch_dp4_ft() {
  local strategy="$1"
  local port="$2"
  local log_path="$3"
  case "$strategy" in
    pause|continue) ;;
    *)
      st_assert launch_strategy false "pause|continue" "$strategy"
      return 1
      ;;
  esac

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
    --fault-tolerance-on-error-strategy "$strategy" \
    --fault-tolerance-timeout 600
}

sg_write_rank_request() {
  local path="$1"
  local rank="$2"
  local max_tokens="${3:-10}"
  python3 - "$path" "$rank" "$max_tokens" <<'PY'
import json
import sys

path, rank, max_tokens = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "text": "Count upward slowly, writing one integer per line.",
            "sampling_params": {"max_new_tokens": max_tokens, "temperature": 0.0},
            "routed_dp_rank": rank,
        },
        handle,
        separators=(",", ":"),
    )
    handle.write("\n")
PY
}

sg_wait_ft_status() {
  local port="$1"
  local output="$2"
  local expected="$3"
  local timeout_sec="$4"
  local label="$5"
  local end=$((SECONDS + timeout_sec))
  local actual=""
  while (( SECONDS < end )); do
    if curl -fsS --connect-timeout 2 --max-time 5 \
      "http://127.0.0.1:${port}/fault_tolerance/status" -o "$output"; then
      actual="$(python3 - "$output" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(",".join(f"{item['rank']}={item['state']}" for item in data["ranks"]))
PY
)"
      if [[ "$actual" == "$expected" ]]; then
        st_assert "$label" true "$expected" "$actual"
        return 0
      fi
    fi
    sleep 1
  done
  st_assert "$label" false "$expected" "${actual:-unavailable}"
}

sg_apply_scale_down() {
  local port="$1"
  local rank="$2"
  local request="$3"
  local response="$4"
  python3 - "$request" "$rank" <<'PY'
import json
import sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(
        {
            "fault_tolerance_instruction": "scale_down",
            "fault_tolerance_timeout": 180,
            "fault_tolerance_params": {"ranks": [int(sys.argv[2])]},
        },
        handle,
        separators=(",", ":"),
    )
    handle.write("\n")
PY
  st_http_json POST "http://127.0.0.1:${port}/fault_tolerance/apply" \
    "$request" "$response" 200 scale_down_apply 180
}

sg_apply_retry() {
  local port="$1"
  local request="$2"
  local response="$3"
  python3 - "$request" <<'PY'
import json
import sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(
        {
            "fault_tolerance_instruction": "retry",
            "fault_tolerance_timeout": 180,
        },
        handle,
        separators=(",", ":"),
    )
    handle.write("\n")
PY
  st_http_json POST "http://127.0.0.1:${port}/fault_tolerance/apply" \
    "$request" "$response" 200 retry_apply 180
}

sg_assert_log_count() {
  local log_path="$1"
  local pattern="$2"
  local expected="$3"
  local label="$4"
  local actual
  actual="$(grep -c -- "$pattern" "$log_path" 2>/dev/null || true)"
  if [[ "$actual" == "$expected" ]]; then
    st_assert "$label" true "$expected" "$actual"
  else
    st_assert "$label" false "$expected" "$actual"
  fi
}

sg_assert_output_ids() {
  local response="$1"
  local oracle_id="$2"
  local result="$3"
  set +e
  python3 "$SERVER_TOOL_INPUT_ROOT/units/assert_output_ids.py" \
    --registry "$SERVER_TOOL_INPUT_ROOT/assets/precision_oracles.json" \
    --oracle "$oracle_id" --response "$response" --output "$result"
  local code=$?
  set -e
  if [[ "$code" -eq 0 ]]; then
    st_assert "precision_${oracle_id}" true exact_token_ids matched
  else
    st_assert "precision_${oracle_id}" false exact_token_ids mismatch
  fi
}

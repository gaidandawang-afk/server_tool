#!/usr/bin/env bash

sg_prepare_dp4_runtime() {
  : "${MODEL_PATH:?}"
  : "${SGLANG_KERNEL_ROOT:?}"
  : "${SGLANG_KERNEL_VERSION:?}"
  : "${MOONCAKE_ROOT:?}"
  : "${MOONCAKE_VERSION:?}"
  : "${MOONCAKE_WHEEL:?}"
  : "${MOONCAKE_SOURCE_COMMIT:?}"
  : "${MOONCAKE_WHEEL_SHA256:?}"

  export PYTHONNOUSERSITE=1
  export PYTHONPATH="$SERVER_TOOL_PROJECT_ROOT/python:$SGLANG_KERNEL_ROOT:$MOONCAKE_ROOT"
  export CUDA_VISIBLE_DEVICES="$GPU_IDS"
  export MC_FORCE_TCP=1
  export MOONCAKE_PROTOCOL=tcp
  export MOONCAKE_EP_FORCE_FALLBACK=1
  export NCCL_IB_DISABLE=1
  export SGLANG_HOST_IP=127.0.0.1
  export HOST_IP=127.0.0.1
  export SGLANG_JIT_DEEPGEMM_PRECOMPILE=0
  export SGLANG_OPT_USE_JIT_EP_ACTIVATION=0
  export SGLANG_FT_TP_SIZE=4
  export SGLANG_FT_DP_SIZE=4
  export SGLANG_FT_EP_SIZE=4
  export SGLANG_ENABLE_TP_MEMORY_INBALANCE_CHECK=false
  export TORCHINDUCTOR_CACHE_DIR=/data2/iws/cache/torch/inductor
  export TRITON_CACHE_DIR=/data2/iws/cache/triton
  mkdir -p "$TORCHINDUCTOR_CACHE_DIR" "$TRITON_CACHE_DIR"

  local sg_mooncake_wheel_sha256
  sg_mooncake_wheel_sha256="$(sha256sum "$MOONCAKE_WHEEL" | awk '{print $1}')"
  if [[ "$sg_mooncake_wheel_sha256" == "$MOONCAKE_WHEEL_SHA256" ]]; then
    st_assert mooncake_wheel_sha256 true "$MOONCAKE_WHEEL_SHA256" \
      "$sg_mooncake_wheel_sha256"
  else
    st_assert mooncake_wheel_sha256 false "$MOONCAKE_WHEEL_SHA256" \
      "$sg_mooncake_wheel_sha256"
  fi

  st_record_python_package \
    sglang-kernel sgl_kernel "$SGLANG_KERNEL_VERSION" "$SGLANG_KERNEL_ROOT" \
    fp8_blockwise_scaled_mm
  st_record_python_package \
    mooncake-transfer-engine-cuda13 mooncake "$MOONCAKE_VERSION" "$MOONCAKE_ROOT"
}

sg_launch_dp4_ft() {
  local sg_strategy="$1"
  local sg_port="$2"
  local sg_log_path="$3"
  case "$sg_strategy" in
    pause|continue) ;;
    *)
      st_assert launch_strategy false "pause|continue" "$sg_strategy"
      return 1
      ;;
  esac

  cd "$SERVER_TOOL_PROJECT_ROOT"
  st_launch_process_group "$sg_log_path" \
    python3 -u -m sglang.launch_server \
    --model-path "$MODEL_PATH" \
    --host 0.0.0.0 \
    --port "$sg_port" \
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
    --disable-overlap-schedule \
    --disable-cuda-graph \
    --disable-piecewise-cuda-graph \
    --skip-server-warmup \
    --enable-fault-tolerance \
    --fault-tolerance-on-error-strategy "$sg_strategy" \
    --fault-tolerance-timeout 600
}

sg_write_rank_request() {
  local sg_request_path="$1"
  local sg_rank="$2"
  local sg_max_tokens="${3:-10}"
  python3 - "$sg_request_path" "$sg_rank" "$sg_max_tokens" <<'PY'
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
  local sg_port="$1"
  local sg_output="$2"
  local sg_expected="$3"
  local sg_timeout_sec="$4"
  local sg_label="$5"
  local sg_end=$((SECONDS + sg_timeout_sec))
  local sg_actual=""
  while (( SECONDS < sg_end )); do
    if curl -fsS --connect-timeout 2 --max-time 5 \
      "http://127.0.0.1:${sg_port}/fault_tolerance/status" -o "$sg_output"; then
      sg_actual="$(python3 - "$sg_output" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(",".join(f"{item['rank']}={item['state']}" for item in data["ranks"]))
PY
)"
      if [[ "$sg_actual" == "$sg_expected" ]]; then
        st_assert "$sg_label" true "$sg_expected" "$sg_actual"
        return 0
      fi
    fi
    sleep 1
  done
  st_assert "$sg_label" false "$sg_expected" "${sg_actual:-unavailable}"
}

sg_apply_scale_down() {
  local sg_port="$1"
  local sg_rank="$2"
  local sg_request="$3"
  local sg_response="$4"
  python3 - "$sg_request" "$sg_rank" <<'PY'
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
  st_http_json POST "http://127.0.0.1:${sg_port}/fault_tolerance/apply" \
    "$sg_request" "$sg_response" 200 scale_down_apply 180
}

sg_apply_retry() {
  local sg_port="$1"
  local sg_request="$2"
  local sg_response="$3"
  python3 - "$sg_request" <<'PY'
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
  st_http_json POST "http://127.0.0.1:${sg_port}/fault_tolerance/apply" \
    "$sg_request" "$sg_response" 200 retry_apply 180
}

sg_assert_log_count() {
  local sg_log_path="$1"
  local sg_pattern="$2"
  local sg_expected="$3"
  local sg_label="$4"
  local sg_actual
  sg_actual="$(grep -c -- "$sg_pattern" "$sg_log_path" 2>/dev/null || true)"
  if [[ "$sg_actual" == "$sg_expected" ]]; then
    st_assert "$sg_label" true "$sg_expected" "$sg_actual"
  else
    st_assert "$sg_label" false "$sg_expected" "$sg_actual"
  fi
}

sg_assert_output_ids() {
  local sg_response="$1"
  local sg_oracle_id="$2"
  local sg_result="$3"
  set +e
  python3 "$SERVER_TOOL_INPUT_ROOT/units/assert_output_ids.py" \
    --registry "$SERVER_TOOL_INPUT_ROOT/assets/precision_oracles.json" \
    --oracle "$sg_oracle_id" --response "$sg_response" --output "$sg_result"
  local sg_code=$?
  set -e
  if [[ "$sg_code" -eq 0 ]]; then
    st_assert "precision_${sg_oracle_id}" true exact_token_ids matched
  else
    st_assert "precision_${sg_oracle_id}" false exact_token_ids mismatch
  fi
}

sg_assert_output_ids_equal() {
  local sg_expected_response="$1"
  local sg_actual_response="$2"
  local sg_result="$3"
  local sg_label="$4"
  local sg_token_limit="${5:-10}"
  set +e
  python3 - "$sg_expected_response" "$sg_actual_response" "$sg_result" \
    "$sg_label" "$sg_token_limit" <<'PY'
import json
import sys

expected_path, actual_path, output_path, label, limit_raw = sys.argv[1:]
limit = int(limit_raw)


def output_ids(path):
    value = json.load(open(path, encoding="utf-8"))
    if isinstance(value, list):
        if len(value) != 1:
            raise ValueError(f"{path}: expected one response")
        value = value[0]
    return value.get("output_ids", [])


expected = output_ids(expected_path)
actual = output_ids(actual_path)
accurate = (
    len(expected) >= limit
    and len(actual) >= limit
    and expected[:limit] == actual[:limit]
)
result = {
    "schema_version": "server-tool.precision-pair.v1",
    "label": label,
    "accurate": accurate,
    "comparison_token_limit": limit,
    "expected_output_ids_compared": expected[:limit],
    "actual_output_ids_compared": actual[:limit],
    "expected_token_count": len(expected),
    "actual_token_count": len(actual),
}
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(result, handle, indent=2, sort_keys=True)
    handle.write("\n")
print(json.dumps(result, sort_keys=True))
raise SystemExit(0 if accurate else 1)
PY
  local sg_code=$?
  set -e
  if [[ "$sg_code" -eq 0 ]]; then
    st_assert "precision_${sg_label}" true "first_${sg_token_limit}_output_ids" matched
  else
    st_assert "precision_${sg_label}" false "first_${sg_token_limit}_output_ids" mismatch
  fi
}

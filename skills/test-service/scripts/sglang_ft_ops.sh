#!/usr/bin/env bash

sg_prepare_ft_runtime() {
  local sg_tp_size="$1"
  local sg_dp_size="$2"
  local sg_ep_size="$3"
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
  export SGLANG_FT_TP_SIZE="$sg_tp_size"
  export SGLANG_FT_DP_SIZE="$sg_dp_size"
  export SGLANG_FT_EP_SIZE="$sg_ep_size"
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

sg_prepare_dp4_runtime() {
  sg_prepare_ft_runtime 4 4 4
}

sg_launch_ft() {
  local sg_strategy="$1"
  local sg_port="$2"
  local sg_log_path="$3"
  local sg_tp_size="$4"
  local sg_dp_size="$5"
  local sg_ep_size="$6"
  local sg_fault_ranks="${7:-}"
  local sg_trigger_file="${8:-}"
  local sg_done_file="${9:-}"
  local sg_redundant_experts="${SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS:-128}"
  local sg_mem_fraction_static="${SGLANG_FT_MEM_FRACTION_STATIC:-0.75}"
  case "$sg_strategy" in
    pause|continue) ;;
    *)
      st_assert launch_strategy false "pause|continue" "$sg_strategy"
      return 1
      ;;
  esac

  if [[ -n "$sg_fault_ranks" ]]; then
    : "${sg_trigger_file:?recoverable fault trigger file is required}"
    : "${sg_done_file:?recoverable fault done file is required}"
    test ! -e "$sg_trigger_file"
    test ! -e "$sg_done_file"
    export SGLANG_TEST_FT_RECOVERABLE_FAULT_RANK="$sg_fault_ranks"
    export SGLANG_TEST_FT_RECOVERABLE_FAULT_FILE="$sg_trigger_file"
    export SGLANG_TEST_FT_RECOVERABLE_FAULT_DONE_FILE="$sg_done_file"
    export SGLANG_FT_INJECT_DIR="$SERVER_TOOL_INPUT_ROOT/assets/recoverable_inject"
    export PYTHONPATH="$SGLANG_FT_INJECT_DIR:$PYTHONPATH"
  fi

  cd "$SERVER_TOOL_PROJECT_ROOT"
  st_launch_process_group "$sg_log_path" \
    python3 -u -m sglang.launch_server \
    --model-path "$MODEL_PATH" \
    --host 0.0.0.0 \
    --port "$sg_port" \
    --dtype auto \
    --load-format auto \
    --tp-size "$sg_tp_size" \
    --dp-size "$sg_dp_size" \
    --enable-dp-attention \
    --enable-dp-lm-head \
    --ep-size "$sg_ep_size" \
    --moe-dense-tp-size 1 \
    --moe-a2a-backend mooncake \
    --enable-eplb \
    --eplb-algorithm elasticity_aware \
    --ep-dispatch-algorithm dynamic \
    --ep-num-redundant-experts "$sg_redundant_experts" \
    --elastic-ep-backend mooncake \
    --deepep-mode low_latency \
    --moe-runner-backend deep_gemm \
    --attention-backend triton \
    --sampling-backend pytorch \
    --mem-fraction-static "$sg_mem_fraction_static" \
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
    --fault-tolerance-on-error-strategy "$sg_strategy" \
    --fault-tolerance-timeout 600
}

sg_launch_dp4_ft() {
  local sg_strategy="$1"
  local sg_port="$2"
  local sg_log_path="$3"
  local sg_fault_ranks="${4:-}"
  local sg_trigger_file="${5:-}"
  local sg_done_file="${6:-}"
  sg_launch_ft "$sg_strategy" "$sg_port" "$sg_log_path" 4 4 4 \
    "$sg_fault_ranks" "$sg_trigger_file" "$sg_done_file"
}

sg_launch_dp4_ft_rejoin_node() {
  local sg_strategy="$1"
  local sg_port="$2"
  local sg_log_path="$3"
  local sg_node_rank="$4"
  local sg_dist_init_addr="$5"
  local sg_rejoin="${6:-0}"
  local sg_redundant_experts="${SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS:-128}"
  local -a sg_rejoin_args=()
  local -a sg_warmup_args=()
  case "$sg_strategy" in
    pause|continue) ;;
    *)
      st_assert launch_strategy false "pause|continue" "$sg_strategy"
      return 1
      ;;
  esac
  if ! [[ "$sg_node_rank" =~ ^[0-3]$ ]]; then
    st_assert launch_node_rank false "0..3" "$sg_node_rank"
    return 1
  fi
  case "$sg_rejoin" in
    0) ;;
    1)
      sg_rejoin_args+=(--elastic-ep-rejoin)
      sg_warmup_args+=(--skip-server-warmup)
      ;;
    *)
      st_assert launch_rejoin false "0|1" "$sg_rejoin"
      return 1
      ;;
  esac

  cd "$SERVER_TOOL_PROJECT_ROOT"
  st_launch_process_group "$sg_log_path" \
    python3 -u -m sglang.launch_server \
    --model-path "$MODEL_PATH" \
    --host 127.0.0.1 \
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
    --ep-dispatch-algorithm static \
    --ep-num-redundant-experts "$sg_redundant_experts" \
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
    "${sg_warmup_args[@]}" \
    --enable-fault-tolerance \
    --fault-tolerance-on-error-strategy "$sg_strategy" \
    --fault-tolerance-timeout 600 \
    --nnodes 4 \
    --node-rank "$sg_node_rank" \
    --base-gpu-id "$sg_node_rank" \
    --dist-init-addr "$sg_dist_init_addr" \
    "${sg_rejoin_args[@]}"
}

sg_launch_dp4_mooncake_noft() {
  local sg_port="$1"
  local sg_log_path="$2"
  local sg_redundant_experts="${SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS:-128}"
  local sg_mem_fraction_static="${SGLANG_FT_MEM_FRACTION_STATIC:-0.75}"
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
    --ep-num-redundant-experts "$sg_redundant_experts" \
    --elastic-ep-backend mooncake \
    --deepep-mode low_latency \
    --moe-runner-backend deep_gemm \
    --attention-backend triton \
    --sampling-backend pytorch \
    --mem-fraction-static "$sg_mem_fraction_static" \
    --max-running-requests 8 \
    --max-total-tokens 4096 \
    --context-length 1024 \
    --watchdog-timeout 120 \
    --disable-custom-all-reduce \
    --disable-overlap-schedule \
    --disable-cuda-graph \
    --disable-piecewise-cuda-graph \
    --skip-server-warmup
}

sg_wait_health_generate() {
  local sg_port="$1"
  local sg_pgid="$2"
  local sg_timeout_sec="$3"
  local sg_label="$4"
  local sg_end=$((SECONDS + sg_timeout_sec))
  while (( SECONDS < sg_end )); do
    if ! ps -g "$sg_pgid" >/dev/null 2>&1; then
      st_assert "$sg_label" false "HTTP 200" process_group_exited
      return
    fi
    if curl -fsS --connect-timeout 5 --max-time 15 \
      "http://127.0.0.1:${sg_port}/health_generate" >/dev/null; then
      st_assert "$sg_label" true "HTTP 200" "HTTP 200"
      return
    fi
    sleep 2
  done
  st_assert "$sg_label" false "HTTP 200 within ${sg_timeout_sec}s" timeout
}

sg_wait_log_contains() {
  local sg_log_path="$1"
  local sg_pattern="$2"
  local sg_timeout_sec="$3"
  local sg_label="$4"
  local sg_end=$((SECONDS + sg_timeout_sec))
  while (( SECONDS < sg_end )); do
    if grep -Eq -- "$sg_pattern" "$sg_log_path" 2>/dev/null; then
      st_assert "$sg_label" true present present
      return
    fi
    sleep 1
  done
  st_assert "$sg_label" false present absent
}

sg_wait_scheduler_count() {
  local sg_pgid="$1"
  local sg_expected="$2"
  local sg_timeout_sec="$3"
  local sg_label="$4"
  local sg_end=$((SECONDS + sg_timeout_sec))
  local sg_actual=0
  while (( SECONDS < sg_end )); do
    sg_actual="$(
      st_process_group_rows "$sg_pgid" |
        grep -c -- "sglang::scheduler" || true
    )"
    if [[ "$sg_actual" == "$sg_expected" ]]; then
      st_assert "$sg_label" true "$sg_expected" "$sg_actual"
      return
    fi
    sleep 1
  done
  st_assert "$sg_label" false "$sg_expected" "$sg_actual"
}

sg_issue_generate_fault_trigger() {
  local sg_port="$1"
  local sg_request="$2"
  local sg_response="$3"
  local sg_label="$4"
  local sg_http_code="" sg_rc=0
  set +e
  sg_http_code="$(
    timeout 31s curl -sS --connect-timeout 5 --max-time 30 \
      -H "Content-Type: application/json" --data-binary "@$sg_request" \
      -o "$sg_response" -w "%{http_code}" \
      "http://127.0.0.1:${sg_port}/generate"
  )"
  sg_rc="$?"
  set -e
  case "$sg_rc" in
    0|28|124)
      st_assert "$sg_label" true issued "curl_rc=$sg_rc HTTP=${sg_http_code:-none}"
      ;;
    *)
      st_assert "$sg_label" false issued "curl_rc=$sg_rc HTTP=${sg_http_code:-none}"
      ;;
  esac
}

sg_drive_generate_until_log() {
  local sg_port="$1"
  local sg_request="$2"
  local sg_log_path="$3"
  local sg_pattern="$4"
  local sg_output_prefix="$5"
  local sg_timeout_sec="$6"
  local sg_label="$7"
  local sg_end=$((SECONDS + sg_timeout_sec))
  local sg_attempt=0 sg_http_code="" sg_rc=0
  while (( SECONDS < sg_end )); do
    if grep -Eq -- "$sg_pattern" "$sg_log_path" 2>/dev/null; then
      st_assert "$sg_label" true observed observed
      return
    fi
    sg_attempt=$((sg_attempt + 1))
    set +e
    sg_http_code="$(
      curl -sS --connect-timeout 5 --max-time 30 \
        -H "Content-Type: application/json" --data-binary "@$sg_request" \
        -o "${sg_output_prefix}-${sg_attempt}.json" -w "%{http_code}" \
        "http://127.0.0.1:${sg_port}/generate"
    )"
    sg_rc="$?"
    set -e
    st_log "RECOVERY_DRIVE label=$sg_label attempt=$sg_attempt curl_rc=$sg_rc HTTP=${sg_http_code:-none}"
    sleep 1
  done
  st_assert "$sg_label" false observed timeout
}

sg_find_scheduler_pid_by_global_rank() {
  local sg_pgid="$1"
  local sg_rank="$2"
  st_process_group_rows "$sg_pgid" |
    awk -v pattern="_TP${sg_rank}_EP" 'index($0, pattern) {print $1; exit}'
}

sg_kill_scheduler_global_rank() {
  local sg_pgid="$1"
  local sg_rank="$2"
  local sg_label="$3"
  st_kill_owned_process "$sg_pgid" "_TP${sg_rank}_EP" KILL "$sg_label"
}

sg_start_recoverable_fault() {
  local sg_trigger_file="$1"
  test ! -e "$sg_trigger_file"
  : >"$sg_trigger_file"
  st_assert recoverable_fault_trigger true created created
}

sg_wait_recoverable_fault_done() {
  local sg_done_file="$1"
  local sg_expected_count="$2"
  local sg_timeout_sec="$3"
  local sg_label="$4"
  local sg_end=$((SECONDS + sg_timeout_sec))
  local sg_actual=0
  while (( SECONDS < sg_end )); do
    sg_actual="$(grep -c '^pid=' "$sg_done_file" 2>/dev/null || true)"
    if (( sg_actual >= sg_expected_count )); then
      st_assert "$sg_label" true "$sg_expected_count" "$sg_actual"
      return 0
    fi
    sleep 1
  done
  st_assert "$sg_label" false "$sg_expected_count" "$sg_actual"
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

sg_write_stream_rank_request() {
  local sg_request_path="$1"
  local sg_rank="$2"
  local sg_max_tokens="${3:-64}"
  python3 - "$sg_request_path" "$sg_rank" "$sg_max_tokens" <<'PY'
import json
import sys

path, rank, max_tokens = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "text": "Count upward slowly, writing one integer per line.",
            "sampling_params": {"max_new_tokens": max_tokens, "temperature": 0.0},
            "stream": True,
            "routed_dp_rank": rank,
        },
        handle,
        separators=(",", ":"),
    )
    handle.write("\n")
PY
}

sg_start_stream_request() {
  local sg_port="$1"
  local sg_request="$2"
  local sg_output="$3"
  local sg_error="$4"
  local sg_max_time_sec="${5:-60}"
  : >"$sg_output"
  : >"$sg_error"
  timeout "$((sg_max_time_sec + 5))s" curl -N -sS \
    --connect-timeout 5 --max-time "$sg_max_time_sec" \
    -H "Content-Type: application/json" --data-binary "@$sg_request" \
    -w $'\nHTTP_CODE:%{http_code}\n' \
    "http://127.0.0.1:${sg_port}/generate" \
    >"$sg_output" 2>"$sg_error" &
  ST_LAST_STREAM_PID="$!"
  export ST_LAST_STREAM_PID
  st_log "STREAM_START pid=$ST_LAST_STREAM_PID request=$sg_request"
}

sg_wait_stream_decode_rank() {
  local sg_output="$1"
  local sg_rank="$2"
  local sg_timeout_sec="$3"
  local sg_end=$((SECONDS + sg_timeout_sec))
  while (( SECONDS < sg_end )); do
    if python3 - "$sg_output" "$sg_rank" <<'PY'
import re
import sys

text = open(sys.argv[1], errors="replace").read()
rank = int(sys.argv[2])
if f'"dp_rank":{rank}' not in text:
    raise SystemExit(1)
if not re.search(r'"completion_tokens":[1-9]', text):
    raise SystemExit(1)
PY
    then
      st_assert "stream_decode_rank${sg_rank}" true observed observed
      return
    fi
    sleep 1
  done
  st_assert "stream_decode_rank${sg_rank}" false observed timeout
}

sg_capture_interrupted_stream_contract() {
  local sg_pid="$1"
  local sg_output="$2"
  local sg_error="$3"
  local sg_contract="$4"
  local sg_timeout_sec="$5"
  local sg_label="$6"
  local sg_end=$((SECONDS + sg_timeout_sec))
  local sg_forced=false
  local sg_rc=0
  while (( SECONDS < sg_end )); do
    if ! kill -0 "$sg_pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  if kill -0 "$sg_pid" 2>/dev/null; then
    st_stop_owned_pid "$sg_pid" "${sg_label}_stream_cleanup"
    sg_forced=true
  fi
  set +e
  wait "$sg_pid"
  sg_rc="$?"
  set -e
  set +e
  python3 - "$sg_output" "$sg_error" "$sg_contract" "$sg_rc" "$sg_forced" <<'PY'
import json
import re
import sys

out_path, err_path, contract_path, rc_raw, forced_raw = sys.argv[1:]
text = open(out_path, errors="replace").read()
error = open(err_path, errors="replace").read()
matches = re.findall(r"HTTP_CODE:(\d+)", text)
http_code = int(matches[-1]) if matches else None
decoder = json.JSONDecoder()
index = 0
complete_final = False
while index < len(text):
    start = text.find("{", index)
    if start < 0:
        break
    try:
        value, index = decoder.raw_decode(text, start)
    except json.JSONDecodeError:
        index = start + 1
        continue
    if not isinstance(value, dict):
        continue
    meta = value.get("meta_info")
    finish_reason = (
        meta.get("finish_reason") if isinstance(meta, dict) else value.get("finish_reason")
    )
    if finish_reason is not None:
        complete_final = True
        break
lower_error = error.lower()
if "timed out" in lower_error:
    error_kind = "timeout"
elif "connection" in lower_error or "transfer closed" in lower_error:
    error_kind = "connection_interrupted"
elif error.strip():
    error_kind = "curl_error"
else:
    error_kind = ""
rc = int(rc_raw)
forced = forced_raw == "true"
contract = {
    "curl_rc": rc,
    "http_code": http_code,
    "stream_process_finished": not forced,
    "normal_stream_end": rc == 0,
    "complete_final_response": complete_final,
    "error_kind": error_kind,
    "output_bytes": len(text.encode()),
    "error_bytes": len(error.encode()),
}
passed = (
    not forced
    and rc != 0
    and http_code == 200
    and not complete_final
    and contract["output_bytes"] > 0
    and error_kind in {"timeout", "connection_interrupted", "curl_error"}
)
contract["pass"] = passed
with open(contract_path, "w", encoding="utf-8") as handle:
    json.dump(contract, handle, indent=2, sort_keys=True)
    handle.write("\n")
print(json.dumps(contract, sort_keys=True))
raise SystemExit(0 if passed else 1)
PY
  local sg_code="$?"
  set -e
  if [[ "$sg_code" -eq 0 ]]; then
    st_assert "$sg_label" true interrupted interrupted
  else
    st_assert "$sg_label" false interrupted invalid_contract
  fi
}

sg_capture_completed_stream_contract() {
  local sg_pid="$1"
  local sg_output="$2"
  local sg_error="$3"
  local sg_contract="$4"
  local sg_final_response="$5"
  local sg_timeout_sec="$6"
  local sg_expected_tokens="$7"
  local sg_label="$8"
  local sg_end=$((SECONDS + sg_timeout_sec))
  local sg_forced=false
  local sg_rc=0
  while (( SECONDS < sg_end )); do
    if ! kill -0 "$sg_pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  if kill -0 "$sg_pid" 2>/dev/null; then
    st_stop_owned_pid "$sg_pid" "${sg_label}_stream_timeout_cleanup"
    sg_forced=true
  fi
  set +e
  wait "$sg_pid"
  sg_rc="$?"
  set -e
  set +e
  python3 - "$sg_output" "$sg_error" "$sg_contract" "$sg_final_response" \
    "$sg_rc" "$sg_forced" "$sg_expected_tokens" <<'PY'
import json
import re
import sys

(
    out_path,
    err_path,
    contract_path,
    final_path,
    rc_raw,
    forced_raw,
    expected_raw,
) = sys.argv[1:]
text = open(out_path, errors="replace").read()
error = open(err_path, errors="replace").read()
matches = re.findall(r"HTTP_CODE:(\d+)", text)
decoder = json.JSONDecoder()
index = 0
events = 0
final = None
while index < len(text):
    start = text.find("{", index)
    if start < 0:
        break
    try:
        value, index = decoder.raw_decode(text, start)
    except json.JSONDecodeError:
        index = start + 1
        continue
    if not isinstance(value, dict):
        continue
    events += 1
    meta = value.get("meta_info")
    if isinstance(meta, dict) and meta.get("finish_reason") is not None:
        final = value
expected_tokens = int(expected_raw)
contract = {
    "curl_rc": int(rc_raw),
    "http_code": int(matches[-1]) if matches else None,
    "stream_process_finished": forced_raw != "true",
    "event_count": events,
    "complete_final_response": final is not None,
    "finish_reason": final.get("meta_info", {}).get("finish_reason") if final else None,
    "completion_tokens": final.get("meta_info", {}).get("completion_tokens") if final else None,
    "output_id_count": len(final.get("output_ids", [])) if final else 0,
    "error": error,
}
contract["pass"] = (
    contract["stream_process_finished"]
    and contract["curl_rc"] == 0
    and contract["http_code"] == 200
    and contract["complete_final_response"]
    and contract["completion_tokens"] == expected_tokens
    and contract["output_id_count"] == expected_tokens
)
with open(contract_path, "w", encoding="utf-8") as handle:
    json.dump(contract, handle, indent=2, sort_keys=True)
    handle.write("\n")
if final is not None:
    with open(final_path, "w", encoding="utf-8") as handle:
        json.dump(final, handle, indent=2, sort_keys=True)
        handle.write("\n")
print(json.dumps(contract, sort_keys=True))
raise SystemExit(0 if contract["pass"] else 1)
PY
  local sg_code="$?"
  set -e
  if [[ "$sg_code" -eq 0 ]]; then
    st_assert "$sg_label" true complete complete
  else
    st_assert "$sg_label" false complete incomplete
  fi
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
  sg_apply_scale_down_ranks "$sg_port" "$sg_rank" "$sg_request" "$sg_response"
}

sg_apply_scale_down_ranks() {
  local sg_port="$1"
  local sg_ranks="$2"
  local sg_request="$3"
  local sg_response="$4"
  python3 - "$sg_request" "$sg_ranks" <<'PY'
import json
import sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(
        {
            "fault_tolerance_instruction": "scale_down",
            "fault_tolerance_timeout": 180,
            "fault_tolerance_params": {
                "ranks": [int(value) for value in sys.argv[2].split(",")]
            },
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

sg_apply_recover() {
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
            "fault_tolerance_instruction": "recover",
            "fault_tolerance_timeout": 180,
            "fault_tolerance_params": {"ranks": [int(sys.argv[2])]},
        },
        handle,
        separators=(",", ":"),
    )
    handle.write("\n")
PY
  st_http_json POST "http://127.0.0.1:${sg_port}/fault_tolerance/apply" \
    "$sg_request" "$sg_response" 200 recover_apply 180
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

sg_assert_log_contains() {
  local sg_log_path="$1"
  local sg_pattern="$2"
  local sg_label="$3"
  if grep -Eq -- "$sg_pattern" "$sg_log_path"; then
    st_assert "$sg_label" true present present
  else
    st_assert "$sg_label" false present absent
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

#!/usr/bin/env bash

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

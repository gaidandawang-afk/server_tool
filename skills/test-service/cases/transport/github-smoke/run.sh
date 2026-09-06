#!/usr/bin/env bash
set -euo pipefail
export CUDA_VISIBLE_DEVICES=""
python3 - <<'PY'
import hashlib, json, os, pathlib, subprocess
output = pathlib.Path(os.environ['SERVER_TOOL_OUTPUT_ROOT'])
actual = subprocess.check_output(['git', '-C', os.environ['SERVER_TOOL_PROJECT_ROOT'], 'rev-parse', 'HEAD'], text=True).strip()
expected = os.environ['SERVER_TOOL_EXPECTED_HEAD']
payload = b'server-tool-github-smoke\n' * 4096
(output / 'payload.bin').write_bytes(payload)
records = [{'label': 'source_commit', 'pass': actual == expected, 'expected': expected, 'actual': actual},
           {'label': 'payload_written', 'pass': (output / 'payload.bin').read_bytes() == payload, 'sha256': hashlib.sha256(payload).hexdigest()}]
(output / 'assertions.jsonl').write_text(''.join(json.dumps(item) + '\n' for item in records))
assert all(item['pass'] for item in records)
print('github smoke passed')
PY

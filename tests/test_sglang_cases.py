import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CASE_ROOT = REPO_ROOT / "skills" / "test-service" / "cases" / "sglang"
ORACLE_PATH = (
    REPO_ROOT
    / "skills"
    / "test-service"
    / "assets"
    / "sglang"
    / "precision_oracles.json"
)


class SGLangCaseContractTests(unittest.TestCase):
    def test_four_gpu_index_contains_all_sixteen_suite_identifiers(self):
        index = (CASE_ROOT / "INDEX.md").read_text(encoding="utf-8")
        identifiers = re.findall(r"`(fault_[a-z0-9_]+\.sh)`", index)
        self.assertEqual(len(identifiers), 16)
        self.assertEqual(len(set(identifiers)), 16)

    def test_implemented_cases_have_complete_contracts(self):
        implemented = (
            "fault-kill-continue-status-only",
            "fault-kill-pause-retry",
            "fault-kill-pause-scale-down",
            "fault-rejection-contracts",
            "fault-exception-continue-discard-resume",
            "fault-exception-pause-retry-timeout",
        )
        for case in implemented:
            with self.subTest(case=case):
                case_root = CASE_ROOT / case
                self.assertTrue((case_root / "TEST.md").is_file())
                self.assertTrue((case_root / "run.sh").is_file())
                test_text = (case_root / "TEST.md").read_text(encoding="utf-8")
                run_text = (case_root / "run.sh").read_text(encoding="utf-8")
                self.assertIn("--repeat 2", test_text)
                self.assertIn("assertions", test_text)
                self.assertNotRegex(run_text, r"REMOTE_AGENT|remote-agent")

    def test_default_precision_oracles_exist_and_cases_use_resolver(self):
        registry = json.loads(ORACLE_PATH.read_text(encoding="utf-8"))
        oracle_ids = {entry["id"] for entry in registry["entries"]}
        for rank in range(4):
            self.assertIn(
                f"qwen-fp8-d4t4e4-count10-no-overlap-rank{rank}-r128",
                oracle_ids,
            )
            self.assertIn(
                "deepseek-v2-lite-chat-bf16-d4t4e4-count10-no-overlap-"
                f"rank{rank}-r64",
                oracle_ids,
            )
        for run_sh in CASE_ROOT.glob("*/run.sh"):
            text = run_sh.read_text(encoding="utf-8")
            self.assertNotRegex(
                text,
                r"qwen-fp8-d4t4e4-count10-no-overlap-rank(?:[0-3]|\$\{rank\})-r128",
            )

    def test_shared_launcher_ignores_callers_readonly_port(self):
        common = REPO_ROOT / "skills" / "test-service" / "scripts" / "test_ops.sh"
        unit = REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp).as_posix()
            command = f"""
set -Eeuo pipefail
readonly port=6220
readonly log_path={output!r}/readonly-scope.log
export SERVER_TOOL_PROJECT_ROOT=.
export SERVER_TOOL_OUTPUT_ROOT={output!r}
export MODEL_PATH=/unused/model
source {common.as_posix()!r}
setsid() {{ "$@"; }}
st_launch_process_group "$log_path" true
wait "$ST_LAST_PGID"
source {unit.as_posix()!r}
st_launch_process_group() {{ :; }}
sg_launch_dp4_ft continue "$port" "$log_path"
"""
            completed = subprocess.run(
                ["bash", "-c", command],
                text=True,
                capture_output=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_rejoin_launcher_supports_fixed_random_seed(self):
        unit = (
            REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        ).read_text(encoding="utf-8")
        self.assertIn('SGLANG_FT_RANDOM_SEED', unit)
        self.assertIn('sg_random_seed_args+=(--random-seed "$sg_random_seed")', unit)

    def test_launchers_support_profile_selected_moe_backend_and_bf16_dispatch(self):
        unit = (
            REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        ).read_text(encoding="utf-8")
        self.assertEqual(
            unit.count(
                'local sg_moe_runner_backend="${SGLANG_FT_MOE_RUNNER_BACKEND:-deep_gemm}"'
            ),
            3,
        )
        self.assertEqual(
            unit.count('--moe-runner-backend "$sg_moe_runner_backend"'),
            3,
        )
        self.assertIn('case "${SGLANG_DEEPEP_BF16_DISPATCH:-0}" in', unit)

    def test_kernel_required_symbol_is_profile_selected_with_legacy_default(self):
        unit = (
            REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        ).read_text(encoding="utf-8")
        self.assertIn(
            'SGLANG_KERNEL_REQUIRED_SYMBOL:-fp8_blockwise_scaled_mm',
            unit,
        )
        self.assertIn('"$sg_kernel_required_symbol"', unit)

    def test_precision_oracle_id_uses_profile_family_and_redundancy(self):
        unit = REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        command = f"""
set -Eeuo pipefail
source {unit.as_posix()!r}
test "$(sg_precision_oracle_id 2)" = \
  "qwen-fp8-d4t4e4-count10-no-overlap-rank2-r128"
export SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS=64
export SGLANG_FT_PRECISION_ORACLE_FAMILY=deepseek-v2-lite-chat-bf16-d4t4e4-count10-no-overlap
test "$(sg_precision_oracle_id 3)" = \
  "deepseek-v2-lite-chat-bf16-d4t4e4-count10-no-overlap-rank3-r64"
"""
        completed = subprocess.run(
            ["bash", "-c", command],
            text=True,
            capture_output=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)


if __name__ == "__main__":
    unittest.main()

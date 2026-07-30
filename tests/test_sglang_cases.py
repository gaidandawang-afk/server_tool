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
    def test_four_gpu_index_contains_all_fourteen_suite_identifiers(self):
        index = (CASE_ROOT / "INDEX.md").read_text(encoding="utf-8")
        identifiers = re.findall(r"`(fault_[a-z0-9_]+\.sh)`", index)
        self.assertEqual(len(identifiers), 14)
        self.assertEqual(len(set(identifiers)), 14)

    def test_implemented_cases_have_complete_contracts(self):
        implemented = (
            "fault-kill-continue-status-only",
            "fault-kill-pause-retry",
            "fault-kill-pause-scale-down",
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

    def test_precision_oracle_references_exist(self):
        registry = json.loads(ORACLE_PATH.read_text(encoding="utf-8"))
        oracle_ids = {entry["id"] for entry in registry["entries"]}
        for run_sh in CASE_ROOT.glob("*/run.sh"):
            text = run_sh.read_text(encoding="utf-8")
            referenced = re.findall(r'"(qwen-[a-z0-9${}_-]+-r128)"', text)
            for oracle_id in referenced:
                if "${rank}" in oracle_id:
                    expanded = [oracle_id.replace("${rank}", str(rank)) for rank in (0, 2, 3)]
                else:
                    expanded = [oracle_id]
                for item in expanded:
                    with self.subTest(script=run_sh.parent.name, oracle=item):
                        self.assertIn(item, oracle_ids)

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


if __name__ == "__main__":
    unittest.main()

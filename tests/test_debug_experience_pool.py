import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "skills" / "debug-service" / "scripts" / "manage_pool.py"
POOL_PATH = REPO_ROOT / "skills" / "debug-service" / "pool.json"

SPEC = importlib.util.spec_from_file_location("debug_experience_pool", SCRIPT_PATH)
assert SPEC and SPEC.loader
experience_pool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(experience_pool)


class DebugExperiencePoolTests(unittest.TestCase):
    def test_manager_owns_repository_local_pool(self):
        self.assertEqual(experience_pool.POOL_PATH, POOL_PATH)

    def test_migrated_pool_has_unique_ids_and_new_scale_down_entry(self):
        pool_text = POOL_PATH.read_text(encoding="utf-8")
        entries = json.loads(pool_text)
        ids = [entry["id"] for entry in entries]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("exp-048", ids)
        next_number = max(int(entry_id.removeprefix("exp-")) for entry_id in ids) + 1
        self.assertEqual(experience_pool.next_entry_id(entries), f"exp-{next_number:03d}")
        self.assertTrue(
            all(entry["category"] in experience_pool.VALID_CATEGORIES for entry in entries)
        )
        self.assertNotIn("plugins/sglang/debug", pool_text)
        self.assertNotIn('"category": "remote-agent"', pool_text)

    def test_list_cli_reads_repository_local_pool(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "list", "--top", "1"],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertIn("exp-011", result.stdout)


if __name__ == "__main__":
    unittest.main()

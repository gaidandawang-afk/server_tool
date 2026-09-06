import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1] / "skills/test-service/scripts"


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


summary = load("summarize-result")
runner = load("run-case")


class ResultSummaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "output").mkdir()
        (self.root / "control").mkdir()

    def write(self, state="succeeded", code=0, assertions=None):
        (self.root / "control/state").write_text(state)
        (self.root / "control/exit_code").write_text(str(code))
        data = {"exit_code": code, "pass": True, "run_id": "task.run.1",
                "source": {"source_commit": "abc"},
                "assertions": assertions if assertions is not None else [{"pass": True}]}
        (self.root / "output/result.json").write_text(json.dumps(data))

    def test_terminal_success(self):
        self.write()
        value, code = summary.summarize(self.root)
        self.assertEqual((value["verdict"], code), ("PASS", 0))

    def test_running_snapshot_cannot_pass(self):
        self.write(state="running")
        self.assertEqual(summary.summarize(self.root)[1], 2)

    def test_missing_or_malformed_result_is_incomplete(self):
        self.assertEqual(summary.summarize(self.root)[1], 2)
        self.write()
        for invalid in ("{", "[]"):
            (self.root / "output/result.json").write_text(invalid)
            self.assertEqual(summary.summarize(self.root)[1], 2)

    def test_assertions_override_stale_pass_flag_and_are_bounded(self):
        self.write(assertions=[{"pass": False, "actual": "x" * 10000}] * 20)
        value, code = summary.summarize(self.root)
        self.assertEqual(code, 1)
        self.assertEqual(len(value["failed_assertions"]), 5)
        self.assertEqual(value["omitted_failures"], 15)
        self.assertLessEqual(len(value["failed_assertions"][0]["actual"]), 300)

    def test_exit_zero_without_assertions_is_incomplete(self):
        self.write(assertions=[])
        self.assertEqual(summary.summarize(self.root)[1], 2)

    def test_preparation_failure_needs_no_behavioral_assertions(self):
        self.write(state="failed", code=128, assertions=[])
        self.assertEqual(summary.summarize(self.root)[1], 1)

    def test_mixed_control_and_result_are_incomplete(self):
        self.write()
        (self.root / "control/exit_code").write_text("1")
        self.assertEqual(summary.summarize(self.root)[1], 2)


class ResumeTests(unittest.TestCase):
    def invoke(self, extra, call_results=None, fetch_code=0):
        argv = ["run-case", "--profile", "unused", "--case", "sglang/fault-exception-pause-retry",
                "--name", "existing", *extra]
        with patch.object(sys, "argv", argv), patch.object(
            runner.subprocess, "call", side_effect=call_results or [0, 0]
        ) as call, patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess(
            [], fetch_code, stdout="artifact-dir\n", stderr=""
        )) as fetch:
            code = runner.main()
        return code, [c.args[0] for c in call.call_args_list], fetch

    def test_resume_never_submits_even_if_wait_failed(self):
        code, commands, fetch = self.invoke(["--resume", "--summary", "--destination", "new-dir"], [1, 0])
        self.assertEqual(code, 0)
        self.assertEqual(commands[0][4], "wait")
        self.assertTrue(commands[1][1].endswith("summarize-result.py"))
        self.assertNotIn("run", [part for cmd in commands for part in cmd])
        self.assertIn("--destination", fetch.call_args.args[0])

    def test_fetch_failure_does_not_claim_result_or_resubmit(self):
        code, commands, _ = self.invoke(["--resume"], [0], fetch_code=2)
        self.assertEqual(code, 1)
        self.assertEqual(len(commands), 1)

    def test_resume_rejects_repetition(self):
        with self.assertRaises(SystemExit) as caught:
            self.invoke(["--resume", "--repeat", "2"])
        self.assertEqual(caught.exception.code, 2)

    def test_normal_run_submits_once_then_reports(self):
        code, commands, _ = self.invoke([], [0, 0, 0])
        self.assertEqual(code, 0)
        self.assertEqual(commands[0][4], "run")
        self.assertEqual(commands[1][4], "wait")


if __name__ == "__main__":
    unittest.main()

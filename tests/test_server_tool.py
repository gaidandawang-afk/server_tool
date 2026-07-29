import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "server_tool.py"
SPEC = importlib.util.spec_from_file_location("server_tool_cli", MODULE_PATH)
assert SPEC and SPEC.loader
server_tool = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = server_tool
SPEC.loader.exec_module(server_tool)


class ServerToolTests(unittest.TestCase):
    def test_remote_child_rejects_equal_and_escape(self):
        with self.assertRaises(server_tool.ToolError):
            server_tool.require_remote_child("/data2/iws/tasks", "/data2/iws/tasks", "task")
        with self.assertRaises(server_tool.ToolError):
            server_tool.require_remote_child("/data2/iws/other", "/data2/iws/tasks", "task")
        self.assertEqual(
            server_tool.require_remote_child(
                "/data2/iws/tasks/example", "/data2/iws/tasks", "task"
            ),
            "/data2/iws/tasks/example",
        )

    def test_attachment_rejects_remote_escape(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "run.sh"
            source.write_text("#!/bin/bash\n", encoding="utf-8")
            with self.assertRaises(server_tool.ToolError):
                server_tool.parse_attachment(f"{source}:../escape")

    def test_script_guard_rejects_broad_process_kill(self):
        with tempfile.TemporaryDirectory() as temp:
            script = Path(temp) / "bad.sh"
            script.write_text("#!/bin/bash\npkill python\n", encoding="utf-8")
            with self.assertRaises(server_tool.ToolError):
                server_tool.scan_script(script)

    def test_parser_exposes_short_connection_lifecycle(self):
        parser = server_tool.build_parser()
        for command in ("check", "run", "status", "logs", "wait", "fetch", "stop"):
            with self.subTest(command=command):
                args = ["--profile", "task.env", command]
                if command != "check":
                    args += ["--name", "case"]
                if command == "run":
                    args += ["--script", "run.sh"]
                self.assertEqual(parser.parse_args(args).command, command)

    def test_source_bundle_uses_named_branch_ref(self):
        class FakeProfile:
            local_repo = MODULE_PATH.parents[1]

            @staticmethod
            def require(key):
                if key == "LOCAL_BRANCH":
                    return server_tool.run_local(
                        ["git", "branch", "--show-current"], MODULE_PATH.parents[1]
                    )
                raise AssertionError(key)

        with tempfile.TemporaryDirectory() as temp:
            bundle = Path(temp) / "source.bundle"
            server_tool.create_source_bundle(FakeProfile(), bundle)
            heads = server_tool.run_local(["git", "bundle", "list-heads", str(bundle)], MODULE_PATH.parents[1])
            self.assertIn("refs/heads/", heads)


if __name__ == "__main__":
    unittest.main()

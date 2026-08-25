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
    def test_runtime_profile_exposes_model_specific_ft_settings(self):
        for key in (
            "SGLANG_KERNEL_REQUIRED_SYMBOL",
            "SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS",
            "SGLANG_FT_MEM_FRACTION_STATIC",
            "SGLANG_FT_MOE_RUNNER_BACKEND",
            "SGLANG_FT_MOONCAKE_TRANSPORT_MODE",
            "SGLANG_DEEPEP_BF16_DISPATCH",
            "SGLANG_FT_PRECISION_ORACLE_FAMILY",
            "SGLANG_FT_RELIABLE_ORACLE_ID",
        ):
            with self.subTest(key=key):
                self.assertIn(key, server_tool.RUNTIME_PROFILE_KEYS)

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

    def test_remote_project_reuse_probe_fails_closed(self):
        class FakeProfile:
            project_root = "/data2/iws/projects/example"

            @staticmethod
            def require(key):
                if key == "PROFILE_NAME":
                    return "example"
                raise AssertionError(key)

        command = server_tool.project_source_mode_command(FakeProfile(), "abc123")

        self.assertIn('rev-parse HEAD)" = abc123 &&', command)
        self.assertIn('status --porcelain)" && echo reuse', command)
        self.assertNotIn('status --porcelain)"; echo reuse', command)

    def test_input_hashes_include_attached_tree(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "nested").mkdir()
            payload = root / "nested" / "unit.sh"
            payload.write_text("echo stable\n", encoding="utf-8")
            hashes = server_tool.input_hashes([root])
            self.assertEqual(
                hashes[str(payload)],
                "ff0d284a5747332f75fef9d40f91eceb09aba268a589be6f1d9f805e34cb4b65",
            )

    def test_gpu_preflight_returns_selected_idle_gpu(self):
        class FakeRemote:
            def run(self, command):
                if "--query-gpu=" in command:
                    return 0, "0, GPU-0, NVIDIA H20, 97871, 10, 0\n", ""
                return 0, "", ""

        class FakeProfile:
            @staticmethod
            def require(key):
                self.assertEqual(key, "GPU_IDS")
                return "0"

        self.assertEqual(
            server_tool.require_idle_profile_gpus(FakeRemote(), FakeProfile()),
            [
                {
                    "index": "0",
                    "uuid": "GPU-0",
                    "name": "NVIDIA H20",
                    "memory_total_mib": "97871",
                    "memory_used_mib": "10",
                    "memory_available_mib": "97861",
                    "utilization_gpu_percent": "0",
                }
            ],
        )

    def test_gpu_preflight_ignores_existing_compute_process_when_memory_is_available(self):
        class FakeRemote:
            def run(self, command):
                if "--query-gpu=" in command:
                    return 0, "4, GPU-4, NVIDIA H20, 97871, 56533, 100\n", ""
                return 0, "GPU-4, 2151955, [Not Found], 56510\n", ""

        class FakeProfile:
            @staticmethod
            def require(key):
                self.assertEqual(key, "GPU_IDS")
                return "4"

        state = server_tool.require_idle_profile_gpus(FakeRemote(), FakeProfile())
        self.assertEqual(state[0]["memory_available_mib"], "41338")
        self.assertEqual(
            state[0]["existing_compute_processes"],
            [
                {
                    "index": "4",
                    "pid": "2151955",
                    "process_name": "[Not Found]",
                    "used_memory_mib": "56510",
                }
            ],
        )

    def test_gpu_preflight_rejects_when_free_memory_is_not_above_30_gib(self):
        class FakeRemote:
            def run(self, command):
                if "--query-gpu=" in command:
                    return 0, "4, GPU-4, NVIDIA H20, 97871, 67151, 0\n", ""
                return 0, "", ""

        class FakeProfile:
            @staticmethod
            def require(key):
                self.assertEqual(key, "GPU_IDS")
                return "4"

        with self.assertRaisesRegex(
            server_tool.ToolError,
            "gpu=4 available=30720MiB required>30720MiB",
        ):
            server_tool.require_idle_profile_gpus(FakeRemote(), FakeProfile())


if __name__ == "__main__":
    unittest.main()

import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


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
ASSERT_OUTPUT_IDS = (
    REPO_ROOT / "skills" / "test-service" / "scripts" / "assert_output_ids.py"
)
RECOVERABLE_INJECT_ROOT = (
    REPO_ROOT / "skills" / "test-service" / "assets" / "sglang" / "recoverable_inject"
)


class SGLangCaseContractTests(unittest.TestCase):
    def test_ft_status_wait_correlates_successful_request_id(self):
        helper = (
            REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        ).read_text(encoding="utf-8")

        self.assertIn('item.get("last_ft_request_id")', helper)
        self.assertIn("reported_request_ids != {request_id}", helper)

    def test_ft_launchers_use_bounded_validation_timeouts(self):
        helper = (
            REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        ).read_text(encoding="utf-8")

        self.assertIn(
            'SGLANG_FT_CONTROL_PHASE_TIMEOUT_SEC:-60',
            helper,
        )
        self.assertIn(
            'SGLANG_FT_CONTROL_WAIT_TIMEOUT_SEC:-90',
            helper,
        )
        self.assertIn(
            'SGLANG_FT_ELASTIC_EP_SCALE_TIMEOUT_SEC:-150',
            helper,
        )
        self.assertIn(
            'SGLANG_FT_ELASTIC_EP_WAIT_TIMEOUT_SEC:-180',
            helper,
        )
        self.assertEqual(
            helper.count('--fault-tolerance-timeout "$sg_control_timeout"'),
            2,
        )
        self.assertEqual(
            helper.count('--elastic-ep-scale-timeout "$sg_elastic_ep_scale_timeout"'),
            2,
        )
        self.assertIn('>"$SERVER_TOOL_OUTPUT_ROOT/ft-timeouts.env"', helper)

    def test_ft_launcher_supports_explicit_overlap_schedule(self):
        helper = (
            REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        ).read_text(encoding="utf-8")

        self.assertIn('SGLANG_FT_OVERLAP_SCHEDULE:-0', helper)
        self.assertIn('sg_overlap_args+=(--disable-overlap-schedule)', helper)
        self.assertIn('"${sg_overlap_args[@]}"', helper)

    def test_overlap_scale_down_contract_has_concurrent_gates(self):
        run_text = (
            CASE_ROOT / "fault-exception-pause-scale-down" / "run.sh"
        ).read_text(encoding="utf-8")
        test_text = (
            CASE_ROOT / "fault-exception-pause-scale-down" / "TEST.md"
        ).read_text(encoding="utf-8")

        self.assertIn("run_concurrent_burst before_fault 0 1 2 3", run_text)
        self.assertIn("run_concurrent_burst after_scale_down 0 1 3", run_text)
        self.assertIn("${phase}_concurrent_inflight", run_text)
        self.assertIn('output_ids = response.get("output_ids")', run_text)
        self.assertIn('record["completion_tokens"] == 64', run_text)
        self.assertIn('2>/dev/null || true', run_text)
        self.assertIn("st_assert overlap_schedule_mode true enabled enabled", run_text)
        self.assertIn("SGLANG_FT_OVERLAP_SCHEDULE=0", test_text)
        self.assertIn("for overlap", test_text)

    def test_ft_apply_cases_wait_longer_than_control_phase(self):
        for run_path in CASE_ROOT.glob("*/run.sh"):
            text = run_path.read_text(encoding="utf-8")
            if "sg_apply_scale_down" not in text and "sg_apply_retry" not in text:
                continue
            self.assertIn(
                "$SGLANG_FT_CONTROL_WAIT_TIMEOUT_SEC",
                text,
                run_path.parent.name,
            )

    def test_rejoin_recovery_uses_elastic_ep_observation_timeout(self):
        for case_name in (
            "fault-kill-continue-whole-node-rejoin",
            "fault-kill-pause-scale-down-then-rejoin",
            "fault-kill-pause-scale-down-then-rejoin-cudagraph",
        ):
            text = (CASE_ROOT / case_name / "run.sh").read_text(encoding="utf-8")
            self.assertIn("$SGLANG_FT_ELASTIC_EP_WAIT_TIMEOUT_SEC", text)
            self.assertNotIn("recovery_eplb_second_forward 600", text)

    def test_ft_runtime_supports_explicit_tcp_fallback_mode(self):
        unit = (
            REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        ).read_text(encoding="utf-8")

        self.assertIn("SGLANG_FT_MOONCAKE_TRANSPORT_MODE", unit)
        self.assertIn("tcp-fallback)", unit)
        self.assertIn("export MC_FORCE_TCP=1", unit)
        self.assertIn("unset MC_INTRANODE_NVLINK", unit)
        self.assertIn("export MOONCAKE_EP_FORCE_FALLBACK=1", unit)
        self.assertIn("mooncake-transport.env", unit)

    def test_recoverable_fault_rank_supports_legacy_and_parallel_state_layouts(self):
        import sys

        sys.path.insert(0, str(RECOVERABLE_INJECT_ROOT))
        try:
            import ft_forward_fault
        finally:
            sys.path.remove(str(RECOVERABLE_INJECT_ROOT))

        self.assertEqual(
            ft_forward_fault.resolve_model_runner_rank(
                SimpleNamespace(dp_rank=2, tp_rank=7)
            ),
            2,
        )
        self.assertEqual(
            ft_forward_fault.resolve_model_runner_rank(
                SimpleNamespace(ps=SimpleNamespace(dp_rank=3, tp_rank=8))
            ),
            3,
        )
        self.assertEqual(
            ft_forward_fault.resolve_model_runner_rank(
                SimpleNamespace(ps=SimpleNamespace(dp_rank=None, tp_rank=9))
            ),
            9,
        )

    def test_local_only_fault_injection_is_explicit_opt_in(self):
        import sys

        sys.path.insert(0, str(RECOVERABLE_INJECT_ROOT))
        try:
            import ft_forward_fault
        finally:
            sys.path.remove(str(RECOVERABLE_INJECT_ROOT))

        with mock.patch.dict(
            os.environ,
            {ft_forward_fault.ENV_LOCAL_ONLY: ""},
            clear=False,
        ):
            self.assertFalse(ft_forward_fault.local_only_fault_enabled())
        with mock.patch.dict(
            os.environ,
            {ft_forward_fault.ENV_LOCAL_ONLY: "1"},
            clear=False,
        ):
            self.assertTrue(ft_forward_fault.local_only_fault_enabled())

    def test_local_only_fault_is_injected_after_the_model_forward(self):
        injector = (
            REPO_ROOT
            / "skills"
            / "test-service"
            / "assets"
            / "sglang"
            / "recoverable_inject"
            / "ft_forward_fault.py"
        ).read_text(encoding="utf-8")
        local_only_branch = injector.index(
            "if local_only_fault_enabled():", injector.index("def patched_forward")
        )
        local_forward = injector.index(
            "original_forward(self, forward_batch, **kwargs)", local_only_branch
        )
        injected = injector.index("injected[0] = True", local_only_branch)
        injected_raise = injector.index("raise RuntimeError(", injected)
        self.assertLess(local_forward, injected)
        self.assertLess(injected, injected_raise)

    def test_index_covers_existing_contracts_without_loading_history(self):
        index = (CASE_ROOT / "INDEX.md").read_text(encoding="utf-8")
        identifiers = re.findall(r"`(fault-[a-z0-9-]+)`", index)
        actual = {p.parent.name for p in CASE_ROOT.glob("*/run.sh")}
        self.assertEqual(set(identifiers), actual)
        self.assertEqual(len(identifiers), len(actual))
        self.assertNotIn("PASS ON", index)
        self.assertIn("VALIDATION-HISTORY.md", index)
        for case in identifiers:
            self.assertTrue((CASE_ROOT / case / "TEST.md").is_file())

    def test_active_cases_complete_inference_before_fault(self):
        fault_markers = (
            "st_kill_owned_",
            "sg_kill_scheduler_",
            "sg_start_recoverable_fault",
            "sg_apply_",
            "sg_issue_generate_fault_trigger",
            "st_stop_owned_pgid",
            "/fault_tolerance/apply",
        )
        for run_path in sorted(CASE_ROOT.glob("*/run.sh")):
            with self.subTest(case=run_path.parent.name):
                run_text = run_path.read_text(encoding="utf-8")
                after_ready = run_text[run_text.index("st_wait_http_ready") :]
                generate = after_ready.index("/generate")
                fault = min(
                    after_ready.index(marker)
                    for marker in fault_markers
                    if marker in after_ready
                )
                self.assertLess(generate, fault)
                self.assertRegex(after_ready[generate:fault], r"\s200\s")

    def test_implemented_cases_have_complete_contracts(self):
        implemented = sorted(
            case_root.name
            for case_root in CASE_ROOT.iterdir()
            if case_root.is_dir() and (case_root / "run.sh").is_file()
        )
        self.assertEqual(len(implemented), 16)
        for case in implemented:
            with self.subTest(case=case):
                case_root = CASE_ROOT / case
                self.assertTrue((case_root / "TEST.md").is_file())
                self.assertTrue((case_root / "run.sh").is_file())
                test_text = (case_root / "TEST.md").read_text(encoding="utf-8")
                run_text = (case_root / "run.sh").read_text(encoding="utf-8")
                self.assertIn("codex/ft-vllm-api-refactor", test_text)
                self.assertIn("assertions", test_text)
                self.assertNotRegex(run_text, r"REMOTE_AGENT|remote-agent")

    def test_rejection_contract_treats_legacy_recover_as_unsupported(self):
        case_root = CASE_ROOT / "fault-rejection-contracts"
        content = "\n".join(
            (case_root / name).read_text(encoding="utf-8")
            for name in ("TEST.md", "run.sh")
        )
        self.assertIn("Invalid instruction: 'recover'.", content)
        self.assertIn("no fault is injected on DP0", content)
        self.assertNotIn("scale_down_dp_rank_0_not_supported", content)
        self.assertNotIn('"removed_dp_ranks":[0]', content)
        self.assertIn('sg_launch_dp4_ft pause "$port" "$log_path" 1', content)
        self.assertIn("ft_operation_in_progress", content)
        self.assertIn("409", content)
        self.assertNotIn("recover_requires_disabled_ranks", content)

    def test_kill_retry_contracts_are_not_executable(self):
        index = (CASE_ROOT / "INDEX.md").read_text(encoding="utf-8")
        for case in (
            "fault-kill-pause-retry",
            "fault-kill-pause-inflight-retry",
        ):
            with self.subTest(case=case):
                self.assertFalse((CASE_ROOT / case).exists())
                self.assertNotIn(f"`{case}`", index)

    def test_only_exception_injection_contracts_execute_retry(self):
        retry_cases = sorted(
            run_sh.parent.name
            for run_sh in CASE_ROOT.glob("*/run.sh")
            if "sg_apply_retry" in run_sh.read_text(encoding="utf-8")
        )
        self.assertEqual(
            retry_cases,
            [
                "fault-exception-pause-retry",
                "fault-kill-scale-down-exception-retry",
            ],
        )

    def test_exception_retry_uses_per_rank_precision_oracles(self):
        case = (CASE_ROOT / "fault-exception-pause-retry" / "run.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn('sg_precision_oracle_id "$rank"', case)
        self.assertNotIn("sg_assert_output_ids_equal", case)

    def test_active_contracts_never_expect_public_paused_state(self):
        for case_root in CASE_ROOT.iterdir():
            if not (case_root / "run.sh").is_file():
                continue
            with self.subTest(case=case_root.name):
                content = "\n".join(
                    path.read_text(encoding="utf-8")
                    for path in (case_root / "TEST.md", case_root / "run.sh")
                )
                self.assertNotIn("=paused", content)

    def test_default_precision_oracles_exist_and_cases_use_resolver(self):
        registry = json.loads(ORACLE_PATH.read_text(encoding="utf-8"))
        oracle_ids = {entry["id"] for entry in registry["entries"]}
        for rank in range(4):
            self.assertIn(
                f"qwen-fp8-d4t4e4-count10-no-overlap-rank{rank}-r128",
                oracle_ids,
            )
            self.assertIn(
                f"deepseek-v2-lite-chat-bf16-d4t4e4-count10-no-overlap-rank{rank}-r64",
                oracle_ids,
            )
        self.assertIn(
            "qwen-fp8-d4t4e4-count10-no-overlap-rank0-r384",
            oracle_ids,
        )
        self.assertIn(
            "deepseek-v2-lite-chat-bf16-d4t4e4-count10-no-overlap-rank0-r192",
            oracle_ids,
        )
        for run_sh in CASE_ROOT.glob("*/run.sh"):
            text = run_sh.read_text(encoding="utf-8")
            self.assertNotRegex(
                text,
                r"qwen-fp8-d4t4e4-count10-no-overlap-rank(?:[0-3]|\$\{rank\})-r128",
            )

    def test_known_output_gate_accepts_only_registered_sequences(self):
        registry = {
            "entries": [
                {
                    "id": "test",
                    "output_ids": [1, 2],
                    "known_output_ids": [[1, 2], [3, 4]],
                }
            ]
        }
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            registry_path = root / "registry.json"
            response_path = root / "response.json"
            result_path = root / "result.json"
            registry_path.write_text(json.dumps(registry), encoding="utf-8")

            def run(output_ids, allow_known):
                response_path.write_text(
                    json.dumps({"output_ids": output_ids}), encoding="utf-8"
                )
                command = [
                    "python",
                    str(ASSERT_OUTPUT_IDS),
                    "--registry",
                    str(registry_path),
                    "--oracle",
                    "test",
                    "--response",
                    str(response_path),
                    "--output",
                    str(result_path),
                ]
                if allow_known:
                    command.append("--allow-known")
                return subprocess.run(command, capture_output=True, text=True)

            self.assertNotEqual(run([3, 4], allow_known=False).returncode, 0)
            self.assertEqual(run([3, 4], allow_known=True).returncode, 0)
            self.assertNotEqual(run([5, 6], allow_known=True).returncode, 0)

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
        self.assertIn("SGLANG_FT_RANDOM_SEED", unit)
        self.assertIn('sg_random_seed_args+=(--random-seed "$sg_random_seed")', unit)

    def test_rejoin_launcher_supports_decode_only_cuda_graph(self):
        unit = (
            REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        ).read_text(encoding="utf-8")
        self.assertIn("SGLANG_FT_CUDA_GRAPH_MODE", unit)
        self.assertIn("decode-only)", unit)
        self.assertIn("--cuda-graph-backend-decode full", unit)
        self.assertIn("--cuda-graph-backend-prefill disabled", unit)
        self.assertIn("--cuda-graph-bs-decode 1 2 4 8", unit)

    def test_recovery_drive_retries_serially_until_log(self):
        unit = (
            REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        ).read_text(encoding="utf-8")
        function = unit.split("sg_drive_generate_until_log() {", 1)[1].split(
            "\n}\n", 1
        )[0]
        self.assertIn('--max-time "$sg_remaining"', function)
        self.assertIn('${sg_output_prefix}-${sg_attempt}.json', function)
        self.assertIn("sg_attempt=$((sg_attempt + 1))", function)
        self.assertIn('sleep "$sg_sleep_sec"', function)
        self.assertIn("sg_sleep_sec=10", function)

    def test_recovery_drive_retries_after_request_returns(self):
        unit = REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            log_path = (root / "node.log").as_posix()
            request_path = (root / "request.json").as_posix()
            output_prefix = (root / "response").as_posix()
            counter_path = (root / "attempts").as_posix()
            command = rf"""
set -Eeuo pipefail
source {unit.as_posix()!r}
timeout() {{ shift; "$@"; }}
curl() {{
  sg_count="$(cat {counter_path!r})"
  sg_count=$((sg_count + 1))
  printf '%s\n' "$sg_count" >{counter_path!r}
  if [[ "$sg_count" == 2 ]]; then
    printf '%s\n' 'recover ranks [3] done' >>{log_path!r}
  fi
  printf '200'
}}
sleep() {{ :; }}
st_log() {{ :; }}
st_assert() {{ test "$2" = true; }}
printf '{{}}' >{request_path!r}
: >{log_path!r}
printf '0\n' >{counter_path!r}
sg_drive_generate_until_log 6200 {request_path!r} {log_path!r} \
  'recover ranks \[3\] done' {output_prefix!r} 3 recovery_done_observed
test "$(cat {counter_path!r})" = 2
"""
            completed = subprocess.run(
                ["bash", "-c", command],
                text=True,
                capture_output=True,
                timeout=5,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_fault_tolerance_apply_payloads_use_async_vllm_schema(self):
        unit = (
            REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        ).read_text(encoding="utf-8")
        rejection_case = (
            REPO_ROOT
            / "skills"
            / "test-service"
            / "cases"
            / "sglang"
            / "fault-rejection-contracts"
            / "run.sh"
        ).read_text(encoding="utf-8")
        exception_retry_case = (
            REPO_ROOT
            / "skills"
            / "test-service"
            / "cases"
            / "sglang"
            / "fault-exception-pause-retry"
            / "run.sh"
        ).read_text(encoding="utf-8")

        self.assertNotIn("fault_tolerance_instruction", rejection_case)
        self.assertNotIn("fault_tolerance_params", rejection_case)
        self.assertNotIn("fault_tolerance_timeout", rejection_case)
        self.assertNotIn('"params": {"timeout"', unit)
        self.assertNotIn("SGLANG_FT_APPLY_REQUEST_SCHEMA", unit)
        self.assertIn('"instruction": "scale_down"', unit)
        self.assertIn('"removed_dp_ranks"', unit)
        self.assertIn('"request_id": request_id', unit)
        self.assertIn('"instruction": "retry"', unit)
        self.assertIn('"params": {}', unit)
        self.assertNotIn('"instruction": "recover"', unit)
        self.assertIn('data["engines"]', unit)
        self.assertIn('local sg_request_id="${6:-}"', unit)
        self.assertIn('local sg_timeout_sec="${5:-120}"', unit)
        self.assertIn("sg_apply_retry", exception_retry_case)
        self.assertIn('"instruction":"retry"', rejection_case)

    def test_continuous_scale_down_uses_vllm_unhealthy_status(self):
        case = (
            REPO_ROOT
            / "skills"
            / "test-service"
            / "cases"
            / "sglang"
            / "fault-kill-pause-continuous-scale-down"
            / "run.sh"
        ).read_text(encoding="utf-8")
        self.assertNotIn("SGLANG_FT_INCIDENT_STATE_SCHEMA", case)
        self.assertNotIn("=paused", case)
        self.assertIn("0=unhealthy,1=dead,2=unhealthy,3=unhealthy", case)
        self.assertIn("redundant_experts_capacity", case)
        self.assertIn(">= 384", case)

    def test_idle_scale_down_uses_process_loss_without_survivor_forward(self):
        case = (
            CASE_ROOT / "fault-kill-pause-scale-down" / "run.sh"
        ).read_text(encoding="utf-8")

        incident_index = case.index("status_incident")
        admission_index = case.index("admission_blocks_generate")
        scale_down_index = case.index("sg_apply_scale_down")

        self.assertIn("0=healthy,1=dead,2=healthy,3=healthy", case)
        self.assertNotIn("sg_issue_generate_fault_trigger", case)
        self.assertNotIn("survivors_self_paused", case)
        self.assertLess(incident_index, admission_index)
        self.assertLess(admission_index, scale_down_index)

    def test_idle_double_kill_keeps_survivors_healthy(self):
        case = (
            CASE_ROOT / "fault-kill-pause-double-scale-down" / "run.sh"
        ).read_text(encoding="utf-8")

        self.assertIn("0=healthy,1=dead,2=healthy,3=healthy", case)
        self.assertIn("0=healthy,1=dead,2=dead,3=healthy", case)
        self.assertNotIn("unhealthy,1=dead", case)

    def test_pause_rejoin_automatically_reopens_after_native_recovery(self):
        case = (
            REPO_ROOT
            / "skills"
            / "test-service"
            / "cases"
            / "sglang"
            / "fault-kill-pause-scale-down-then-rejoin"
            / "run.sh"
        ).read_text(encoding="utf-8")

        self.assertIn("rejoin_waits_for_native_recovery", case)
        self.assertIn("rejoin_waiting_keeps_dp3_closed", case)
        self.assertEqual(case.count("sg_wait_inactive_route_error"), 1)
        self.assertEqual(case.count("sg_assert_inactive_route_error"), 1)
        self.assertNotIn("Elastic EP recovery join process groups begin", case)
        self.assertIn("recovery_done_observed", case)
        self.assertIn("recovery_eplb_second_forward", case)
        self.assertIn("status-recovered.json", case)
        self.assertIn("0=healthy,1=healthy,2=healthy,3=healthy", case)
        self.assertIn("status_auto_recovered", case)
        self.assertNotIn("status-disabled.json", case)
        self.assertNotIn("sg_apply_recover", case)
        stream_index = case.index("sg_start_stream_request")
        decode_index = case.index("sg_wait_stream_decode_rank")
        owner_group_kill_index = case.index("node3_owner_process_group_killed")
        owner_group_gone_index = case.index("node3_owner_process_group_confirmed_gone")
        scale_down_index = case.index("sg_apply_scale_down")
        rejoin_index = case.index(
            'node_logs[3]="$SERVER_TOOL_OUTPUT_ROOT/node3-rejoin.log"'
        )
        recovery_drive_index = case.index("sg_drive_generate_until_log")
        recovery_done_index = case.index("recovery_done_observed")
        healthy_index = case.index("status-recovered.json")
        self.assertNotIn("st_kill_owned_process", case)
        self.assertNotIn("sg_issue_generate_fault_trigger", case)
        self.assertLess(stream_index, decode_index)
        self.assertLess(decode_index, owner_group_kill_index)
        self.assertLess(owner_group_kill_index, owner_group_gone_index)
        self.assertLess(owner_group_gone_index, scale_down_index)
        self.assertLess(scale_down_index, rejoin_index)
        self.assertLess(rejoin_index, recovery_drive_index)
        self.assertLess(recovery_drive_index, recovery_done_index)
        self.assertLess(recovery_done_index, healthy_index)

    def test_cudagraph_rejoin_keeps_fault_scale_down_rejoin_order(self):
        case = (
            CASE_ROOT
            / "fault-kill-pause-scale-down-then-rejoin-cudagraph"
            / "run.sh"
        ).read_text(encoding="utf-8")
        decode_index = case.index("sg_wait_stream_decode_rank")
        kill_index = case.index("node3_owner_process_group_killed")
        scale_down_index = case.index("sg_apply_scale_down")
        rejoin_index = case.index('node_logs[3]="$SERVER_TOOL_OUTPUT_ROOT/node3-rejoin.log"')
        capture_index = case.index("replacement_decode_graph_captured")
        recovery_drive_index = case.index("sg_drive_generate_until_log")
        self.assertIn("SGLANG_FT_CUDA_GRAPH_MODE=decode-only", case)
        self.assertIn("survivor_node${graph_node}_capture_count", case)
        self.assertIn("replacement_capture_count", case)
        self.assertNotIn("Elastic EP recovery join process groups begin", case)
        self.assertIn("sg_assert_inactive_route_error", case)
        self.assertIn("CUDA_ERROR_ILLEGAL_ADDRESS", case)
        self.assertLess(decode_index, kill_index)
        self.assertLess(kill_index, scale_down_index)
        self.assertLess(scale_down_index, rejoin_index)
        self.assertLess(rejoin_index, capture_index)
        self.assertLess(capture_index, recovery_drive_index)

    def test_continue_rejoin_drives_recovery_without_join_log_barrier(self):
        case = (
            CASE_ROOT / "fault-kill-continue-whole-node-rejoin" / "run.sh"
        ).read_text(encoding="utf-8")
        drive_index = case.index("sg_drive_generate_until_log")
        rejoin_index = case.index('node_logs[3]="$SERVER_TOOL_OUTPUT_ROOT/node3-rejoin.log"')
        self.assertNotIn("Elastic EP recovery join process groups begin", case)
        self.assertLess(rejoin_index, drive_index)

    def test_noft_native_inflight_uses_current_mooncake_failure_log(self):
        case = (CASE_ROOT / "fault-kill-noft-native-inflight" / "run.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("health check rank [023] -> 1 FAILED", case)
        self.assertNotIn("marking peer 1 as broken", case)
        self.assertNotIn("learned peer 1 is broken", case)

    def test_exception_scale_down_kills_target_without_direct_recover(self):
        case = (CASE_ROOT / "fault-exception-pause-scale-down" / "run.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("whole_dp2_shutdown_process_count", case)
        self.assertIn("global_rank2_shutdown", case)
        self.assertIn("0=healthy,1=healthy,2=dead,3=healthy", case)
        self.assertNotIn("sg_apply_recover", case)

    def test_retry_after_scale_down_preserves_committed_three_rank_topology(self):
        case = (
            CASE_ROOT / "fault-kill-scale-down-exception-retry" / "run.sh"
        ).read_text(encoding="utf-8")

        self.assertIn("SGLANG_TEST_FT_RECOVERABLE_FAULT_LOCAL_ONLY=1", case)
        self.assertIn("0=unhealthy,1=dead,2=healthy,3=healthy", case)
        self.assertNotIn("retry_reset", case)
        self.assertIn("three_rank_topology_rebalanced", case)
        self.assertIn("retry_does_not_run_eplb", case)
        self.assertIn("retry_keeps_three_schedulers", case)
        self.assertIn("removed_dp1_stays_closed_after_retry", case)
        kill_index = case.index("st_kill_owned_process")
        scale_down_index = case.index("sg_apply_scale_down")
        exception_index = case.index("sg_start_recoverable_fault")
        retry_index = case.index("sg_apply_retry")
        self.assertLess(kill_index, scale_down_index)
        self.assertLess(scale_down_index, exception_index)
        self.assertLess(exception_index, retry_index)

    def test_attention_siblings_are_removed_by_whole_dp_scale_down(self):
        case_root = CASE_ROOT / "fault-tpgt1-whole-dp-shutdown"
        test_text = (case_root / "TEST.md").read_text(encoding="utf-8")
        run_text = (case_root / "run.sh").read_text(encoding="utf-8")
        self.assertIn("both global ranks 2 and 3", test_text)
        self.assertIn("global_rank2_shutdown", run_text)
        self.assertIn("global_rank3_shutdown", run_text)
        self.assertIn("sg_apply_scale_down", run_text)
        self.assertNotIn("sg_apply_retry", run_text)
        self.assertFalse((CASE_ROOT / "fault-tpgt1-sibling-ep-retention").exists())

    def test_ordinary_launchers_honor_dispatch_determinism_and_seed(self):
        unit = REPO_ROOT / "skills" / "test-service" / "scripts" / "sglang_ft_ops.sh"
        command = f"""
set -Eeuo pipefail
export SERVER_TOOL_PROJECT_ROOT=.
export MODEL_PATH=/unused/model
export SGLANG_FT_EP_DISPATCH_ALGORITHM=static
export SGLANG_FT_DETERMINISTIC_INFERENCE=1
export SGLANG_FT_RANDOM_SEED=424242
source {unit.as_posix()!r}
st_launch_process_group() {{ printf '%s\\n' "$@"; }}
st_assert() {{ :; }}
ft_command="$(sg_launch_dp4_ft pause 6200 /tmp/ft.log)"
noft_command="$(sg_launch_dp4_mooncake_noft 6201 /tmp/noft.log)"
for command_text in "$ft_command" "$noft_command"; do
  grep -q -x -- '--ep-dispatch-algorithm' <<<"$command_text"
  grep -q -x -- 'static' <<<"$command_text"
  grep -q -x -- '--enable-deterministic-inference' <<<"$command_text"
  grep -q -x -- '--random-seed' <<<"$command_text"
  grep -q -x -- '424242' <<<"$command_text"
done
"""
        completed = subprocess.run(
            ["bash", "-c", command],
            text=True,
            capture_output=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)

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
            "SGLANG_KERNEL_REQUIRED_SYMBOL:-fp8_blockwise_scaled_mm",
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

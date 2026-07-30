#!/usr/bin/env python3
"""Task-scoped SSH runner for server_tool.

The CLI transports committed inputs and owns remote run lifecycle mechanics.
Test meaning and step composition stay in committed TEST.md/run.sh contracts.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import posixpath
import re
import shlex
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

try:
    import paramiko
except ImportError as exc:  # pragma: no cover
    raise SystemExit("missing dependency: paramiko") from exc


REPO_ROOT = Path(__file__).resolve().parents[1]
REMOTE_RUNNER = Path(__file__).with_name("remote_runner.sh")
RUN_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
SAFE_REMOTE_ROOT = "/data2/iws"
REQUIRED_PROFILE_KEYS = {
    "PROFILE_NAME",
    "REMOTE_HOST",
    "REMOTE_PORT",
    "REMOTE_USER",
    "SSH_KEY",
    "LOCAL_REPO",
    "LOCAL_BRANCH",
    "REMOTE_BRANCH",
    "REMOTE_TASK_ROOT",
    "REMOTE_PROJECT_ROOT",
    "LOCAL_ARTIFACT_ROOT",
    "GPU_IDS",
    "PORT_BASE",
    "PORT_COUNT",
    "CONTAINER_NAME",
    "CONTAINER_MANIFEST",
    "SGLANG_KERNEL_ROOT",
    "SGLANG_KERNEL_VERSION",
}
RUNTIME_PROFILE_KEYS = (
    "PROFILE_NAME",
    "GPU_IDS",
    "PORT_BASE",
    "PORT_COUNT",
    "MODEL_PATH",
    "SGLANG_KERNEL_ROOT",
    "SGLANG_KERNEL_VERSION",
    "MOONCAKE_ROOT",
    "MOONCAKE_VERSION",
    "MOONCAKE_WHEEL",
    "MOONCAKE_SOURCE_COMMIT",
    "MOONCAKE_WHEEL_SHA256",
    "SGLANG_FT_EP_NUM_REDUNDANT_EXPERTS",
    "SGLANG_FT_MEM_FRACTION_STATIC",
    "SGLANG_FT_PRECISION_ORACLE_FAMILY",
    "SGLANG_FT_RELIABLE_ORACLE_ID",
    "SGLANG_FT_EP_DISPATCH_ALGORITHM",
    "SGLANG_FT_DETERMINISTIC_INFERENCE",
    "SGLANG_FT_REJOIN_REQUEST_STYLE",
    "SGLANG_FT_REJOIN_MAX_TOKENS",
    "SGLANG_FT_RANDOM_SEED",
    "CONTAINER_NAME",
    "CONTAINER_MANIFEST",
)
FORBIDDEN_SCRIPT_PATTERNS = {
    "pkill": re.compile(r"\bpkill\b"),
    "killall": re.compile(r"\bkillall\b"),
    "broad recursive delete": re.compile(r"\brm\s+-[^\n]*r[^\n]*f\s+(?:/|~|\$HOME|\*)"),
}


class ToolError(RuntimeError):
    pass


def read_env(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise ToolError(f"profile not found: {path}")
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip("\"'")
    return values


def within_remote(path: str, root: str) -> bool:
    normalized = posixpath.normpath(path)
    normalized_root = posixpath.normpath(root)
    return normalized == normalized_root or normalized.startswith(normalized_root + "/")


def require_remote_child(path: str, root: str, label: str) -> str:
    normalized = posixpath.normpath(path)
    if normalized == posixpath.normpath(root) or not within_remote(normalized, root):
        raise ToolError(f"{label} must be a child of {root}: {normalized}")
    return normalized


def safe_name(value: str, label: str) -> str:
    if not RUN_NAME_RE.fullmatch(value):
        raise ToolError(f"{label} must match {RUN_NAME_RE.pattern}")
    return value


def shell_quote(value: str) -> str:
    return shlex.quote(value)


def run_local(args: list[str], cwd: Path) -> str:
    proc = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if proc.returncode:
        raise ToolError(
            f"local command failed ({proc.returncode}): {' '.join(args)}\n{proc.stderr.strip()}"
        )
    return proc.stdout.strip()


def scan_script(path: Path) -> None:
    if path.suffix.lower() not in {"", ".sh", ".bash"}:
        return
    text = path.read_text(encoding="utf-8", errors="replace")
    violations = [name for name, pattern in FORBIDDEN_SCRIPT_PATTERNS.items() if pattern.search(text)]
    if violations:
        raise ToolError(f"unsafe script {path}: {', '.join(violations)}")


@dataclass(frozen=True)
class Profile:
    path: Path
    values: dict[str, str]

    @classmethod
    def load(cls, path_text: str) -> "Profile":
        path = Path(path_text).resolve()
        values = read_env(path)
        missing = sorted(key for key in REQUIRED_PROFILE_KEYS if not values.get(key))
        if missing:
            raise ToolError(f"missing profile keys: {', '.join(missing)}")
        profile = cls(path=path, values=values)
        profile.validate()
        return profile

    def get(self, key: str, default: str = "") -> str:
        return self.values.get(key, default).strip()

    def require(self, key: str) -> str:
        value = self.get(key)
        if not value:
            raise ToolError(f"missing profile key: {key}")
        return value

    @property
    def local_repo(self) -> Path:
        return Path(self.require("LOCAL_REPO")).resolve()

    @property
    def artifact_root(self) -> Path:
        return Path(self.require("LOCAL_ARTIFACT_ROOT")).resolve()

    @property
    def task_root(self) -> str:
        return posixpath.normpath(self.require("REMOTE_TASK_ROOT"))

    @property
    def project_root(self) -> str:
        return posixpath.normpath(self.require("REMOTE_PROJECT_ROOT"))

    def validate(self) -> None:
        safe_name(self.require("PROFILE_NAME"), "PROFILE_NAME")
        if not self.local_repo.is_dir():
            raise ToolError(f"LOCAL_REPO not found: {self.local_repo}")
        if not Path(self.require("SSH_KEY")).is_file():
            raise ToolError(f"SSH_KEY not found: {self.require('SSH_KEY')}")
        if self.require("LOCAL_BRANCH") != self.require("REMOTE_BRANCH"):
            raise ToolError("LOCAL_BRANCH and REMOTE_BRANCH must match")
        require_remote_child(self.task_root, f"{SAFE_REMOTE_ROOT}/tasks", "REMOTE_TASK_ROOT")
        require_remote_child(self.project_root, f"{SAFE_REMOTE_ROOT}/projects", "REMOTE_PROJECT_ROOT")
        require_remote_child(
            self.require("CONTAINER_MANIFEST"),
            SAFE_REMOTE_ROOT,
            "CONTAINER_MANIFEST",
        )
        require_remote_child(
            self.require("SGLANG_KERNEL_ROOT"),
            f"{SAFE_REMOTE_ROOT}/deps/sglang-kernel",
            "SGLANG_KERNEL_ROOT",
        )
        if self.get("MOONCAKE_ROOT"):
            require_remote_child(self.get("MOONCAKE_ROOT"), SAFE_REMOTE_ROOT, "MOONCAKE_ROOT")
        int(self.require("REMOTE_PORT"))
        port_base = int(self.require("PORT_BASE"))
        port_count = int(self.require("PORT_COUNT"))
        if port_base < 6100 or port_base > 6300 or port_count < 1 or port_base + port_count - 1 > 6300:
            raise ToolError("PORT_BASE/PORT_COUNT must stay within 6100-6300")

    def source_identity(self) -> tuple[str, str]:
        dirty = run_local(["git", "status", "--porcelain"], self.local_repo)
        if dirty:
            raise ToolError(f"LOCAL_REPO is dirty:\n{dirty}")
        branch = run_local(["git", "branch", "--show-current"], self.local_repo)
        if branch != self.require("LOCAL_BRANCH"):
            raise ToolError(f"expected branch {self.require('LOCAL_BRANCH')}, got {branch or '<detached>'}")
        return branch, run_local(["git", "rev-parse", "HEAD"], self.local_repo)


class Remote:
    def __init__(self, profile: Profile):
        self.profile = profile
        self.client: paramiko.SSHClient | None = None
        self.sftp: paramiko.SFTPClient | None = None

    def __enter__(self) -> "Remote":
        client = paramiko.SSHClient()
        known_hosts = self.profile.get("KNOWN_HOSTS")
        if known_hosts:
            client.load_host_keys(str(Path(known_hosts).resolve()))
            client.set_missing_host_key_policy(paramiko.RejectPolicy())
        else:
            client.load_system_host_keys()
            client.set_missing_host_key_policy(paramiko.WarningPolicy())
        client.connect(
            self.profile.require("REMOTE_HOST"),
            port=int(self.profile.require("REMOTE_PORT")),
            username=self.profile.require("REMOTE_USER"),
            key_filename=self.profile.require("SSH_KEY"),
            look_for_keys=False,
            allow_agent=False,
            timeout=20,
            banner_timeout=20,
            auth_timeout=20,
        )
        self.client = client
        self.sftp = client.open_sftp()
        return self

    def __exit__(self, *_: object) -> None:
        if self.sftp:
            self.sftp.close()
        if self.client:
            self.client.close()

    def run(self, command: str, timeout: int = 30, check: bool = True) -> tuple[int, str, str]:
        assert self.client is not None
        _, stdout, stderr = self.client.exec_command(command, timeout=timeout)
        out = stdout.read().decode(errors="replace")
        err = stderr.read().decode(errors="replace")
        code = stdout.channel.recv_exit_status()
        if check and code:
            raise ToolError(f"remote command failed ({code}): {command}\n{err.strip()}")
        return code, out, err

    def mkdir(self, path: str) -> None:
        path = require_remote_child(path, self.profile.task_root, "remote run path")
        self.run(f"umask 077; mkdir -p -- {shell_quote(path)}")

    def put_file(self, local: Path, remote_path: str, mode: int | None = None) -> None:
        assert self.sftp is not None
        require_remote_child(remote_path, self.profile.task_root, "remote upload path")
        self.mkdir(posixpath.dirname(remote_path))
        self.sftp.put(str(local), remote_path)
        if mode is not None:
            self.sftp.chmod(remote_path, mode)

    def put_text(self, text: str, remote_path: str, mode: int | None = None) -> None:
        assert self.sftp is not None
        require_remote_child(remote_path, self.profile.task_root, "remote upload path")
        self.mkdir(posixpath.dirname(remote_path))
        with self.sftp.file(remote_path, "w") as handle:
            handle.write(text)
        if mode is not None:
            self.sftp.chmod(remote_path, mode)

    def put_tree(self, local: Path, remote_path: str) -> None:
        if local.is_symlink():
            raise ToolError(f"refusing symlink attachment: {local}")
        if local.is_file():
            scan_script(local)
            self.put_file(local, remote_path, 0o755 if os.access(local, os.X_OK) else None)
            return
        for child in sorted(local.iterdir(), key=lambda item: item.name):
            self.put_tree(child, posixpath.join(remote_path, child.name))

    def get_tree(self, remote_path: str, local: Path) -> None:
        assert self.sftp is not None
        require_remote_child(remote_path, self.profile.task_root, "remote fetch path")
        local.mkdir(parents=True, exist_ok=True)
        for item in self.sftp.listdir_attr(remote_path):
            source = posixpath.join(remote_path, item.filename)
            target = local / item.filename
            if stat.S_ISLNK(item.st_mode):
                raise ToolError(f"refusing remote symlink: {source}")
            if stat.S_ISDIR(item.st_mode):
                self.get_tree(source, target)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                self.sftp.get(source, str(target))


def run_root(profile: Profile, name: str) -> str:
    return f"{profile.task_root}/runs/{safe_name(name, 'run name')}"


def verify_task_owner(remote: Remote, profile: Profile, create: bool = False) -> None:
    marker = f"{profile.task_root}/.server-tool-task"
    expected = f"profile={profile.require('PROFILE_NAME')}"
    command = (
        f"if [ -e {shell_quote(profile.task_root)} ]; then "
        f"test -f {shell_quote(marker)} && grep -Fqx {shell_quote(expected)} {shell_quote(marker)}; "
        "else exit 44; fi"
    )
    code, _, _ = remote.run(command, check=False)
    if code == 0:
        return
    if not create:
        raise ToolError("remote task root is absent or not owned by this profile")
    parent = posixpath.dirname(profile.task_root)
    remote.run(
        f"test -d {shell_quote(parent)}; "
        f"test ! -e {shell_quote(profile.task_root)}; "
        f"umask 077; mkdir {shell_quote(profile.task_root)}; "
        f"printf '%s\\n' {shell_quote(expected)} > {shell_quote(marker)}"
    )


def require_idle_profile_gpus(
    remote: Remote, profile: Profile, *, allow_occupied: bool = False
) -> list[dict[str, object]]:
    _, gpu_output, _ = remote.run(
        "nvidia-smi --query-gpu=index,uuid,name,memory.total,memory.used,utilization.gpu "
        "--format=csv,noheader,nounits"
    )
    _, process_output, _ = remote.run(
        "nvidia-smi --query-compute-apps=gpu_uuid,pid,process_name,used_memory "
        "--format=csv,noheader,nounits"
    )
    gpus = []
    gpu_index_by_uuid = {}
    for row in csv.reader(io.StringIO(gpu_output)):
        if len(row) != 6:
            raise ToolError(f"unexpected nvidia-smi GPU row: {row}")
        index, uuid, name, memory_total, memory_used, utilization = (
            value.strip() for value in row
        )
        gpu_index_by_uuid[uuid] = index
        gpus.append(
            {
                "index": index,
                "uuid": uuid,
                "name": name,
                "memory_total_mib": memory_total,
                "memory_used_mib": memory_used,
                "utilization_gpu_percent": utilization,
            }
        )

    requested = profile.require("GPU_IDS")
    selected = (
        set(gpu_index_by_uuid.values())
        if requested == "all"
        else set(requested.split(","))
    )
    unknown = sorted(selected - set(gpu_index_by_uuid.values()))
    if unknown:
        raise ToolError(f"GPU_IDS contains unavailable indexes: {','.join(unknown)}")

    conflicts = []
    for row in csv.reader(io.StringIO(process_output)):
        if not row:
            continue
        if len(row) != 4:
            raise ToolError(f"unexpected nvidia-smi compute-app row: {row}")
        uuid, pid, process_name, used_memory = (value.strip() for value in row)
        index = gpu_index_by_uuid.get(uuid)
        if index in selected:
            conflicts.append(
                {
                    "index": index,
                    "pid": pid,
                    "process_name": process_name,
                    "used_memory_mib": used_memory,
                }
            )
    if conflicts and not allow_occupied:
        details = "; ".join(
            f"gpu={item['index']} pid={item['pid']} "
            f"memory={item['used_memory_mib']}MiB process={item['process_name']}"
            for item in conflicts
        )
        raise ToolError(f"selected GPUs are occupied: {details}")
    selected_gpus = [gpu for gpu in gpus if gpu["index"] in selected]
    if allow_occupied:
        for gpu in selected_gpus:
            gpu["existing_compute_processes"] = [
                process for process in conflicts if process["index"] == gpu["index"]
            ]
    return selected_gpus


def parse_attachment(text: str) -> tuple[Path, str]:
    if ":" not in text:
        raise ToolError("--attach must be LOCAL_PATH:REMOTE_RELATIVE_PATH")
    local_text, remote_relative = text.rsplit(":", 1)
    local = Path(local_text).resolve()
    if not local.exists():
        raise ToolError(f"attachment not found: {local}")
    normalized = posixpath.normpath(remote_relative.replace("\\", "/"))
    if normalized.startswith("../") or normalized in {"", ".", ".."} or normalized.startswith("/"):
        raise ToolError(f"unsafe attachment destination: {remote_relative}")
    return local, normalized


def runtime_env(profile: Profile, expected_head: str, run_id: str, timeout: int) -> str:
    values = {key: profile.get(key) for key in RUNTIME_PROFILE_KEYS if profile.get(key)}
    values.update(
        {
            "SERVER_TOOL_EXPECTED_HEAD": expected_head,
            "SERVER_TOOL_SOURCE_BRANCH": profile.require("REMOTE_BRANCH"),
            "SERVER_TOOL_TASK_ROOT": profile.task_root,
            "SERVER_TOOL_PROJECT_ROOT": profile.project_root,
            "SERVER_TOOL_RUN_ID": run_id,
            "SERVER_TOOL_RUN_TIMEOUT_SEC": str(timeout),
        }
    )
    return "".join(f"export {key}={shell_quote(value)}\n" for key, value in values.items())


def create_source_bundle(profile: Profile, output: Path) -> None:
    source_ref = f"refs/heads/{profile.require('LOCAL_BRANCH')}"
    run_local(["git", "bundle", "create", str(output), source_ref], profile.local_repo)


def input_hashes(local_paths: list[Path]) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for path in local_paths:
        files = [path] if path.is_file() else sorted(item for item in path.rglob("*") if item.is_file())
        for file in files:
            hashes[str(file)] = hashlib.sha256(file.read_bytes()).hexdigest()
    return hashes


def cmd_check(args: argparse.Namespace) -> int:
    profile = Profile.load(args.profile)
    branch, head = profile.source_identity()
    with Remote(profile) as remote:
        manifest = profile.require("CONTAINER_MANIFEST")
        command = (
            f"test -r {shell_quote(manifest)}; "
            f"grep -Fqx {shell_quote('container_name=' + profile.require('CONTAINER_NAME'))} "
            f"{shell_quote(manifest)}; "
            "command -v git >/dev/null; command -v setsid >/dev/null; command -v timeout >/dev/null"
        )
        remote.run(command)
        gpu_state = require_idle_profile_gpus(remote, profile)
        _, out, _ = remote.run(
            f"test -e {shell_quote(profile.task_root)} && "
            f"cat {shell_quote(profile.task_root + '/.server-tool-task')} || true",
            check=False,
        )
    print(
        json.dumps(
            {
                "branch": branch,
                "head": head,
                "task_owner": out.strip(),
                "task_initialized": bool(out.strip()),
                "gpus": gpu_state,
            },
            indent=2,
        )
    )
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    profile = Profile.load(args.profile)
    _, head = profile.source_identity()
    script = Path(args.script).resolve()
    if not script.is_file():
        raise ToolError(f"run script not found: {script}")
    scan_script(script)
    test_md = script.with_name("TEST.md")
    if not test_md.is_file():
        raise ToolError(f"TEST.md must accompany run.sh: {test_md}")
    attachments = [parse_attachment(value) for value in args.attach]
    name = safe_name(args.name, "run name")
    run_id = f"{profile.require('PROFILE_NAME')}.{name}.{time.time_ns()}"
    root = run_root(profile, name)

    with tempfile.TemporaryDirectory(prefix="server-tool-") as temp_text:
        temp = Path(temp_text)
        bundle = temp / "source.bundle"
        paths_for_hash = [script, test_md, *(local for local, _ in attachments)]
        invocation = {
            "profile": str(profile.path),
            "run_name": name,
            "script": str(script),
            "attachments": [{"local": str(local), "remote": remote} for local, remote in attachments],
            "source_head": head,
            "input_sha256": input_hashes(paths_for_hash),
            "allow_busy_gpus": args.allow_busy_gpus,
        }
        with Remote(profile) as remote:
            invocation["gpu_preflight"] = require_idle_profile_gpus(
                remote, profile, allow_occupied=args.allow_busy_gpus
            )
            verify_task_owner(remote, profile, create=True)
            project_check = (
                f"if [ ! -e {shell_quote(profile.project_root)} ]; then echo absent; exit 0; fi; "
                f"test -d {shell_quote(profile.project_root + '/.git')}; "
                f"test -f {shell_quote(profile.project_root + '/.git/server-tool-owner')}; "
                f"grep -Fqx {shell_quote('profile=' + profile.require('PROFILE_NAME'))} "
                f"{shell_quote(profile.project_root + '/.git/server-tool-owner')}; "
                f"test \"$(git -C {shell_quote(profile.project_root)} rev-parse HEAD)\" = {shell_quote(head)}; "
                f"test -z \"$(git -C {shell_quote(profile.project_root)} status --porcelain)\"; "
                "echo reuse"
            )
            _, project_out, _ = remote.run(project_check)
            source_mode = project_out.strip()
            if source_mode not in {"absent", "reuse"}:
                raise ToolError(f"unexpected remote source mode: {source_mode}")
            invocation["remote_source_mode"] = source_mode
            code, _, _ = remote.run(f"test ! -e {shell_quote(root)}", check=False)
            if code:
                raise ToolError(f"run already exists: {root}")
            remote.run(f"umask 077; mkdir -p {shell_quote(root + '/input')} {shell_quote(root + '/control')}")
            if source_mode == "absent":
                create_source_bundle(profile, bundle)
                remote.put_file(bundle, root + "/input/source.bundle", 0o600)
            remote.put_file(script, root + "/input/run.sh", 0o700)
            remote.put_file(test_md, root + "/input/TEST.md", 0o600)
            remote.put_file(REMOTE_RUNNER, root + "/input/remote_runner.sh", 0o700)
            for local, destination in attachments:
                remote.put_tree(local, root + "/input/" + destination)
            remote.put_text(runtime_env(profile, head, run_id, args.timeout), root + "/input/runtime.env", 0o600)
            remote.put_text(json.dumps(invocation, indent=2, sort_keys=True) + "\n", root + "/input/invocation.json", 0o600)
            launch = (
                f"cd {shell_quote(root)} && "
                f"setsid -f env SERVER_TOOL_RUN_ROOT={shell_quote(root)} "
                f"bash input/remote_runner.sh </dev/null >/dev/null 2>&1; "
                "for attempt in $(seq 1 100); do "
                "if [ -s control/runner.pgid ]; then cat control/runner.pgid; exit 0; fi; "
                "sleep 0.1; "
                "done; "
                "echo 'runner did not publish its PGID' >&2; exit 124"
            )
            _, out, _ = remote.run(launch)
    print(json.dumps({"run": name, "run_id": run_id, "runner_pgid": out.strip(), "head": head}, indent=2))
    return 0


def read_state(profile: Profile, name: str) -> dict[str, str]:
    root = run_root(profile, name)
    command = (
        f"test -d {shell_quote(root)}; "
        f"for f in state runner.pgid started_at finished_at exit_code; do "
        f"p={shell_quote(root + '/control')}/$f; "
        "if [ -f \"$p\" ]; then printf '%s=' \"$f\"; cat \"$p\"; fi; done"
    )
    with Remote(profile) as remote:
        verify_task_owner(remote, profile)
        _, out, _ = remote.run(command)
    state: dict[str, str] = {}
    for line in out.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            state[key] = value
    return state


def cmd_status(args: argparse.Namespace) -> int:
    profile = Profile.load(args.profile)
    print(json.dumps(read_state(profile, args.name), indent=2, sort_keys=True))
    return 0


def cmd_logs(args: argparse.Namespace) -> int:
    profile = Profile.load(args.profile)
    root = run_root(profile, args.name)
    log_name = "stderr.log" if args.stderr else "stdout.log"
    with Remote(profile) as remote:
        verify_task_owner(remote, profile)
        _, out, _ = remote.run(
            f"test -f {shell_quote(root + '/output/' + log_name)} && "
            f"tail -n {int(args.lines)} -- {shell_quote(root + '/output/' + log_name)}"
        )
    sys.stdout.write(out)
    return 0


def cmd_wait(args: argparse.Namespace) -> int:
    profile = Profile.load(args.profile)
    deadline = time.monotonic() + args.timeout
    while True:
        state = read_state(profile, args.name)
        if state.get("state") in {"succeeded", "failed", "stopped"}:
            print(json.dumps(state, indent=2, sort_keys=True))
            return 0 if state.get("state") == "succeeded" else 1
        if time.monotonic() >= deadline:
            raise ToolError(f"wait timed out after {args.timeout}s")
        time.sleep(min(args.poll, max(0.1, deadline - time.monotonic())))


def cmd_fetch(args: argparse.Namespace) -> int:
    profile = Profile.load(args.profile)
    root = run_root(profile, args.name)
    destination = Path(args.destination).resolve() if args.destination else profile.artifact_root / args.name
    if destination.exists():
        raise ToolError(f"local artifact destination already exists: {destination}")
    with Remote(profile) as remote:
        verify_task_owner(remote, profile)
        remote.get_tree(root + "/output", destination / "output")
        remote.get_tree(root + "/control", destination / "control")
    print(destination)
    return 0


def cmd_stop(args: argparse.Namespace) -> int:
    profile = Profile.load(args.profile)
    root = run_root(profile, args.name)
    control = root + "/control"
    command = (
        f"test -f {shell_quote(control + '/runner.pgid')}; "
        f"test -f {shell_quote(control + '/run.id')}; "
        f"pgid=$(cat {shell_quote(control + '/runner.pgid')}); "
        f"run_id=$(cat {shell_quote(control + '/run.id')}); "
        "case \"$pgid\" in ''|*[!0-9]*) exit 65;; esac; "
        "actual=$(ps -o pgid= -p \"$pgid\" | tr -d ' '); test \"$actual\" = \"$pgid\"; "
        "tr '\\0' '\\n' < \"/proc/$pgid/environ\" | grep -Fqx \"SERVER_TOOL_RUN_ID=$run_id\"; "
        "kill -TERM -- \"-$pgid\"; "
        "for i in $(seq 1 30); do ps -g \"$pgid\" >/dev/null 2>&1 || exit 0; sleep 1; done; "
        "exit 124"
    )
    with Remote(profile) as remote:
        verify_task_owner(remote, profile)
        remote.run(command, timeout=40)
    print(f"stop requested for {args.name}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check").set_defaults(func=cmd_check)

    run = sub.add_parser("run")
    run.add_argument("--name", required=True)
    run.add_argument("--script", required=True)
    run.add_argument("--attach", action="append", default=[])
    run.add_argument("--timeout", type=int, default=900)
    run.add_argument(
        "--allow-busy-gpus",
        action="store_true",
        help="run on occupied selected GPUs after explicit user authorization",
    )
    run.set_defaults(func=cmd_run)

    for command, func in (("status", cmd_status), ("logs", cmd_logs), ("wait", cmd_wait), ("fetch", cmd_fetch), ("stop", cmd_stop)):
        item = sub.add_parser(command)
        item.add_argument("--name", required=True)
        if command == "logs":
            item.add_argument("--stderr", action="store_true")
            item.add_argument("--lines", type=int, default=200)
        if command == "wait":
            item.add_argument("--timeout", type=int, default=900)
            item.add_argument("--poll", type=float, default=5.0)
        if command == "fetch":
            item.add_argument("--destination")
        item.set_defaults(func=func)
    return parser


def main() -> int:
    try:
        args = build_parser().parse_args()
        return args.func(args)
    except (ToolError, ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

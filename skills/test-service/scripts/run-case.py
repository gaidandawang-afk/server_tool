#!/usr/bin/env python3
"""Invoke the generic runner with the committed test-service bundle."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--case", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--summary", action="store_true", help="fetch only result/assertions/provenance; retain full logs remotely")
    parser.add_argument(
        "--allow-busy-gpus",
        action="store_true",
        help="run on occupied selected GPUs after explicit user authorization",
    )
    args = parser.parse_args()

    skill_root = Path(__file__).resolve().parents[1]
    repo_root = skill_root.parents[1]
    case_root = (skill_root / "cases" / args.case).resolve()
    run_sh = case_root / "run.sh"
    if not run_sh.is_file() or not (case_root / "TEST.md").is_file():
        print(f"invalid committed case: {case_root}", file=sys.stderr)
        return 2
    if args.repeat < 1:
        print("--repeat must be at least 1", file=sys.stderr)
        return 2
    cli = [sys.executable, str(repo_root / "tools" / "server_tool.py"), "--profile", args.profile]
    for index in range(1, args.repeat + 1):
        name = args.name if args.repeat == 1 else f"{args.name}-{index:02d}"
        run_command = cli + [
            "run",
            "--name",
            name,
            "--script",
            str(run_sh),
            "--attach",
            f"{skill_root / 'scripts'}:units",
            "--attach",
            f"{skill_root / 'assets' / 'sglang'}:assets",
            "--timeout",
            str(args.timeout),
        ]
        if args.allow_busy_gpus:
            run_command.append("--allow-busy-gpus")
        if subprocess.call(run_command):
            return 1
        # Include bounded Git preparation before the test's own timeout starts.
        wait_command = cli + ["wait", "--name", name, "--timeout", str(args.timeout + 600)]
        wait_code = subprocess.call(wait_command)
        fetch_command = cli + ["fetch", "--name", name]
        if args.summary:
            fetch_command.append("--summary")
        fetch_code = subprocess.call(fetch_command)
        if wait_code or fetch_code:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

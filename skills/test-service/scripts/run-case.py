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
    parser.add_argument("--resume", action="store_true", help="observe one existing run; never submit or restart it")
    parser.add_argument("--destination", help="new local artifact directory (single run only)")
    parser.add_argument(
        "--allow-busy-gpus",
        action="store_true",
        help="run on occupied selected GPUs after explicit user authorization",
    )
    args = parser.parse_args()
    if args.repeat != 1 and (args.resume or args.destination):
        parser.error("--resume and --destination require --repeat 1")

    skill_root = Path(__file__).resolve().parents[1]
    repo_root = skill_root.parents[1]
    case_root = (skill_root / "cases" / args.case).resolve()
    run_sh = case_root / "run.sh"
    if not case_root.is_relative_to(skill_root / "cases") or not run_sh.is_file() or not (case_root / "TEST.md").is_file():
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
        if not args.resume and subprocess.call(run_command):
            print("Submission not confirmed; query this run name before submitting again.", file=sys.stderr)
            return 1
        # Include bounded Git preparation before the test's own timeout starts.
        wait_command = cli + ["wait", "--name", name, "--timeout", str(args.timeout + 600)]
        wait_code = subprocess.call(wait_command)
        fetch_command = cli + ["fetch", "--name", name]
        if args.summary:
            fetch_command.append("--summary")
        if args.destination:
            fetch_command.extend(["--destination", args.destination])
        fetched = subprocess.run(fetch_command, capture_output=True, text=True)
        sys.stdout.write(fetched.stdout)
        sys.stderr.write(fetched.stderr)
        if fetched.returncode:
            print("Evidence not fetched; resume this run with a new --destination.", file=sys.stderr)
            return 1
        destination = fetched.stdout.strip()
        if not destination:
            print("fetch returned no artifact path", file=sys.stderr)
            return 2
        # A terminal artifact can prove success even if the wait connection failed.
        result_code = subprocess.call([
            sys.executable, str(skill_root / "scripts" / "summarize-result.py"), destination,
            "--expected-case", args.case,
        ])
        if result_code:
            if result_code == 2:
                print(f"Evidence incomplete (wait exit={wait_code}); check summary issues before resuming.", file=sys.stderr)
            return result_code
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Read a fetched run without connecting to S or loading full logs."""

import argparse
import json
from pathlib import Path


def summarize(root: Path, expected_case: str | None = None) -> tuple[dict, int]:
    root = root.resolve()
    issues = []
    state = "unknown"
    control_exit = None
    result = {}
    try:
        state = (root / "control/state").read_text().strip()
        control_exit = int((root / "control/exit_code").read_text().strip())
        result = json.loads((root / "output/result.json").read_text(encoding="utf-8"))
        if not isinstance(result, dict):
            raise ValueError("result must be an object")
    except (OSError, ValueError) as exc:
        issues.append(f"incomplete evidence: {type(exc).__name__}")
        result = {}

    assertions = result.get("assertions", [])
    if not isinstance(assertions, list) or any(not isinstance(a, dict) for a in assertions):
        issues.append("invalid assertions")
        assertions = []
    source = result.get("source") or {}
    commit = source.get("source_commit") if isinstance(source, dict) else None
    case = None
    try:
        invocation = json.loads((root / "output/invocation.json").read_text(encoding="utf-8"))
        script = invocation["script"].replace("\\", "/")
        marker = "skills/test-service/cases/"
        if marker in script and script.endswith("/run.sh"):
            case = script.rsplit(marker, 1)[1][:-len("/run.sh")]
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        pass
    if expected_case is not None and case != expected_case.replace("\\", "/"):
        issues.append(f"case mismatch: expected {expected_case}, recorded {case}")
    if state not in {"succeeded", "failed", "stopped"}:
        issues.append("no terminal state; resume observation")
    if result.get("exit_code") != control_exit:
        issues.append("result/control exit codes differ")
    if state == "succeeded" and control_exit != 0:
        issues.append("succeeded state has nonzero exit code")
    if state == "succeeded" and (not assertions or not commit):
        issues.append("success lacks assertions or source commit")

    failed = [a for a in assertions if a.get("pass") is not True]
    passed = (state == "succeeded" and control_exit == 0 and bool(assertions)
              and not failed and result.get("pass") is True)
    verdict = "INCOMPLETE" if issues else "PASS" if passed else "FAIL"
    summary = {
        "verdict": verdict,
        "state": state,
        "run_id": result.get("run_id"),
        "case": case,
        "source_commit": commit,
        "exit_code": control_exit,
        "assertions": {"passed": len(assertions) - len(failed), "total": len(assertions)},
        "failed_assertions": [
            {key: str(a.get(key, ""))[:300] for key in ("label", "expected", "actual")}
            for a in failed[:5]
        ],
        "omitted_failures": max(0, len(failed) - 5),
        "issues": issues,
        "result_path": str(root / "output/result.json"),
    }
    return summary, {"PASS": 0, "FAIL": 1, "INCOMPLETE": 2}[verdict]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact_directory", type=Path)
    parser.add_argument("--expected-case", help="require the case recorded in the original invocation")
    args = parser.parse_args()
    summary, code = summarize(args.artifact_directory, args.expected_case)
    print(json.dumps(summary, indent=2, ensure_ascii=True))
    return code


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--oracle", required=True)
    parser.add_argument("--response", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    registry = json.loads(Path(args.registry).read_text(encoding="utf-8"))
    entries = {entry["id"]: entry for entry in registry["entries"]}
    if args.oracle not in entries:
        raise SystemExit(f"oracle not found: {args.oracle}")
    expected = entries[args.oracle]["output_ids"]
    response = json.loads(Path(args.response).read_text(encoding="utf-8"))
    actual = response.get("output_ids")
    result = {
        "schema_version": "server-tool.precision-result.v1",
        "oracle_id": args.oracle,
        "expected_output_ids": expected,
        "actual_output_ids": actual,
        "expected_token_count": len(expected),
        "actual_token_count": len(actual) if isinstance(actual, list) else None,
        "accurate": actual == expected,
    }
    Path(args.output).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0 if result["accurate"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

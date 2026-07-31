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
    parser.add_argument("--allow-known", action="store_true")
    args = parser.parse_args()

    registry = json.loads(Path(args.registry).read_text(encoding="utf-8"))
    entries = {entry["id"]: entry for entry in registry["entries"]}
    if args.oracle not in entries:
        raise SystemExit(f"oracle not found: {args.oracle}")
    expected = entries[args.oracle]["output_ids"]
    accepted = (
        entries[args.oracle].get("known_output_ids", [expected])
        if args.allow_known
        else [expected]
    )
    response = json.loads(Path(args.response).read_text(encoding="utf-8"))
    actual = response.get("output_ids")
    matched_index = next(
        (index for index, output_ids in enumerate(accepted) if actual == output_ids),
        None,
    )
    result = {
        "schema_version": "server-tool.precision-result.v1",
        "oracle_id": args.oracle,
        "expected_output_ids": expected,
        "accepted_output_ids": accepted,
        "allow_known": args.allow_known,
        "matched_output_index": matched_index,
        "actual_output_ids": actual,
        "expected_token_count": len(expected),
        "actual_token_count": len(actual) if isinstance(actual, list) else None,
        "accurate": matched_index is not None,
    }
    Path(args.output).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0 if result["accurate"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

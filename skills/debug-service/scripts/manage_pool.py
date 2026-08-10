#!/usr/bin/env python3
"""Manage the debug experience pool: add entries, vote, list ranked."""

import json
import sys
from pathlib import Path
from datetime import date

POOL_PATH = Path(__file__).resolve().parent.parent / "pool.json"

VALID_CATEGORIES = {
    "code-pattern", "test-script", "watchdog", "retry",
    "scale-down", "cache", "server-tool", "environment",
}

ENTRY_ID_PREFIX = "exp-"


def load():
    if not POOL_PATH.exists():
        return []
    with POOL_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)


def save(entries):
    with POOL_PATH.open("w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2, ensure_ascii=False)
        f.write("\n")


def next_entry_id(entries):
    max_numeric_id = 0
    for entry in entries:
        entry_id = entry.get("id", "")
        if not entry_id.startswith(ENTRY_ID_PREFIX):
            continue
        suffix = entry_id[len(ENTRY_ID_PREFIX):]
        if suffix.isdigit():
            max_numeric_id = max(max_numeric_id, int(suffix))
    return f"{ENTRY_ID_PREFIX}{max_numeric_id + 1:03d}"


def cmd_list(args):
    entries = load()
    entries.sort(key=lambda e: e["score"], reverse=True)
    top_arg = args.get("top")
    selected = entries if top_arg is None else entries[:int(top_arg)]
    for e in selected:
        print(f"[{e['id']}] ({e['score']:+.0f}) {e['category']}: {e['title']}")
        print(f"    {e['content']}")
        print()


def cmd_add(args):
    cat = args["category"]
    if cat not in VALID_CATEGORIES:
        print(f"ERROR: invalid category '{cat}'. Valid: {sorted(VALID_CATEGORIES)}")
        sys.exit(1)
    entries = load()
    entry = {
        "id": next_entry_id(entries),
        "category": cat,
        "title": args["title"],
        "content": args["content"],
        "score": 2,
        "votes": [
            {"delta": 2, "reason": "Initial entry from session", "date": str(date.today())}
        ],
    }
    entries.append(entry)
    save(entries)
    print(f"Added {entry['id']}: {entry['title']}")


def cmd_vote(args):
    eid = args["id"]
    delta = int(args["delta"])
    reason = args.get("reason", "no reason given")
    entries = load()
    for e in entries:
        if e["id"] == eid:
            e["score"] += delta
            e["votes"].append({
                "delta": delta,
                "reason": reason,
                "date": str(date.today()),
            })
            save(entries)
            print(f"Voted {delta:+d} on {eid}: {e['title']} (new score: {e['score']:+.0f})")
            return
    print(f"ERROR: entry {eid} not found")
    sys.exit(1)


def cmd_summary(args):
    entries = load()
    by_cat = {}
    for e in entries:
        by_cat.setdefault(e["category"], []).append(e)
    print(f"Total entries: {len(entries)}")
    for cat in sorted(by_cat):
        items = sorted(by_cat[cat], key=lambda x: x["score"], reverse=True)
        top_title = items[0]["title"] if items else "-"
        print(f"  {cat}: {len(items)} entries (top: {top_title[:60]})")


def main():
    if len(sys.argv) < 2:
        print("usage: manage_pool.py <list|add|vote|summary> [args]")
        sys.exit(1)
    cmd = sys.argv[1]
    args = {}
    i = 2
    while i < len(sys.argv):
        if sys.argv[i].startswith("--"):
            key = sys.argv[i][2:].replace("-", "_")
            val = sys.argv[i + 1] if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith("--") else "true"
            args[key] = val
            if val != "true":
                i += 2
            else:
                i += 1
        else:
            if "id" not in args and cmd == "vote":
                args["id"] = sys.argv[i]
                i += 1
            elif "delta" not in args and cmd == "vote":
                args["delta"] = sys.argv[i]
                i += 1
            else:
                i += 1
    {"list": cmd_list, "add": cmd_add, "vote": cmd_vote, "summary": cmd_summary}[cmd](args)


if __name__ == "__main__":
    main()

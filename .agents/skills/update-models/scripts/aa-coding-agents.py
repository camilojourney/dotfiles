#!/usr/bin/env python3
"""Print the Artificial Analysis Coding Agent Index as a table.

The page renders its charts with JavaScript, so a plain page fetch shows
"Not publicly available". The data is embedded in the Next.js payload
(self.__next_f chunks) as `benchmarkRows`; this decodes it directly.

Usage: aa-coding-agents.py [--json]
"""
import json
import re
import sys
import urllib.request

URL = "https://artificialanalysis.ai/agents/coding-agents"


def fetch_rows():
    req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0 (Macintosh) Chrome/140"})
    raw = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)</script>', raw, re.S)
    payload = "".join(json.loads('"' + c + '"') for c in chunks)
    decoder = json.JSONDecoder()
    rows, seen = [], set()
    # Rows appear in several chart payloads (benchmarkRows and others), so
    # decode every agent-result object rather than one named array.
    for match in re.finditer(r'\{"id":"[0-9a-f]{32}","isDefault"', payload):
        try:
            row, _ = decoder.raw_decode(payload[match.start():])
        except ValueError:
            continue
        if "agentName" not in row or "display" not in row or row["id"] in seen:
            continue
        seen.add(row["id"])
        mean = row.get("mean") or {}
        rows.append({
            "agent": row["display"]["agent"],
            "model": row["display"]["model"],
            "index": row.get("indexScore"),
            "cost_usd_per_task": mean.get("costUsd"),
            "minutes_per_task": (mean.get("agentWallTimeSec") or 0) / 60 or None,
            "unavailable": row.get("isUnavailable", False),
        })
    if not rows:
        sys.exit("aa-coding-agents: no agent result rows found - the page layout changed; read it in a browser instead")
    return sorted(rows, key=lambda r: -(r["index"] or 0))


def main():
    rows = fetch_rows()
    if "--json" in sys.argv:
        json.dump(rows, sys.stdout, indent=2)
        return
    fmt = lambda v, k=1: "-" if v is None else f"{v:.{k}f}"
    print(f"{'index':>6} {'$/task':>7} {'min':>5}  agent / model")
    for r in rows:
        index = None if r["index"] is None else r["index"] * 100
        print(f"{fmt(index):>6} {fmt(r['cost_usd_per_task'], 2):>7} {fmt(r['minutes_per_task']):>5}  "
              f"{r['agent']} / {r['model']}{'  (unavailable)' if r['unavailable'] else ''}")


if __name__ == "__main__":
    main()

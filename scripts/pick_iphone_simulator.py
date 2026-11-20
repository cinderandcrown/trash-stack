#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""Print the UDID of a suitable single-screen iPhone simulator.

Examples:
  pick_iphone_simulator.py
  pick_iphone_simulator.py --prefer "iPhone 16 Pro" --prefer "iPhone 16"
  pick_iphone_simulator.py --prefer "iPhone SE (3rd generation)" --prefer "iPhone SE"
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys

DEFAULT_PREFERRED = (
    "iPhone 16 Pro",
    "iPhone 16",
    "iPhone 17",
    "iPhone 15 Pro",
    "iPhone 15",
    "iPhone 14",
    "iPhone 13",
    "iPhone 12",
    "iPhone 11",
    "iPhone SE",
)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--prefer",
        action="append",
        default=[],
        help="Preferred name prefix/substring (repeatable; earlier wins)",
    )
    ap.add_argument(
        "--print-name",
        action="store_true",
        help="Also print device name on stderr (always) and as second stdout line",
    )
    args = ap.parse_args()
    preferred = tuple(args.prefer) if args.prefer else DEFAULT_PREFERRED

    raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        text=True,
    )
    devices = json.loads(raw)["devices"]
    cands: list[tuple[int, str, str, str]] = []
    for runtime, items in devices.items():
        if "iOS" not in runtime:
            continue
        for device in items:
            name = device.get("name", "")
            if not name.startswith("iPhone"):
                continue
            if "Duo" in name or "Fold" in name:
                continue
            rank = next(
                (i for i, pref in enumerate(preferred) if name.startswith(pref) or pref in name),
                99,
            )
            cands.append((rank, name, device["udid"], runtime))
    if not cands:
        print("No suitable iPhone simulator found", file=sys.stderr)
        return 1
    # Prefer exact prefer-list matches; among same rank, longer/more specific name first.
    cands.sort(key=lambda t: (t[0], -len(t[1]), t[1]))
    rank, name, udid, runtime = cands[0]
    if rank >= 99 and args.prefer:
        print(
            f"WARN no match for prefer={list(preferred)}; falling back to {name}",
            file=sys.stderr,
        )
    print(f"Picked {name} ({runtime}) rank={rank}", file=sys.stderr)
    print(udid)
    if args.print_name:
        print(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

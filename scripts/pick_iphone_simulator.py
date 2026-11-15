#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""Print the UDID of a suitable single-screen iPhone simulator."""

from __future__ import annotations

import json
import subprocess
import sys

PREFERRED = (
    "iPhone 16",
    "iPhone 15",
    "iPhone 14",
    "iPhone 13",
    "iPhone 12",
    "iPhone 11",
    "iPhone SE",
)


def main() -> int:
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
            rank = next((i for i, prefix in enumerate(PREFERRED) if name.startswith(prefix)), 99)
            cands.append((rank, name, device["udid"], runtime))
    if not cands:
        print("No suitable iPhone simulator found", file=sys.stderr)
        return 1
    cands.sort()
    rank, name, udid, runtime = cands[0]
    print(f"Picked {name} ({runtime})", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

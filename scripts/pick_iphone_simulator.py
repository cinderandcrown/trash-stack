#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""Print the UDID of a suitable single-screen iPhone simulator.

Examples:
  pick_iphone_simulator.py --prefer "iPhone 16 Pro" --prefer "iPhone 17 Pro"
  pick_iphone_simulator.py --prefer "iPhone SE (3rd generation)" --create
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time

DEFAULT_PREFERRED = (
    "iPhone 16 Pro",
    "iPhone 17 Pro",
    "iPhone 15 Pro",
    "iPhone 16",
    "iPhone 17",
    "iPhone 15",
    "iPhone 14",
    "iPhone SE (3rd generation)",
    "iPhone SE",
)


def list_devices() -> dict:
    raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        text=True,
    )
    return json.loads(raw)["devices"]


def list_devicetypes() -> list[dict]:
    raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "devicetypes", "-j"],
        text=True,
    )
    return json.loads(raw).get("devicetypes", [])


def list_runtimes() -> list[dict]:
    raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "runtimes", "-j"],
        text=True,
    )
    return json.loads(raw).get("runtimes", [])


def rank_name(name: str, preferred: tuple[str, ...], allow_max: bool) -> int | None:
    if not name.startswith("iPhone"):
        return None
    if "Duo" in name or "Fold" in name:
        return None
    if not allow_max and "Max" in name:
        return None
    for i, pref in enumerate(preferred):
        if name.startswith(pref) or pref in name:
            return i
    return 99


def pick_existing(preferred: tuple[str, ...], allow_max: bool) -> tuple[int, str, str, str] | None:
    devices = list_devices()
    cands: list[tuple[int, str, str, str]] = []
    for runtime, items in devices.items():
        if "iOS" not in runtime:
            continue
        for device in items:
            name = device.get("name", "")
            rank = rank_name(name, preferred, allow_max=allow_max)
            if rank is None:
                continue
            cands.append((rank, name, device["udid"], runtime))
    if not cands:
        return None
    # Prefer prefer-list hits; among ties, shorter names (Pro before Pro Max when Max allowed).
    cands.sort(key=lambda t: (t[0], len(t[1]), t[1]))
    return cands[0]


def is_generic_ios_runtime(runtime_id: str, name: str = "") -> bool:
    """Accept shared iOS runtimes only — reject device-bundled ids like iOS-27-2-iPhone19-4."""
    rid = runtime_id or ""
    # Generic: com.apple.CoreSimulator.SimRuntime.iOS-18-0 (no device suffix).
    if re.search(r"SimRuntime\.iOS-\d+-\d+$", rid):
        return True
    # Also accept plain "iOS 18.0" style names without an iPhone model token.
    if "iOS" in (name or "") and "iPhone" not in rid and "iPhone" not in (name or ""):
        if re.search(r"iOS-\d+-\d+$", rid) or re.search(r"iOS \d+", name or ""):
            return "iPhone" not in rid
    return False


def resolve_create_pairs(prefer_name: str) -> list[tuple[str, str]]:
    """Return candidate (deviceTypeIdentifier, runtimeIdentifier) pairs, newest first."""
    types = list_devicetypes()
    # Exact / startswith match on device type name.
    type_id = None
    for t in types:
        n = t.get("name", "")
        if n == prefer_name or n.startswith(prefer_name):
            type_id = t.get("identifier")
            break
    if not type_id:
        # Fuzzy: SE → any SE type; Pro (non-Max) → first Pro without Max.
        for t in types:
            n = t.get("name", "")
            if "SE" in prefer_name and "SE" in n:
                type_id = t.get("identifier")
                break
            if "Pro" in prefer_name and "Pro" in n and "Max" not in n and "iPhone" in n:
                type_id = t.get("identifier")
                break
    if not type_id:
        return []
    runtimes = [
        r
        for r in list_runtimes()
        if r.get("isAvailable")
        and "iOS" in (r.get("name") or "")
        and is_generic_ios_runtime(r.get("identifier") or "", r.get("name") or "")
    ]
    if not runtimes:
        # Last resort: any available iOS runtime that does not embed an iPhone model token.
        runtimes = [
            r
            for r in list_runtimes()
            if r.get("isAvailable")
            and "iOS" in (r.get("name") or "")
            and "iPhone" not in (r.get("identifier") or "")
        ]
    runtimes.sort(key=lambda r: r.get("version", ""), reverse=True)
    return [(type_id, r["identifier"]) for r in runtimes]


def create_device(prefer_name: str) -> tuple[int, str, str, str] | None:
    pairs = resolve_create_pairs(prefer_name)
    if not pairs:
        print(f"Cannot resolve device type/runtime for create '{prefer_name}'", file=sys.stderr)
        return None
    name = f"TrashStack-{re.sub(r'[^A-Za-z0-9]+', '-', prefer_name)}-{int(time.time()) % 100000}"
    last_err: Exception | None = None
    for type_id, runtime in pairs:
        try:
            udid = subprocess.check_output(
                ["xcrun", "simctl", "create", name, type_id, runtime],
                text=True,
                stderr=subprocess.STDOUT,
            ).strip()
        except subprocess.CalledProcessError as e:
            last_err = e
            print(
                f"simctl create failed for {prefer_name} with {runtime}: {e}",
                file=sys.stderr,
            )
            continue
        print(f"Created {name} ({type_id} / {runtime})", file=sys.stderr)
        return 0, name, udid, runtime
    print(f"simctl create failed for {prefer_name}: {last_err}", file=sys.stderr)
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--prefer",
        action="append",
        default=[],
        help="Preferred name prefix/substring (repeatable; earlier wins)",
    )
    ap.add_argument(
        "--allow-max",
        action="store_true",
        help="Allow Pro Max devices (default: exclude Max for Pro evidence)",
    )
    ap.add_argument(
        "--create",
        action="store_true",
        help="If no prefer match exists, create the first prefer name from available types",
    )
    ap.add_argument(
        "--require-match",
        action="store_true",
        help="Fail if no prefer-list match (do not fall back to unrelated phones)",
    )
    args = ap.parse_args()
    preferred = tuple(args.prefer) if args.prefer else DEFAULT_PREFERRED

    picked = pick_existing(preferred, allow_max=args.allow_max)
    if picked and picked[0] < 99:
        rank, name, udid, runtime = picked
        print(f"Picked {name} ({runtime}) rank={rank}", file=sys.stderr)
        print(udid)
        return 0

    if args.create and preferred:
        created = create_device(preferred[0])
        if created:
            _, name, udid, runtime = created
            print(f"Picked {name} ({runtime}) rank=created", file=sys.stderr)
            print(udid)
            return 0

    if args.require_match or (args.create and not picked):
        print(f"No matching simulator for prefer={list(preferred)}", file=sys.stderr)
        return 1

    if picked:
        rank, name, udid, runtime = picked
        print(
            f"WARN no match for prefer={list(preferred)}; falling back to {name}",
            file=sys.stderr,
        )
        print(f"Picked {name} ({runtime}) rank={rank}", file=sys.stderr)
        print(udid)
        return 0

    print("No suitable iPhone simulator found", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""CI gate: shipping AppIcon-1024.png must be Nicholas's bandit dumpster icon A."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

EXPECTED_MD5 = "a616467312ef6339d3219b145ce7adec"
ICON_REL = Path("TrashStack/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    path = root / ICON_REL
    if not path.is_file():
        print(f"FAIL: missing {ICON_REL}", file=sys.stderr)
        return 1
    digest = hashlib.md5(path.read_bytes()).hexdigest()
    if digest != EXPECTED_MD5:
        print(
            f"FAIL: {ICON_REL} md5={digest} (expected {EXPECTED_MD5} — "
            "cyberpunk bandit dumpster icon A)",
            file=sys.stderr,
        )
        return 1
    print(f"OK AppIcon-1024.png md5={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

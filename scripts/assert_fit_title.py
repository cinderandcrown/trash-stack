#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""Reject C&C splash / blank frames labeled as a title shot."""

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "smoke-artifacts/fit/se-title.png")
    data = path.read_bytes()
    pos = 8
    w = h = ct = None
    idat = bytearray()
    while pos + 8 <= len(data):
        ln = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + ln]
        pos += 12 + ln
        if ctype == b"IHDR":
            w, h, _bd, ct = struct.unpack(">IIBB", chunk[:10])
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
    if w is None or h is None or ct is None:
        print(f"Bad PNG {path}", file=sys.stderr)
        return 1
    raw = zlib.decompress(bytes(idat))
    bpp = 3 if ct == 2 else 4
    stride = w * bpp + 1
    bright = 0
    n = 0
    for y in range(int(h * 0.15), int(h * 0.55), max(1, h // 40)):
        row = raw[y * stride + 1 : (y + 1) * stride]
        for x in range(int(w * 0.15), int(w * 0.85), max(1, w // 40)):
            i = x * bpp
            r, g, b = row[i], row[i + 1], row[i + 2]
            n += 1
            if r + g + b > 180:
                bright += 1
    ratio = bright / max(1, n)
    print(f"{path.name} bright ratio={ratio:.3f} size={w}x{h}")
    if ratio < 0.02:
        print(f"{path} looks like C&C splash / blank — not the title screen", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

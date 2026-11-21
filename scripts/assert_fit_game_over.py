#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""Assert a fit/smoke PNG is a real game-over overlay (score/best/retry), not a bare board."""
from __future__ import annotations

import pathlib
import struct
import sys
import zlib


def load_rows(path: pathlib.Path):
    data = path.read_bytes()
    if len(data) < 200_000:
        raise SystemExit(f"FAIL game-over too small ({len(data)} B): {path}")
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"FAIL not PNG: {path}")
    pos = 8
    width = height = color_type = None
    idat = bytearray()
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            width, height, _, color_type = struct.unpack(">IIBB", chunk[:10])
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
    raw = zlib.decompress(bytes(idat))
    bpp = 3 if color_type == 2 else 4
    stride = width * bpp + 1
    rows: list[bytearray] = []
    for y in range(height):
        start = y * stride
        filt = raw[start]
        row = bytearray(raw[start + 1 : start + stride])
        prev = rows[-1] if rows else bytearray(len(row))
        if filt == 1:
            for i in range(len(row)):
                row[i] = (row[i] + (row[i - bpp] if i >= bpp else 0)) & 255
        elif filt == 2:
            for i in range(len(row)):
                row[i] = (row[i] + prev[i]) & 255
        elif filt == 3:
            for i in range(len(row)):
                left = row[i - bpp] if i >= bpp else 0
                row[i] = (row[i] + ((left + prev[i]) // 2)) & 255
        elif filt == 4:

            def paeth(a, b, c):
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                return a if pa <= pb and pa <= pc else b if pb <= pc else c

            for i in range(len(row)):
                a = row[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                row[i] = (row[i] + paeth(a, b, c)) & 255
        rows.append(row)

    def sample(fx: float, fy: float):
        x = min(width - 1, int(width * fx))
        y = min(height - 1, int(height * fy))
        i = x * bpp
        return rows[y][i], rows[y][i + 1], rows[y][i + 2]

    return sample


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} path.png", file=sys.stderr)
        return 2
    path = pathlib.Path(sys.argv[1])
    sample = load_rows(path)
    # Reject phoenix splash.
    splash_dark = sum(
        1
        for fy in (0.2, 0.4, 0.6, 0.8)
        for fx in (0.2, 0.5, 0.8)
        if (lambda r, g, b: r < 40 and g < 40 and b < 40)(*sample(fx, fy))
    )
    orange = sum(
        1
        for fy in (0.35, 0.45, 0.55)
        for fx in (0.4, 0.5, 0.6)
        if (lambda r, g, b: r > 180 and g > 80 and b < 80)(*sample(fx, fy))
    )
    if splash_dark >= 6 and orange >= 2:
        print(f"FAIL game-over is publisher splash: {path.name}", file=sys.stderr)
        return 1

    panel = title = btn = 0
    for fy in (0.40, 0.48, 0.55, 0.62):
        for fx in (0.25, 0.40, 0.50, 0.60, 0.75):
            r, g, b = sample(fx, fy)
            if r < 30 and g < 40 and b < 50:
                panel += 1
    for fy in (0.34, 0.36, 0.38, 0.40):
        for fx in (0.35, 0.45, 0.55, 0.65):
            r, g, b = sample(fx, fy)
            if (g > 200 and b > 180 and r < 40) or (r > 180 and b > 100 and g < 120):
                title += 1
    for fy in (0.64, 0.66, 0.68):
        for fx in (0.25, 0.35, 0.45, 0.55, 0.65, 0.75):
            r, g, b = sample(fx, fy)
            if g > 180 and r > 100 and b > 100:
                btn += 1
    if panel < 8 or title < 1 or btn < 3:
        print(
            f"FAIL game-over missing overlay (panel={panel} title={title} btn={btn}): {path.name}",
            file=sys.stderr,
        )
        return 1
    print(f"fit game-over OK {path.name}: panel={panel} title={title} btn={btn}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

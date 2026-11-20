#!/usr/bin/env python3
"""Render GameCore play-verify dump into gameplay frames + a short GIF."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

COLORS = {
    "m": (120, 160, 210),  # metal
    "p": (250, 55, 185),   # plastic
    "g": (40, 230, 245),   # glass
    "a": (245, 185, 70),   # paper (p taken) — GameCore uses "p" for paper prefix too
    ".": (18, 20, 32),
}
# Material.rawValue prefixes: metal/plastic/glass/paper → m/p/g/p — paper collides with plastic.
# Dump uses first letter; plastic=p, paper=p. Distinguish via full dump if needed.
# Our dump uses prefix(1): metal=m, plastic=p, glass=g, paper=p. Treat second p as paper when
# we also write capital P for paper in a future dump; for now map p→plastic neon magenta.

MAT = {
    "m": (110, 155, 205),
    "p": (250, 50, 185),
    "g": (35, 230, 245),
    "P": (245, 185, 65),
    ".": (16, 18, 28),
}


def render_frame(grid: list[list[str]], meta: str, path: Path, cell: int = 36) -> Image.Image:
    rows = len(grid)
    cols = len(grid[0]) if rows else 8
    pad = 48
    w = cols * cell + pad * 2
    h = rows * cell + pad * 2 + 72
    img = Image.new("RGB", (w, h), (8, 10, 22))
    d = ImageDraw.Draw(img)
    # Neon bin frame
    d.rounded_rectangle(
        [pad - 10, pad - 10, pad + cols * cell + 10, pad + rows * cell + 10],
        radius=14,
        outline=(0, 230, 235),
        width=3,
    )
    d.rounded_rectangle(
        [pad - 6, pad - 6, pad + cols * cell + 6, pad + rows * cell + 6],
        radius=12,
        outline=(255, 40, 180),
        width=1,
    )
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            # paper also dumps as "p" — leave magenta; metal/glass distinct enough for verify
            color = MAT.get(ch, (200, 200, 200))
            x0 = pad + x * cell
            y0 = pad + y * cell
            if ch == ".":
                d.rectangle([x0 + 1, y0 + 1, x0 + cell - 2, y0 + cell - 2], fill=color)
            else:
                d.rounded_rectangle(
                    [x0 + 1, y0 + 1, x0 + cell - 2, y0 + cell - 2],
                    radius=6,
                    fill=color,
                    outline=(255, 255, 255),
                    width=1,
                )
                # icon dot
                d.ellipse(
                    [x0 + cell * 0.35, y0 + cell * 0.35, x0 + cell * 0.65, y0 + cell * 0.65],
                    fill=(255, 255, 255),
                )
    d.text((pad, h - 52), "TRASH STACK · play verify", fill=(0, 230, 235))
    d.text((pad, h - 30), meta[:90], fill=(220, 220, 230))
    img.save(path)
    return img


def main() -> int:
    src = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/trash-stack-play-verify.json")
    out_dir = Path(sys.argv[2] if len(sys.argv) > 2 else "/opt/cursor/artifacts")
    out_dir.mkdir(parents=True, exist_ok=True)
    data = json.loads(src.read_text())
    frames = data["frames"]
    images = []
    for i, grid in enumerate(frames):
        meta = f"frame {i} · score {data['finalScore']} · lvl {data['finalLevel']} · seed {data['seed']}"
        if i == len(frames) - 1:
            meta += " · FINAL" + (" · OVER" if data.get("over") else "")
        path = out_dir / f"play-verify-{i:02d}.png"
        images.append(render_frame(grid, meta, path))
        print("wrote", path)
    # Short GIF of the played loop
    gif = out_dir / "play-verify-loop.gif"
    if images:
        images[0].save(
            gif,
            save_all=True,
            append_images=images[1:],
            duration=700,
            loop=0,
        )
        print("wrote", gif)
    # Copy highlight still
    if images:
        hero = out_dir / "play-verify-gameplay.png"
        images[min(2, len(images) - 1)].save(hero)
        print("wrote", hero)
    log_path = out_dir / "play-verify-log.txt"
    log_path.write_text("\n".join(data.get("log", [])) + "\n")
    print("wrote", log_path)
    print(
        f"PLAYED seed={data['seed']} score={data['finalScore']} "
        f"level={data['finalLevel']} over={data.get('over')} frames={len(frames)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

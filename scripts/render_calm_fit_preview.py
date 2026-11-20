#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""Layout preview for Calm+Fit — Pro / SE title, play, game-over frames + ~60s GIF.
Not a substitute for CI simulator_smoke evidence; documents the intended fit."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path("/opt/cursor/artifacts/calm-fit")
OUT.mkdir(parents=True, exist_ok=True)

MAT = {
    "m": (110, 155, 205),
    "p": (250, 50, 185),
    "g": (35, 230, 245),
    "P": (245, 185, 65),
}
BANDIT_DIR = Path("/workspace/docs/art/bandit-shared/shared")


def font(size: int, bold: bool = False):
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def load_bandit(size: int = 48) -> Image.Image:
    path = BANDIT_DIR / "head-cheer.png"
    if path.exists():
        im = Image.open(path).convert("RGBA")
        im.thumbnail((size, size), Image.Resampling.LANCZOS)
        return im
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([4, 4, size - 4, size - 4], fill=(180, 140, 90, 255))
    return im


def phone_frame(w: int, h: int, island: bool) -> Image.Image:
    img = Image.new("RGB", (w, h), (8, 10, 18))
    d = ImageDraw.Draw(img)
    # Safe-area guides (not drawn as UI chrome — just keep content inset)
    if island:
        d.rounded_rectangle([w // 2 - 60, 10, w // 2 + 60, 34], radius=12, fill=(20, 22, 30))
    # Home indicator
    d.rounded_rectangle([w // 2 - 50, h - 14, w // 2 + 50, h - 8], radius=3, fill=(60, 65, 80))
    return img


def draw_title(w: int, h: int, island: bool) -> Image.Image:
    img = phone_frame(w, h, island)
    d = ImageDraw.Draw(img)
    top = 48 if island else 28
    bandit = load_bandit(90 if h > 700 else 72)
    bx = (w - bandit.width) // 2
    img = img.convert("RGBA")
    img.alpha_composite(bandit, (bx, top))
    img = img.convert("RGB")
    d = ImageDraw.Draw(img)
    d.text((w // 2 - 110, top + 100), "TRASH STACK", fill=(0, 230, 235), font=font(28, True))
    d.text((w // 2 - 90, top + 136), "Recycling Night Shift", fill=(220, 220, 230), font=font(14, True))
    d.rounded_rectangle([48, top + 180, w - 48, top + 228], radius=14, fill=(0, 200, 190))
    d.text((w // 2 - 28, top + 194), "PLAY", fill=(8, 12, 20), font=font(18, True))
    # Fine print inside safe bottom
    d.text((24, h - 36), "Free to play · odds shown · no wagers", fill=(160, 165, 180), font=font(10))
    return img


def layout_board(w: int, h: int):
    """~8px side margins; board takes height under HUD + SLAM strip."""
    top_safe = 48
    hud_h = 56
    slam_h = 64
    bottom_safe = 18
    side = 8
    cols, rows = 10, 18
    avail_w = w - side * 2
    avail_h = h - top_safe - hud_h - slam_h - bottom_safe
    cell = min(avail_w / cols, avail_h / rows)
    board_w = cell * cols
    board_h = cell * rows
    bx = (w - board_w) / 2
    by = top_safe + hud_h + 4
    return int(bx), int(by), int(cell), cols, rows, int(board_w), int(board_h)


def draw_play(w: int, h: int, island: bool, slam: bool, combo: int, danger: bool, score: int) -> Image.Image:
    img = phone_frame(w, h, island)
    d = ImageDraw.Draw(img)
    top = 48 if island else 28
    # HUD with bandit beside score
    bandit = load_bandit(44)
    img = img.convert("RGBA")
    img.alpha_composite(bandit, (52, top))
    img = img.convert("RGB")
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([12, top, 48, top + 36], radius=8, fill=(30, 40, 50))
    d.text((18, top + 8), "II", fill=(0, 230, 235), font=font(14, True))
    d.text((104, top + 2), f"{score:,}", fill=(255, 255, 255), font=font(20, True))
    d.text((104, top + 26), "LVL 2  ·  Recycle 8 glass", fill=(255, 80, 180), font=font(11, True))

    bx, by, cell, cols, rows, bw, bh = layout_board(w, h)
    # Board frame
    outline = (255, 60, 70) if danger else (0, 230, 235)
    d.rounded_rectangle([bx - 3, by - 3, bx + bw + 3, by + bh + 3], radius=8, outline=outline, width=3)
    # Fill board
    for y in range(rows):
        for x in range(cols):
            cx = bx + int(x * cell)
            cy = by + int(y * cell)
            filled = y > rows - 7 and (x + y) % 4 != 0
            if filled:
                ch = "mpgP"[(x + y) % 4]
                color = MAT[ch]
                d.rounded_rectangle(
                    [cx + 1, cy + 1, cx + int(cell) - 2, cy + int(cell) - 2],
                    radius=3,
                    fill=color,
                )
            else:
                d.rectangle([cx + 1, cy + 1, cx + int(cell) - 2, cy + int(cell) - 2], fill=(14, 16, 26))
    if combo >= 2:
        d.text((w // 2 - 40, by - 22), f"CHAIN ×{combo}", fill=(0, 255, 200), font=font(14, True))
    # Local glow only — no full-board white flash
    if combo >= 2:
        gx = bx + int(2 * cell)
        gy = by + int((rows - 3) * cell)
        glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse([gx, gy, gx + int(cell * 3), gy + int(cell * 2)], fill=(0, 255, 220, 70))
        img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")
        d = ImageDraw.Draw(img)
    # SLAM only when charged
    if slam:
        d.rounded_rectangle([16, h - 70, w - 16, h - 22], radius=14, fill=(255, 90, 140))
        d.text((w // 2 - 30, h - 56), "SLAM", fill=(10, 10, 16), font=font(20, True))
    else:
        # slim meter
        d.rounded_rectangle([24, h - 42, w - 24, h - 28], radius=4, fill=(30, 40, 50))
        d.rounded_rectangle([24, h - 42, 24 + int((w - 48) * 0.7), h - 28], radius=4, fill=(0, 200, 190))
    return img


def draw_game_over(w: int, h: int, island: bool) -> Image.Image:
    img = draw_play(w, h, island, slam=False, combo=0, danger=True, score=4820)
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 180))
    img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")
    d = ImageDraw.Draw(img)
    panel = [36, h // 2 - 120, w - 36, h // 2 + 120]
    d.rounded_rectangle(panel, radius=16, fill=(18, 22, 36), outline=(0, 230, 235), width=2)
    d.text((w // 2 - 50, h // 2 - 90), "BIN FULL", fill=(255, 80, 180), font=font(22, True))
    d.text((w // 2 - 40, h // 2 - 40), "4,820", fill=(255, 255, 255), font=font(32, True))
    d.rounded_rectangle([60, h // 2 + 20, w - 60, h // 2 + 60], radius=12, fill=(0, 200, 190))
    d.text((w // 2 - 50, h // 2 + 32), "Play again", fill=(8, 12, 20), font=font(14, True))
    return img


def main():
    # iPhone 16 Pro-ish logical points & SE
    pro = (393, 852)
    se = (375, 667)
    frames = []
    draw_title(*pro, True).save(OUT / "pro-title.png")
    draw_play(*pro, True, slam=True, combo=3, danger=False, score=1260).save(OUT / "pro-play.png")
    draw_game_over(*pro, True).save(OUT / "pro-game-over.png")
    draw_title(*se, False).save(OUT / "se-title.png")
    draw_play(*se, False, slam=False, combo=2, danger=True, score=980).save(OUT / "se-play.png")
    draw_game_over(*se, False).save(OUT / "se-game-over.png")

    # ~60s GIF at 6fps = 360 frames is huge; ship ~12s preview @ 8fps for eyes
    for i in range(96):
        t = i / 96.0
        combo = 1 + int(t * 3) if 0.25 < t < 0.55 else (2 if t > 0.55 else 1)
        slam = 0.55 < t < 0.72
        danger = t > 0.82
        score = 200 + int(t * 2400)
        fr = draw_play(*pro, True, slam=slam, combo=combo, danger=danger, score=score)
        frames.append(fr)
    frames[0].save(
        OUT / "calm-fit-play-preview.gif",
        save_all=True,
        append_images=frames[1:],
        duration=125,
        loop=0,
        optimize=True,
    )
    # Also write a note that CI smoke produces the real mp4
    (OUT / "README.txt").write_text(
        "Layout previews for Calm+Fit (Pro 393x852, SE 375x667).\n"
        "Real ~60s gameplay-demo.mp4 + device screenshots come from CI simulator_smoke.\n"
    )
    print(f"Wrote calm-fit previews to {OUT}")


if __name__ == "__main__":
    main()

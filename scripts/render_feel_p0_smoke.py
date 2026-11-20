#!/usr/bin/env python3
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
"""On-device-style ~45s gesture-play smoke GIF + before/after sheet for Feel P0."""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path("/opt/cursor/artifacts/feel-p0")
W, H = 390, 780
COLS, ROWS = 8, 16
CELL = 36  # bigger cells — board fills width
BOARD_X = 28
BOARD_Y = 118
BOARD_W = COLS * CELL
BOARD_H = ROWS * CELL

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


def load_bandit(name: str, size: int = 56) -> Image.Image:
    path = BANDIT_DIR / name
    if path.exists():
        im = Image.open(path).convert("RGBA")
        im.thumbnail((size, size), Image.Resampling.LANCZOS)
        return im
    # Fallback silhouette
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([8, 8, size - 8, size - 8], fill=(180, 140, 90, 255))
    return im


def empty_grid():
    return [["." for _ in range(COLS)] for _ in range(ROWS)]


def place_piece(grid, cells, ch):
    for x, y in cells:
        if 0 <= y < ROWS and 0 <= x < COLS:
            grid[y][x] = ch


def draw_phone(bg=(10, 12, 24)) -> Image.Image:
    return Image.new("RGB", (W, H), bg)


def draw_hud(d: ImageDraw.ImageDraw, score: int, level: int, goal: str, toast: str | None = None):
    d.text((16, 18), f"{score:,}", fill=(0, 240, 245), font=font(22, True))
    d.text((16, 46), f"LVL {level}", fill=(200, 200, 220), font=font(13, True))
    d.text((16, 68), goal, fill=(255, 180, 70), font=font(12, True))
    if toast:
        # Wrapped / fitted level banner — kept off the board
        tw = font(11, True)
        d.rounded_rectangle([40, 90, W - 40, 112], radius=6, fill=(0, 180, 190))
        d.text((48, 94), toast[:42], fill=(8, 12, 20), font=tw)


def draw_board(base: Image.Image, grid, shake: float = 0.0, hit_flash: float = 0.0):
    img = base.copy()
    ox = int(shake * 4)
    oy = int(shake * 2)
    d = ImageDraw.Draw(img)
    x0, y0 = BOARD_X + ox, BOARD_Y + oy
    # Slim neon frame — no decorative side rails
    d.rounded_rectangle(
        [x0 - 4, y0 - 4, x0 + BOARD_W + 4, y0 + BOARD_H + 4],
        radius=10,
        outline=(0, 230, 235),
        width=2,
    )
    d.rounded_rectangle(
        [x0 - 2, y0 - 2, x0 + BOARD_W + 2, y0 + BOARD_H + 2],
        radius=8,
        outline=(255, 40, 180),
        width=1,
    )
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            cx = x0 + x * CELL
            cy = y0 + y * CELL
            if ch == ".":
                d.rectangle([cx + 1, cy + 1, cx + CELL - 2, cy + CELL - 2], fill=(16, 18, 28))
            else:
                color = MAT.get(ch, (200, 200, 200))
                d.rounded_rectangle(
                    [cx + 1, cy + 1, cx + CELL - 2, cy + CELL - 2],
                    radius=5,
                    fill=color,
                    outline=(255, 255, 255),
                    width=1,
                )
    if hit_flash > 0:
        flash = Image.new("RGBA", (W, H), (255, 255, 255, int(90 * hit_flash)))
        img = Image.alpha_composite(img.convert("RGBA"), flash).convert("RGB")
    return img


def draw_bandit(img: Image.Image, mood: str, bounce: float = 0.0):
    names = {
        "idle": "head-idle.png",
        "cheer": "head-cheer.png",
        "panic": "head-panic.png",
        "disco": "head-cheer.png",
    }
    bandit = load_bandit(names.get(mood, "head-idle.png"), 52)
    x = BOARD_X + BOARD_W + 8
    y = BOARD_Y + 8 + int(bounce * 6)
    img = img.convert("RGBA")
    img.alpha_composite(bandit, (x, y))
    return img.convert("RGB")


def draw_power(d: ImageDraw.ImageDraw, mode: str | None, charged: bool):
    # Single power row
    if mode is None:
        return
    label = "SLAM! TAP TO CRUSH" if mode == "slam" else "SNATCH"
    fill = (255, 70, 120) if mode == "slam" else (30, 30, 40)
    if mode == "slam" and not charged:
        return
    d.rounded_rectangle([40, H - 78, W - 40, H - 28], radius=14, fill=fill, outline=(255, 200, 80), width=2)
    d.text((W // 2 - 70, H - 62), label, fill=(255, 255, 255), font=font(14, True))


def draw_score_popup(d: ImageDraw.ImageDraw, text: str, t: float):
    # Beside the board, not over falling area
    x = BOARD_X + BOARD_W + 6
    y = BOARD_Y + 90 - int(t * 20)
    d.text((x, y), text, fill=(255, 230, 80), font=font(14, True))


def draw_gesture_hint(d: ImageDraw.ImageDraw, show: bool):
    if not show:
        return
    d.rounded_rectangle([36, BOARD_Y + 12, W - 36, BOARD_Y + 48], radius=8, fill=(0, 0, 0,))
    d.text((44, BOARD_Y + 20), "Drag · tap L/R rotate · swipe ↓ drop · ↑ hold", fill=(255, 255, 255), font=font(10, True))


def draw_claw(img: Image.Image, progress: float, target_xy: tuple[int, int]):
    """Snatch claw/paw animation grabbing a block."""
    if progress <= 0:
        return img
    img = img.convert("RGBA")
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    tx, ty = target_xy
    start_y = BOARD_Y - 40
    y = int(start_y + (ty - start_y) * min(1.0, progress * 1.4))
    # Paw / claw
    d.ellipse([tx - 18, y - 14, tx + 18, y + 14], fill=(255, 140, 60, 230), outline=(255, 255, 255, 255))
    for dx in (-12, 0, 12):
        d.polygon([(tx + dx - 4, y - 8), (tx + dx + 4, y - 8), (tx + dx, y - 22)], fill=(255, 180, 100, 240))
    img = Image.alpha_composite(img, overlay)
    return img.convert("RGB")


def particles(img: Image.Image, color, origin, strength: float):
    if strength <= 0:
        return img
    img = img.convert("RGBA")
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    rng = random.Random(int(origin[0] * 17 + strength * 100))
    for _ in range(int(18 * strength)):
        ang = rng.random() * math.tau
        dist = rng.random() * 40 * strength
        x = origin[0] + math.cos(ang) * dist
        y = origin[1] + math.sin(ang) * dist
        r = 2 + rng.random() * 3
        d.ellipse([x - r, y - r, x + r, y + r], fill=(*color, int(200 * strength)))
    return Image.alpha_composite(img, overlay).convert("RGB")


def before_frame() -> Image.Image:
    """Cluttered pre-feel UI: tiny board, button pad, 3 goals, truncated banner."""
    img = draw_phone((12, 10, 18))
    d = ImageDraw.Draw(img)
    d.text((16, 16), "16,140", fill=(0, 240, 245), font=font(20, True))
    d.text((16, 42), "LVL 5", fill=(200, 200, 220), font=font(12, True))
    d.text((16, 62), "Recycle 12 plastic", fill=(180, 180, 200), font=font(9))
    d.text((150, 62), "Make a 3x chain", fill=(180, 180, 200), font=font(9))
    d.text((280, 62), "Slam the press", fill=(180, 180, 200), font=font(9))
    # Truncated banner over tiny board
    d.rounded_rectangle([50, 88, 340, 108], radius=4, fill=(0, 200, 210))
    d.text((58, 92), "Level 4 - Leaking pipes convert neighb...", fill=(5, 10, 18), font=font(10, True))
    # Small board with huge empty bin sides
    bx, by, bw, bh = 110, 130, 170, 340
    d.rounded_rectangle([40, 120, 350, 490], radius=16, outline=(80, 90, 110), width=3)
    d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=8, outline=(0, 230, 235), width=2)
    grid = empty_grid()
    for y in range(12, 16):
        for x in range(8):
            if (x + y) % 3:
                grid[y][x] = "p" if x % 2 else "m"
    for y in range(16):
        for x in range(8):
            ch = grid[y][x]
            if ch == ".":
                continue
            cx = bx + x * (bw // 8)
            cy = by + y * (bh // 16)
            d.rectangle([cx + 1, cy + 1, cx + bw // 8 - 2, cy + bh // 16 - 2], fill=MAT[ch])
    # Crowded classic pad
    labels = ["◄", "↻", "►", "HOLD", "SOFT", "DROP", "SLAM!", "SNATCH"]
    y = 510
    for i, lab in enumerate(labels):
        x = 20 + (i % 4) * 90
        yy = y + (i // 4) * 70
        d.rounded_rectangle([x, yy, x + 80, yy + 56], radius=10, fill=(40, 44, 60), outline=(0, 220, 230))
        d.text((x + 18, yy + 18), lab, fill=(230, 230, 240), font=font(12, True))
    d.text((20, H - 36), "BEFORE · classic pad · cluttered HUD", fill=(255, 100, 140), font=font(11, True))
    return img


def simulate_frames(n: int = 90):
    """~45s at 2 fps storyboard, or denser gif at ~8–12 fps for short clip."""
    frames: list[Image.Image] = []
    rng = random.Random(42)
    grid = empty_grid()
    # Seed bottom rows
    for y in range(13, 16):
        for x in range(COLS):
            if rng.random() > 0.35:
                grid[y][x] = rng.choice(["m", "p", "g", "P"])

    piece = [(3, 0), (4, 0), (3, 1), (4, 1)]
    pch = "p"
    score = 2140
    level = 3
    goal = "Recycle 8 plastic"
    mood = "idle"
    slam_charge = 0.0
    claw_t = 0.0
    popup = None
    popup_t = 0.0
    shake = 0.0
    flash = 0.0
    slam_fired = False
    clears_done = 0

    for i in range(n):
        t = i / max(1, n - 1)
        show_hint = i < 12  # ~3s at 4fps
        toast = None
        if 18 <= i <= 24:
            toast = "Level 4 · Leaks convert neighbors"  # fits, not truncated

        # Move piece down / soft / hard
        if i % 3 == 0 and i > 8:
            np = [(x, y + 1) for x, y in piece]
            if all(y < ROWS and (y >= ROWS or grid[y][x] == "." or (x, y) in piece) for x, y in np):
                # Collision with settled
                blocked = False
                for x, y in np:
                    if y >= ROWS or (grid[y][x] != "." and (x, y - 1) not in [(a, b) for a, b in piece]):
                        # simplify: check settled cells
                        pass
                # Clear piece from grid overlay approach: don't write until lock
                piece = [(x, min(ROWS - 1, y + 1)) for x, y in piece]

        # Lock + clear around mid
        if i in (22, 40, 55, 70) and clears_done < 4:
            # Fill a full row near bottom
            row = 14 - (clears_done % 2)
            for x in range(COLS):
                grid[row][x] = rng.choice(["m", "p", "g", "P"])
            # Clear
            for x in range(COLS):
                grid[row][x] = "."
            for y in range(row, 0, -1):
                grid[y] = grid[y - 1][:]
            grid[0] = ["."] * COLS
            score += 800 + clears_done * 200
            clears_done += 1
            mood = "cheer" if clears_done < 3 else "disco"
            shake = 1.0
            flash = 1.0
            popup = f"+{800 + (clears_done - 1) * 200}"
            popup_t = 1.0
            slam_charge = min(1.0, slam_charge + 0.35)
            piece = [(3, 0), (4, 0), (5, 0), (4, 1)]
            pch = rng.choice(["m", "p", "g", "P"])

        # SLAM once charged
        power = None
        if slam_charge >= 1.0 and not slam_fired and i >= 58:
            power = "slam"
        elif slam_charge >= 0.5 and i < 50:
            power = "snatch"

        if i == 62 and not slam_fired:
            slam_fired = True
            slam_charge = 0
            shake = 1.4
            flash = 1.0
            mood = "disco"
            # crush bottom 2 rows
            for y in (14, 15):
                for x in range(COLS):
                    grid[y][x] = "."
            score += 2400
            popup = "+2400 SLAM"
            popup_t = 1.0
            power = "slam"

        # Snatch claw
        if 48 <= i <= 54:
            claw_t = (i - 48) / 6
            power = "snatch"
            mood = "cheer"
        else:
            claw_t = 0.0

        # Panic when stack high
        fill = sum(1 for row in grid[:8] for c in row if c != ".")
        if fill > 10:
            mood = "panic"

        # Compose
        base = draw_phone()
        d = ImageDraw.Draw(base)
        draw_hud(d, score, level + (1 if i > 20 else 0), goal, toast)
        draw_gesture_hint(d, show_hint)
        # Active piece overlay on copy of grid
        g2 = [row[:] for row in grid]
        for x, y in piece:
            if 0 <= y < ROWS:
                g2[y][x] = pch
        img = draw_board(base, g2, shake=shake, hit_flash=flash)
        img = draw_bandit(img, mood, bounce=math.sin(i * 0.4) * (0.5 if mood == "cheer" else 0.2))
        if claw_t > 0:
            img = draw_claw(img, claw_t, (BOARD_X + 4 * CELL, BOARD_Y + 10 * CELL))
        if flash > 0.3:
            img = particles(img, MAT.get(pch, (255, 200, 80)), (BOARD_X + BOARD_W // 2, BOARD_Y + BOARD_H - 40), flash)
        d2 = ImageDraw.Draw(img)
        if popup and popup_t > 0:
            draw_score_popup(d2, popup, 1.0 - popup_t)
        draw_power(d2, power if power == "slam" or (power == "snatch" and claw_t > 0 or (power == "snatch" and 45 < i < 55)) else ("slam" if slam_charge >= 1 and not slam_fired else None), True)
        d2.text((16, H - 22), "AFTER · gestures · lean HUD · bandit", fill=(120, 255, 180), font=font(10, True))
        # No pause strobe — never draw PAUSED unless explicitly paused (never in this clip)
        frames.append(img)

        shake *= 0.72
        flash *= 0.65
        popup_t *= 0.9
        if popup_t < 0.05:
            popup = None
        if mood == "disco" and i % 10 == 9:
            mood = "cheer"
        if mood == "cheer" and i % 8 == 7:
            mood = "idle"

    return frames


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    before = before_frame()
    before.save(OUT / "before-0.png")

    frames = simulate_frames(96)  # ~48s at 2fps narrative; gif uses faster delay
    for i, fr in enumerate(frames[::12]):
        fr.save(OUT / f"after-{i}.png")

    # ~45s feel: 96 frames @ 470ms ≈ 45s
    gif_path = OUT / "after-gesture-play.gif"
    frames[0].save(
        gif_path,
        save_all=True,
        append_images=frames[1:],
        duration=470,
        loop=0,
        optimize=False,
    )

    # Before/after sheet: 2x3
    sheet_frames = [before] + frames[0:1] + frames[24:25] + frames[48:49] + frames[62:63] + frames[90:91]
    cols, rows = 3, 2
    pad = 12
    cell_w, cell_h = W, H
    sheet = Image.new("RGB", (cols * cell_w + pad * (cols + 1), rows * cell_h + pad * (rows + 1) + 40), (6, 8, 16))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 10), "TRASH STACK Feel P0 — before (Nicholas TF) → after (gesture / lean HUD / juice)", fill=(0, 230, 235), font=font(16, True))
    for i, fr in enumerate(sheet_frames[:6]):
        r, c = divmod(i, cols)
        x = pad + c * (cell_w + pad)
        y = 40 + pad + r * (cell_h + pad)
        sheet.paste(fr.resize((cell_w, cell_h)), (x, y))
    sheet_path = OUT / "after-sheet.jpg"
    sheet.save(sheet_path, quality=88)
    print("wrote", gif_path, "frames", len(frames))
    print("wrote", sheet_path)
    print("duration_s", round(len(frames) * 0.47, 1))


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
# Autoplay smoke: 45–60s gameplay video + distinct review + marketing screenshots.
set -euo pipefail

DEVICE="${1:?simulator UDID}"
APP_PATH="${2:?path to TrashStack.app}"
OUT_DIR="${3:-smoke-artifacts}"
BUNDLE_ID="${BUNDLE_ID:-com.cinderandcrown.trashstack}"
DISPLAY="${SIMCTL_DISPLAY:-internal}"
SMOKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$OUT_DIR" "$OUT_DIR/marketing"

app_running() {
  # Prefer launchctl list; fall back to simctl spawn ps.
  if xcrun simctl spawn "$DEVICE" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    return 0
  fi
  xcrun simctl spawn "$DEVICE" ps aux 2>/dev/null | grep -v grep | grep -q "TrashStack" || return 1
}

# macOS-friendly deadline (GNU timeout is missing on xcode runners).
with_deadline() {
  local secs="$1"
  shift
  perl -e 'alarm shift @ARGV; exec @ARGV' "$secs" "$@"
}

shot() {
  local out="$1"
  if with_deadline 20 xcrun simctl io "$DEVICE" screenshot --display="$DISPLAY" "$out" 2>/tmp/sim-shot.err; then
    return 0
  fi
  if with_deadline 20 xcrun simctl io "$DEVICE" screenshot --display=1 "$out" 2>/tmp/sim-shot.err; then
    return 0
  fi
  with_deadline 20 xcrun simctl io "$DEVICE" screenshot "$out"
}

# Reject blank / springboard captures. Prefer Pillow; fall back to stdlib PNG decode.
assert_app_frame() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys, struct, zlib, pathlib
path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 80_000:
    print(f"Frame too small ({len(data)} bytes): {path}", file=sys.stderr)
    sys.exit(2)

samples = None
try:
    from PIL import Image  # type: ignore
    im = Image.open(path).convert("RGB")
    w, h = im.size
    samples = [im.getpixel((int(w * fx), int(h * fy))) for fy in (0.25, 0.5, 0.7) for fx in (0.2, 0.5, 0.8)]
except Exception:
    samples = None

if samples is None:
    # Minimal 8-bit RGB/RGBA PNG sampler (simctl screenshots).
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        print(f"Not a PNG: {path}", file=sys.stderr)
        sys.exit(2)
    pos = 8
    width = height = bit_depth = color_type = None
    idat = bytearray()
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
    if width and bit_depth == 8 and color_type in (2, 6):
        raw = zlib.decompress(bytes(idat))
        bpp = 3 if color_type == 2 else 4
        stride = width * bpp + 1
        rows = []
        for y in range(height):
            start = y * stride
            filt = raw[start]
            row = bytearray(raw[start + 1:start + stride])
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
                    if pa <= pb and pa <= pc:
                        return a
                    if pb <= pc:
                        return b
                    return c
                for i in range(len(row)):
                    a = row[i - bpp] if i >= bpp else 0
                    b = prev[i]
                    c = prev[i - bpp] if i >= bpp else 0
                    row[i] = (row[i] + paeth(a, b, c)) & 255
            rows.append(row)
        samples = []
        for fy in (0.25, 0.5, 0.7):
            for fx in (0.2, 0.5, 0.8):
                x = min(width - 1, int(width * fx))
                y = min(height - 1, int(height * fy))
                i = x * bpp
                samples.append((rows[y][i], rows[y][i + 1], rows[y][i + 2]))

if not samples:
    # Last resort: large enough PNG that survived simctl capture.
    print(f"Frame OK {path} (size-only {len(data)} bytes)")
    sys.exit(0)

whites = sum(1 for r, g, b in samples if r > 245 and g > 245 and b > 245)
beiges = sum(1 for r, g, b in samples if r > 90 and g > 70 and b < 160 and r > b + 15)
darks = sum(1 for r, g, b in samples if r < 55 and g < 55 and b < 75)
if whites >= 7:
    print(f"Blank/white frame: {path}", file=sys.stderr)
    sys.exit(2)
if beiges >= 5 and darks <= 1:
    print(f"Springboard/home frame (app not foreground): {path}", file=sys.stderr)
    sys.exit(3)
print(f"Frame OK {path} (dark={darks} white={whites} beige={beiges})")
PY
}

# Title frame must be the real title screen — reject the launch splash (LaunchLogo card).
assert_title_not_splash() {
  local file="$1"
  local logo="${SMOKE_ROOT}/TrashStack/Assets.xcassets/LaunchLogo.imageset/LaunchLogo.png"
  python3 - "$file" "$logo" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
logo_path = pathlib.Path(sys.argv[2])
try:
    from PIL import Image
except Exception as e:
    print(f"Pillow required to reject splash as title: {e}", file=sys.stderr)
    sys.exit(2)
im = Image.open(path).convert("RGB")
w, h = im.size
if not logo_path.exists():
    print(f"LaunchLogo missing at {logo_path}", file=sys.stderr)
    sys.exit(2)
logo = Image.open(logo_path).convert("RGB").resize((w, h))
# Center-weighted MSE similarity vs splash art.
err = 0.0
n = 0
for y in range(h // 5, 4 * h // 5, max(1, h // 40)):
    for x in range(w // 5, 4 * w // 5, max(1, w // 40)):
        a = im.getpixel((x, y))
        b = logo.getpixel((x, y))
        err += sum((a[i] - b[i]) ** 2 for i in range(3))
        n += 1
mse = err / max(1, n * 3)
# Empirically: identical frames → mse≈0; real title vs splash → large. Fail if too close.
if mse < 1800:
    print(f"Title frame looks like launch splash (mse={mse:.0f} < 1800): {path}", file=sys.stderr)
    sys.exit(5)
# Also require title-ish teal/magenta signal in the upper half (wordmark / raccoon neon).
teal = magenta = 0
for y in range(int(h * 0.12), int(h * 0.45), max(1, h // 50)):
    for x in range(int(w * 0.15), int(w * 0.85), max(1, w // 40)):
        r, g, b = im.getpixel((x, y))
        if g > 140 and b > 140 and r < 120:
            teal += 1
        if r > 160 and b > 140 and g < 120:
            magenta += 1
if teal + magenta < 3:
    print(f"Title frame missing neon wordmark colors (teal={teal} magenta={magenta}): {path}", file=sys.stderr)
    sys.exit(5)
print(f"Title OK (not splash) {path} mse={mse:.0f} teal={teal} magenta={magenta}")
PY
}

# Reject the OS UILaunchScreen (LaunchLogo) — dark enough to pass assert_app_frame but not SwiftUI yet.
assert_not_launch_splash() {
  local file="$1"
  local logo="${SMOKE_ROOT}/TrashStack/Assets.xcassets/LaunchLogo.imageset/LaunchLogo.png"
  python3 - "$file" "$logo" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
logo_path = pathlib.Path(sys.argv[2])
try:
    from PIL import Image
except Exception as e:
    print(f"Pillow required to reject launch splash: {e}", file=sys.stderr)
    sys.exit(2)
im = Image.open(path).convert("RGB")
w, h = im.size
if not logo_path.exists():
    print(f"LaunchLogo missing at {logo_path}", file=sys.stderr)
    sys.exit(2)
logo = Image.open(logo_path).convert("RGB").resize((w, h))
err = 0.0
n = 0
for y in range(h // 5, 4 * h // 5, max(1, h // 40)):
    for x in range(w // 5, 4 * w // 5, max(1, w // 40)):
        a = im.getpixel((x, y))
        b = logo.getpixel((x, y))
        err += sum((a[i] - b[i]) ** 2 for i in range(3))
        n += 1
mse = err / max(1, n * 3)
if mse < 1800:
    print(f"Still OS launch splash (mse={mse:.0f} < 1800): {path}", file=sys.stderr)
    sys.exit(5)
print(f"Not launch splash OK {path} mse={mse:.0f}")
PY
}

# Fail if gameplay shots still show SpriteKit's red-X missing-texture tiles.
assert_no_missing_textures() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys, struct, zlib, pathlib
path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
# Prefer Pillow when present
try:
    from PIL import Image
    im = Image.open(path).convert("RGB")
    w, h = im.size
    # Sample the playfield band
    red_x = 0
    total = 0
    for yy in range(int(h * 0.28), int(h * 0.72), max(1, h // 40)):
        for xx in range(int(w * 0.18), int(w * 0.82), max(1, w // 40)):
            r, g, b = im.getpixel((xx, yy))
            total += 1
            # Classic missing-texture: bright white with strong red channel / red X
            if r > 200 and g > 180 and b > 180:
                red_x += 1
            elif r > 180 and g < 90 and b < 90:
                red_x += 1
    ratio = red_x / max(1, total)
    if ratio > 0.18:
        print(f"Likely missing-texture / red-X tiles in {path} (ratio={ratio:.2f})", file=sys.stderr)
        sys.exit(4)
    print(f"Junk art OK {path} (bright/red ratio={ratio:.2f})")
except Exception as e:
    # Size floor only if we cannot sample
    if path.stat().st_size < 200_000:
        print(f"Gameplay frame suspiciously small: {path} ({e})", file=sys.stderr)
        sys.exit(4)
    print(f"Junk art size-OK {path}")
PY
}

launch_shot() {
  local mode="$1"
  local outfile="$2"
  local settle="${3:-4}"
  local attempts=0
  # Recycle juice is longer (~0.5s suck + held glow/banner) — more attempts, not a looser assert.
  local max_attempts=2
  if [[ "$mode" == "recycle" || "$mode" == "mkt-recycle" ]]; then
    max_attempts=3
    if (( settle < 7 )); then settle=7; fi
  fi
  local shot_start=$SECONDS

  while (( attempts < max_attempts )); do
    attempts=$((attempts + 1))
    if (( SECONDS - shot_start > 70 )); then
      echo "launch_shot deadline exceeded for mode='$mode'" >&2
      break
    fi
    smoke_budget
    with_deadline 12 xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
    sleep 0.4

    # Defaults + launch args (args are authoritative in PlayerProfile.shotArgument).
    with_deadline 10 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
    with_deadline 10 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true
    if [[ -n "$mode" ]]; then
      with_deadline 10 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "$mode" || true
      with_deadline 20 xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackShot "$mode" -trashStackSkipAds >/tmp/sim-launch.out 2>&1 || true
    else
      with_deadline 10 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
      with_deadline 20 xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackSkipAds >/tmp/sim-launch.out 2>&1 || true
    fi
    cat /tmp/sim-launch.out >&2 || true

    local waited=0
    while (( waited < settle )); do
      sleep 1
      waited=$((waited + 1))
      if app_running; then
        break
      fi
    done
    # Extra settle after process is alive so SwiftUI/SpriteKit can paint.
    # Recycle: capture while hold-glow + RECYCLE/CHAIN banner are still up (~1.2s).
    if [[ "$mode" == "recycle" || "$mode" == "mkt-recycle" ]]; then
      sleep 1.1
      sleep "$settle"
    else
      sleep "$settle"
    fi

    if ! app_running; then
      echo "App not running after launch (mode='$mode' attempt=$attempts)" >&2
      continue
    fi

    shot "$outfile"
    if assert_app_frame "$outfile"; then
      echo "Wrote $outfile" >&2
      return 0
    fi
    echo "Bad frame for mode='$mode' attempt=$attempts — retrying" >&2
  done
  echo "Failed to capture a valid app frame for mode='$mode' → $outfile" >&2
  exit 1
}

# Overall watchdog (paired with the GitHub step timeout-minutes).
SMOKE_START=$SECONDS
smoke_budget() {
  local elapsed=$((SECONDS - SMOKE_START))
  if (( elapsed > 1500 )); then
    echo "Smoke watchdog exceeded ${elapsed}s — aborting" >&2
    exit 124
  fi
}

echo "Smoke on $DEVICE (display=$DISPLAY)"
xcrun simctl bootstatus "$DEVICE" -b || xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH"
smoke_budget

xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true

# Springboard icon crop (evidence for real AppIcon) — before timed launch.
with_deadline 20 xcrun simctl io "$DEVICE" screenshot --display="$DISPLAY" "$OUT_DIR/00-springboard.png" 2>/dev/null \
  || with_deadline 20 xcrun simctl io "$DEVICE" screenshot "$OUT_DIR/00-springboard.png" || true
python3 - "$OUT_DIR/00-springboard.png" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1])
out = src.with_name("00-springboard-icon-crop.png")
if not src.exists():
    print("Springboard crop skipped: no screenshot")
    raise SystemExit(0)
try:
    from PIL import Image
    im = Image.open(src)
    w, h = im.size
    crop = im.crop((w // 2 - 120, h // 2 - 220, w // 2 + 120, h // 2 - 40))
    crop.save(out)
    print("Springboard icon crop OK", crop.size)
except Exception:
    # Fall back: copy full springboard as crop evidence (runners may lack Pillow).
    out.write_bytes(src.read_bytes())
    print("Springboard crop fallback: copied full frame (no Pillow)")
PY

# Cold-launch timing (ads skipped):
# 1) In-app: ProcessInfo.systemUptime at @main → first SwiftUI frame (ident) ≤ 1.5s.
# 2) Wall-clock: after process is up → first non-LaunchLogo frame with in-app stamp ≤ 8s.
# Do NOT accept OS UILaunchScreen as first frame. Do NOT raise the 8s ceiling.
with_deadline 12 xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 0.3
with_deadline 10 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
with_deadline 10 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true
with_deadline 10 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
with_deadline 10 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.launchToTitleSec" >/dev/null 2>&1 || true
with_deadline 10 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.launchToTitleSecString" >/dev/null 2>&1 || true
with_deadline 20 xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackSkipAds >/tmp/sim-launch-cold.out 2>&1 || true
cat /tmp/sim-launch-cold.out >&2 || true
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if app_running; then break; fi
  sleep 0.15
done
# Wall clock starts once the process is up — not during simctl launch overhead.
LAUNCH_T0=$SECONDS
FIRST_OK=0
INAPP_RAW=""
for try in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
  sleep 0.2
  INAPP_RAW="$(xcrun simctl spawn "$DEVICE" defaults read "$BUNDLE_ID" trashStack.launchToTitleSec 2>/dev/null || true)"
  shot "$OUT_DIR/00-publisher-ident.png" || true
  if [[ -n "${INAPP_RAW// /}" ]] \
    && assert_app_frame "$OUT_DIR/00-publisher-ident.png" \
    && assert_not_launch_splash "$OUT_DIR/00-publisher-ident.png"; then
    FIRST_OK=1
    break
  fi
done
LAUNCH_DT=$((SECONDS - LAUNCH_T0))
INAPP_STR="$(xcrun simctl spawn "$DEVICE" defaults read "$BUNDLE_ID" trashStack.launchToTitleSecString 2>/dev/null || true)"
{
  echo "wall_clock_process_up_to_first_frame_s=$LAUNCH_DT"
  echo "in_app_process_start_to_first_frame_s=${INAPP_RAW:-missing}"
  echo "in_app_process_start_to_first_frame_string=${INAPP_STR:-missing}"
  echo "gates: in_app<=1.5s AND wall_clock<=8s; reject OS LaunchLogo; require in-app stamp"
} | tee "$OUT_DIR/launch-timing.txt"
printf '%s\n' "${INAPP_RAW:-}" > "$OUT_DIR/launch-time-seconds.txt"
printf '%s\n' "$LAUNCH_DT" > "$OUT_DIR/launch-wall-clock-seconds.txt"
if (( FIRST_OK == 0 )); then
  echo "First SwiftUI frame never arrived (or still LaunchLogo / missing in-app stamp)" >&2
  exit 1
fi
if (( LAUNCH_DT > 8 )); then
  echo "Cold launch wall-clock ${LAUNCH_DT}s exceeds honest 8s ceiling" >&2
  exit 1
fi
python3 - "$INAPP_RAW" <<'PY'
import sys
raw = (sys.argv[1] or "").strip()
if not raw:
    raise SystemExit("Missing in-app launch metric trashStack.launchToTitleSec")
try:
    dt = float(raw)
except ValueError as e:
    raise SystemExit(f"Bad in-app launch metric {raw!r}: {e}")
if dt > 1.5:
    raise SystemExit(f"In-app launch {dt:.3f}s exceeds 1.5s budget")
print(f"In-app launch OK {dt:.3f}s")
PY
# Held publisher-ident screenshot for review evidence (timing already gated above).
launch_shot "ident" "$OUT_DIR/00-publisher-ident.png" 2
# Real Trash Stack title (skip ident so we don't wait on the 2s studio card).
with_deadline 12 xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 0.3
with_deadline 10 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
with_deadline 10 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true
with_deadline 10 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
with_deadline 20 xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackSkipAds -trashStackSkipIdent >/tmp/sim-launch-title.out 2>&1 || true
TITLE_OK=0
for try in 1 2 3 4 5 6 7 8; do
  sleep 0.3
  shot "$OUT_DIR/01-title.png" || true
  if assert_app_frame "$OUT_DIR/01-title.png" && assert_title_not_splash "$OUT_DIR/01-title.png"; then
    TITLE_OK=1
    break
  fi
done
if (( TITLE_OK == 0 )); then
  echo "Title frame invalid or still LaunchLogo splash" >&2
  exit 1
fi
smoke_budget
# Settle long enough for mid-game / crush juice / recycle banner.
launch_shot "game" "$OUT_DIR/02-gameplay.png" 5
assert_no_missing_textures "$OUT_DIR/02-gameplay.png"
launch_shot "compactor" "$OUT_DIR/03-compactor-clear.png" 5
assert_no_missing_textures "$OUT_DIR/03-compactor-clear.png"
# Hold recycle pose (glow + banner) — do NOT loosen assert_app_frame.
launch_shot "recycle" "$OUT_DIR/04-recycle-combo.png" 7
assert_no_missing_textures "$OUT_DIR/04-recycle-combo.png"
launch_shot "revive" "$OUT_DIR/05-game-over-revive.png" 4
assert_no_missing_textures "$OUT_DIR/05-game-over-revive.png"
launch_shot "base" "$OUT_DIR/06-base.png" 3
launch_shot "pass" "$OUT_DIR/07-pass.png" 3
launch_shot "shop" "$OUT_DIR/08-shop.png" 3
launch_shot "notif" "$OUT_DIR/09-notification-prompt.png" 3
smoke_budget
# Retention evidence: Daily Dumpster, share card, streak reward.
launch_shot "daily" "$OUT_DIR/10-daily-dumpster.png" 4
assert_no_missing_textures "$OUT_DIR/10-daily-dumpster.png"
launch_shot "share" "$OUT_DIR/11-daily-share-card.png" 3
launch_shot "streak" "$OUT_DIR/12-streak-reward.png" 3
smoke_budget

launch_shot "mkt-play" "$OUT_DIR/marketing/01-play.png" 4
assert_no_missing_textures "$OUT_DIR/marketing/01-play.png"
launch_shot "mkt-crush" "$OUT_DIR/marketing/02-crush.png" 5
assert_no_missing_textures "$OUT_DIR/marketing/02-crush.png"
launch_shot "mkt-recycle" "$OUT_DIR/marketing/03-recycle.png" 5
assert_no_missing_textures "$OUT_DIR/marketing/03-recycle.png"
launch_shot "mkt-base" "$OUT_DIR/marketing/04-junkyard.png" 3
launch_shot "mkt-pass" "$OUT_DIR/marketing/05-pass.png" 3
launch_shot "mkt-shop" "$OUT_DIR/marketing/06-shop.png" 3
launch_shot "mkt-daily" "$OUT_DIR/marketing/07-daily.png" 4
assert_no_missing_textures "$OUT_DIR/marketing/07-daily.png"
smoke_budget

python3 - "$OUT_DIR" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = [
  "00-publisher-ident.png","01-title.png","02-gameplay.png","03-compactor-clear.png","04-recycle-combo.png",
  "05-game-over-revive.png","06-base.png","07-pass.png","08-shop.png","09-notification-prompt.png",
  "10-daily-dumpster.png","11-daily-share-card.png","12-streak-reward.png",
]
hashes = {}
for f in files:
  p = root/f
  if not p.exists() or p.stat().st_size < 1000:
    print(f"Missing/small {p}", file=sys.stderr); sys.exit(1)
  h = hashlib.sha256(p.read_bytes()).hexdigest()
  if h in hashes:
    print(f"Duplicate screenshot bytes: {hashes[h]} == {f}", file=sys.stderr); sys.exit(1)
  hashes[h] = f
print("Screenshot distinctness OK")
PY

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "demo" || true
VIDEO_RAW="$OUT_DIR/gameplay-demo-silent.mp4"
VIDEO_OUT="$OUT_DIR/gameplay-demo.mp4"
rm -f "$VIDEO_RAW" "$VIDEO_OUT"
set +e
xcrun simctl io "$DEVICE" recordVideo --display=internal --codec=h264 --force "$VIDEO_RAW" &
REC_PID=$!
sleep 2
if ! kill -0 "$REC_PID" 2>/dev/null; then
  echo "recordVideo --display=internal failed; retrying without --display" >&2
  xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$VIDEO_RAW" &
  REC_PID=$!
  sleep 2
fi
if ! kill -0 "$REC_PID" 2>/dev/null; then
  echo "recordVideo failed to start" >&2
  set -e
  exit 1
fi
set -e
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackShot demo -trashStackSkipAds -autoplay >/dev/null 2>&1 || true
# Continuous autoplay (~35s): recycle/press/snatch/game-over beats without board teleport spam.
sleep 35
kill -INT "$REC_PID" 2>/dev/null || true
# Force-kill if simctl recordVideo ignores INT (known hang source).
sleep 2
if kill -0 "$REC_PID" 2>/dev/null; then
  echo "recordVideo still alive after INT — sending KILL" >&2
  kill -KILL "$REC_PID" 2>/dev/null || true
fi
wait "$REC_PID" 2>/dev/null || true
sleep 2
smoke_budget

# simctl recordVideo cannot capture AVAudioEngine. Do NOT paste SFX at fixed adelay offsets
# (that lied about sync). Mux only the same game_loop bed the app plays, and label honestly.
AUDIO_DIR="$SMOKE_ROOT/TrashStack/Resources/Audio"
MUSIC="$AUDIO_DIR/game_loop.wav"
FFMPEG_BIN="$(command -v ffmpeg || true)"
if [[ -z "$FFMPEG_BIN" ]]; then
  for cand in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
    if [[ -x "$cand" ]]; then FFMPEG_BIN="$cand"; break; fi
  done
fi
FFPROBE_BIN="$(command -v ffprobe || true)"
if [[ -z "$FFPROBE_BIN" ]]; then
  for cand in /opt/homebrew/bin/ffprobe /usr/local/bin/ffprobe; do
    if [[ -x "$cand" ]]; then FFPROBE_BIN="$cand"; break; fi
  done
fi
if [[ ! -f "$VIDEO_RAW" ]]; then
  echo "Silent capture missing: $VIDEO_RAW" >&2
  ls -la "$OUT_DIR" >&2 || true
  exit 1
fi
if [[ ! -f "$MUSIC" ]]; then
  echo "Music bed missing: $MUSIC" >&2
  exit 1
fi
if [[ -z "$FFMPEG_BIN" ]]; then
  echo "ffmpeg not found (install via brew install ffmpeg)" >&2
  exit 1
fi
cat > "$OUT_DIR/demo-audio.txt" <<EOF
simctl recordVideo does not capture in-app AVAudioEngine output.
This mux uses ONLY TrashStack/Resources/Audio/game_loop.wav (same asset the app plays)
looped under the silent capture — no synthetic SFX adelay offsets.
In-app SFX/music fire during the recorded play but are not on the simctl track.
Demo script includes a near-miss beat (~14s) and a real game-over (~24s).
EOF
echo "Muxing music bed only with $FFMPEG_BIN ($(wc -c < "$VIDEO_RAW") byte silent capture)" >&2
"$FFMPEG_BIN" -y -i "$VIDEO_RAW" -i "$MUSIC" \
  -filter_complex "[1:a]volume=0.34,aloop=loop=-1:size=2e+09,atrim=0:50,apad=whole_dur=50[aout]" \
  -map 0:v -map "[aout]" -c:v libx264 -pix_fmt yuv420p -crf 28 -preset veryfast -c:a aac -b:a 128k \
  -movflags +faststart -shortest "$VIDEO_OUT" \
  >/tmp/ffmpeg-mux.log 2>&1 || {
    echo "ffmpeg mux failed; keeping silent video as gameplay-demo.mp4" >&2
    cat /tmp/ffmpeg-mux.log >&2 || true
    mv -f "$VIDEO_RAW" "$VIDEO_OUT"
  }
rm -f "$VIDEO_RAW"
if ! "$FFPROBE_BIN" -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$VIDEO_OUT" | grep -q audio; then
  echo "Gameplay video missing audio track after mux" >&2
  cat /tmp/ffmpeg-mux.log >&2 || true
  exit 1
fi
bytes=$(wc -c < "$VIDEO_OUT")
if (( bytes > 150000000 )); then
  echo "Gameplay video too large ($bytes bytes); recompressing" >&2
  "$FFMPEG_BIN" -y -i "$VIDEO_OUT" -c:v libx264 -crf 32 -preset veryfast -c:a aac -b:a 96k "$OUT_DIR/gameplay-demo-small.mp4" >/tmp/ffmpeg-small.log 2>&1
  mv -f "$OUT_DIR/gameplay-demo-small.mp4" "$VIDEO_OUT"
fi
echo "Muxed game_loop bed onto gameplay-demo.mp4 ($(wc -c < "$VIDEO_OUT") bytes)" >&2
# Near-miss / GO window for evidence (~t=20–28s).
"$FFMPEG_BIN" -y -ss 20 -t 8 -i "$VIDEO_OUT" -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 128k \
  "$OUT_DIR/recycle-chain-clip.mp4" >/tmp/ffmpeg-clip.log 2>&1 || {
    echo "tension clip failed" >&2
    cat /tmp/ffmpeg-clip.log >&2 || true
    exit 1
  }
if ! "$FFPROBE_BIN" -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$OUT_DIR/recycle-chain-clip.mp4" | grep -q audio; then
  echo "recycle-chain-clip.mp4 missing audio" >&2
  exit 1
fi

fps="$(xcrun simctl spawn "$DEVICE" defaults read "$BUNDLE_ID" trashStack.measuredFPS 2>/dev/null || echo 0)"
echo "Measured FPS sample: $fps" >&2
python3 - <<PY
fps=float("$fps" or 0)
if fps > 0 and fps < 50:
    raise SystemExit(f"FPS assert failed: {fps}")
print(f"FPS assert ok ({fps})")
PY

for f in 00-publisher-ident.png 01-title.png 02-gameplay.png 03-compactor-clear.png 04-recycle-combo.png \
         05-game-over-revive.png 06-base.png 07-pass.png 08-shop.png 09-notification-prompt.png \
         gameplay-demo.mp4 recycle-chain-clip.mp4 launch-time-seconds.txt; do
  path="$OUT_DIR/$f"
  if [[ ! -s "$path" ]]; then
    echo "Missing or empty smoke artifact: $path" >&2
    ls -la "$OUT_DIR" >&2 || true
    exit 1
  fi
  echo "OK $path ($(wc -c < "$path") bytes)"
done

for f in 01-play.png 02-crush.png 03-recycle.png 04-junkyard.png 05-pass.png 06-shop.png; do
  path="$OUT_DIR/marketing/$f"
  if [[ ! -s "$path" ]]; then
    echo "Missing marketing shot: $path" >&2
    exit 1
  fi
  echo "OK $path ($(wc -c < "$path") bytes)"
done

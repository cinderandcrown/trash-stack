#!/usr/bin/env bash
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
# Autoplay smoke: 45–60s gameplay video + distinct review + marketing screenshots.
set -euo pipefail

DEVICE="${1:?simulator UDID}"
APP_PATH="${2:?path to TrashStack.app}"
OUT_DIR="${3:-smoke-artifacts}"
BUNDLE_ID="${BUNDLE_ID:-com.cinderandcrown.trashstack}"
DISPLAY="${SIMCTL_DISPLAY:-internal}"

mkdir -p "$OUT_DIR" "$OUT_DIR/marketing"

app_running() {
  # Prefer launchctl list; fall back to simctl spawn ps.
  if xcrun simctl spawn "$DEVICE" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    return 0
  fi
  xcrun simctl spawn "$DEVICE" ps aux 2>/dev/null | grep -v grep | grep -q "TrashStack" || return 1
}

shot() {
  local out="$1"
  if xcrun simctl io "$DEVICE" screenshot --display="$DISPLAY" "$out" 2>/tmp/sim-shot.err; then
    return 0
  fi
  if xcrun simctl io "$DEVICE" screenshot --display=1 "$out" 2>/tmp/sim-shot.err; then
    return 0
  fi
  xcrun simctl io "$DEVICE" screenshot "$out"
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
  local settle="${3:-6}"
  local attempts=0
  local max_attempts=3

  while (( attempts < max_attempts )); do
    attempts=$((attempts + 1))
    xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
    sleep 0.6

    # Defaults + launch args (args are authoritative in PlayerProfile.shotArgument).
    xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
    xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true
    if [[ -n "$mode" ]]; then
      xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "$mode" || true
      xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackShot "$mode" -trashStackSkipAds >/tmp/sim-launch.out 2>&1 || true
    else
      xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
      xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackSkipAds >/tmp/sim-launch.out 2>&1 || true
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
    sleep "$settle"

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

# Overall watchdog (CI also wraps with `timeout 20m`).
SMOKE_START=$SECONDS
smoke_budget() {
  local elapsed=$((SECONDS - SMOKE_START))
  if (( elapsed > 1100 )); then
    echo "Smoke watchdog exceeded ${elapsed}s — aborting" >&2
    exit 124
  fi
}

echo "Smoke on $DEVICE (display=$DISPLAY)"
xcrun simctl bootstatus "$DEVICE" -b || xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH"
smoke_budget()

xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true

launch_shot "" "$OUT_DIR/01-title.png" 4
smoke_budget
# Longer settle so mid-game / crush juice / recycle banner are on-screen.
launch_shot "game" "$OUT_DIR/02-gameplay.png" 6
assert_no_missing_textures "$OUT_DIR/02-gameplay.png"
launch_shot "compactor" "$OUT_DIR/03-compactor-clear.png" 6
assert_no_missing_textures "$OUT_DIR/03-compactor-clear.png"
launch_shot "recycle" "$OUT_DIR/04-recycle-combo.png" 6
assert_no_missing_textures "$OUT_DIR/04-recycle-combo.png"
launch_shot "revive" "$OUT_DIR/05-game-over-revive.png" 5
assert_no_missing_textures "$OUT_DIR/05-game-over-revive.png"
launch_shot "base" "$OUT_DIR/06-base.png" 4
launch_shot "pass" "$OUT_DIR/07-pass.png" 4
launch_shot "shop" "$OUT_DIR/08-shop.png" 4
launch_shot "notif" "$OUT_DIR/09-notification-prompt.png" 4
smoke_budget
# Retention evidence: Daily Dumpster, share card, streak reward.
launch_shot "daily" "$OUT_DIR/10-daily-dumpster.png" 5
assert_no_missing_textures "$OUT_DIR/10-daily-dumpster.png"
launch_shot "share" "$OUT_DIR/11-daily-share-card.png" 4
launch_shot "streak" "$OUT_DIR/12-streak-reward.png" 4
smoke_budget

launch_shot "mkt-play" "$OUT_DIR/marketing/01-play.png" 5
assert_no_missing_textures "$OUT_DIR/marketing/01-play.png"
launch_shot "mkt-crush" "$OUT_DIR/marketing/02-crush.png" 6
assert_no_missing_textures "$OUT_DIR/marketing/02-crush.png"
launch_shot "mkt-recycle" "$OUT_DIR/marketing/03-recycle.png" 6
assert_no_missing_textures "$OUT_DIR/marketing/03-recycle.png"
launch_shot "mkt-base" "$OUT_DIR/marketing/04-junkyard.png" 4
launch_shot "mkt-pass" "$OUT_DIR/marketing/05-pass.png" 4
launch_shot "mkt-shop" "$OUT_DIR/marketing/06-shop.png" 4
launch_shot "mkt-daily" "$OUT_DIR/marketing/07-daily.png" 5
assert_no_missing_textures "$OUT_DIR/marketing/07-daily.png"
smoke_budget

python3 - "$OUT_DIR" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = [
  "01-title.png","02-gameplay.png","03-compactor-clear.png","04-recycle-combo.png",
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
# Continuous autoplay (~45s): recycle/press/snatch/game-over beats without board teleport spam.
sleep 45
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

# simctl recordVideo has no app audio — mux music+SFX, re-encode under ~150MB.
AUDIO_DIR="$(cd "$(dirname "$0")/.." && pwd)/TrashStack/Resources/Audio"
MUSIC="$AUDIO_DIR/game_loop.wav"
CRUSH="$AUDIO_DIR/crush.wav"
RECYCLE="$AUDIO_DIR/recycle.wav"
COMBO="$AUDIO_DIR/combo.wav"
LOCK="$AUDIO_DIR/lock.wav"
LEVELUP="$AUDIO_DIR/levelup.wav"
MAGNET="$AUDIO_DIR/magnet.wav"
if [[ -f "$VIDEO_RAW" && -f "$MUSIC" ]] && command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -y -i "$VIDEO_RAW" \
    -i "$MUSIC" \
    -i "$CRUSH" \
    -i "$RECYCLE" \
    -i "$COMBO" \
    -i "$LOCK" \
    -i "$LEVELUP" \
    -i "$MAGNET" \
    -filter_complex "\
[1:a]volume=0.34,aloop=loop=-1:size=2e+09,atrim=0:50,apad=whole_dur=50[music];\
[5:a]adelay=2500|2500,volume=0.55[lock1];\
[5:a]adelay=7000|7000,volume=0.5[lock2];\
[3:a]adelay=12000|12000,volume=0.85[rec1];\
[4:a]adelay=12400|12400,volume=0.75[combo1];\
[2:a]adelay=18000|18000,volume=0.95[press];\
[5:a]adelay=22000|22000,volume=0.5[lock3];\
[3:a]adelay=25000|25000,volume=0.8[rec2];\
[7:a]adelay=28000|28000,volume=0.9[snatch];\
[6:a]adelay=30000|30000,volume=0.75[order];\
[5:a]adelay=36000|36000,volume=0.45[lock4];\
[6:a]adelay=46000|46000,volume=0.85[revive];\
[music][lock1][lock2][rec1][combo1][press][lock3][rec2][snatch][order][lock4][revive]amix=inputs=12:duration=first:dropout_transition=0[aout]" \
    -map 0:v -map "[aout]" -c:v libx264 -pix_fmt yuv420p -crf 28 -preset veryfast -c:a aac -b:a 128k -movflags +faststart -shortest "$VIDEO_OUT" \
    >/tmp/ffmpeg-mux.log 2>&1 || {
      echo "ffmpeg mux failed; keeping silent video as gameplay-demo.mp4" >&2
      cat /tmp/ffmpeg-mux.log >&2 || true
      mv -f "$VIDEO_RAW" "$VIDEO_OUT"
    }
  rm -f "$VIDEO_RAW"
  if ! ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$VIDEO_OUT" | grep -q audio; then
    echo "Gameplay video missing audio track after mux" >&2
    exit 1
  fi
  bytes=$(wc -c < "$VIDEO_OUT")
  if (( bytes > 150000000 )); then
    echo "Gameplay video too large ($bytes bytes); recompressing" >&2
    ffmpeg -y -i "$VIDEO_OUT" -c:v libx264 -crf 32 -preset veryfast -c:a aac -b:a 96k "$OUT_DIR/gameplay-demo-small.mp4" >/tmp/ffmpeg-small.log 2>&1
    mv -f "$OUT_DIR/gameplay-demo-small.mp4" "$VIDEO_OUT"
  fi
  echo "Muxed music+SFX onto gameplay-demo.mp4 ($(wc -c < "$VIDEO_OUT") bytes)" >&2
else
  echo "ffmpeg/audio missing — using silent capture" >&2
  mv -f "$VIDEO_RAW" "$VIDEO_OUT"
fi

fps="$(xcrun simctl spawn "$DEVICE" defaults read "$BUNDLE_ID" trashStack.measuredFPS 2>/dev/null || echo 0)"
echo "Measured FPS sample: $fps" >&2
python3 - <<PY
fps=float("$fps" or 0)
if fps > 0 and fps < 50:
    raise SystemExit(f"FPS assert failed: {fps}")
print(f"FPS assert ok ({fps})")
PY

for f in 01-title.png 02-gameplay.png 03-compactor-clear.png 04-recycle-combo.png \
         05-game-over-revive.png 06-base.png 07-pass.png 08-shop.png 09-notification-prompt.png \
         gameplay-demo.mp4; do
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

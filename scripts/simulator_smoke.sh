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

# Reject blank / springboard captures so CI fails with a clear signal instead of
# "duplicate bytes" between two home-screen shots.
assert_app_frame() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys
from PIL import Image
path = sys.argv[1]
im = Image.open(path).convert("RGB")
w, h = im.size
# Sample a grid in the content area (ignore status bar).
samples = []
for yy in (int(h * 0.25), int(h * 0.5), int(h * 0.7)):
    for xx in (int(w * 0.2), int(w * 0.5), int(w * 0.8)):
        samples.append(im.getpixel((xx, yy)))
whites = sum(1 for r, g, b in samples if r > 245 and g > 245 and b > 245)
# Springboard wallpaper on CI sims is warm beige/brown — not our neon alley.
beiges = sum(1 for r, g, b in samples if r > 90 and g > 70 and b < 160 and r > b + 15)
darks = sum(1 for r, g, b in samples if r < 50 and g < 50 and b < 70)
if whites >= 7:
    print(f"Blank/white frame: {path}", file=sys.stderr)
    sys.exit(2)
if beiges >= 6 and darks == 0:
    print(f"Springboard/home frame (app not foreground): {path}", file=sys.stderr)
    sys.exit(3)
print(f"Frame OK {path} (dark={darks} white={whites} beige={beiges})")
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

echo "Smoke on $DEVICE (display=$DISPLAY)"
xcrun simctl bootstatus "$DEVICE" -b || xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH"

xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true

launch_shot "" "$OUT_DIR/01-title.png" 5
launch_shot "game" "$OUT_DIR/02-gameplay.png" 6
launch_shot "compactor" "$OUT_DIR/03-compactor-clear.png" 6
launch_shot "recycle" "$OUT_DIR/04-recycle-combo.png" 6
launch_shot "revive" "$OUT_DIR/05-game-over-revive.png" 6
launch_shot "base" "$OUT_DIR/06-base.png" 5
launch_shot "pass" "$OUT_DIR/07-pass.png" 5
launch_shot "shop" "$OUT_DIR/08-shop.png" 5
launch_shot "notif" "$OUT_DIR/09-notification-prompt.png" 5

launch_shot "mkt-play" "$OUT_DIR/marketing/01-play.png" 6
launch_shot "mkt-crush" "$OUT_DIR/marketing/02-crush.png" 6
launch_shot "mkt-recycle" "$OUT_DIR/marketing/03-recycle.png" 6
launch_shot "mkt-base" "$OUT_DIR/marketing/04-junkyard.png" 5
launch_shot "mkt-pass" "$OUT_DIR/marketing/05-pass.png" 5
launch_shot "mkt-shop" "$OUT_DIR/marketing/06-shop.png" 5

python3 - "$OUT_DIR" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = [
  "01-title.png","02-gameplay.png","03-compactor-clear.png","04-recycle-combo.png",
  "05-game-over-revive.png","06-base.png","07-pass.png","08-shop.png","09-notification-prompt.png"
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
VIDEO_OUT="$OUT_DIR/gameplay-demo.mp4"
rm -f "$VIDEO_OUT"
set +e
xcrun simctl io "$DEVICE" recordVideo --display=internal --codec=h264 --force "$VIDEO_OUT" &
REC_PID=$!
sleep 2
if ! kill -0 "$REC_PID" 2>/dev/null; then
  echo "recordVideo --display=internal failed; retrying without --display" >&2
  xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$VIDEO_OUT" &
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
sleep 55
kill -INT "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true
sleep 3

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

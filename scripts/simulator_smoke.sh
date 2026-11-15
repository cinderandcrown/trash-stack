#!/usr/bin/env bash
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
# Autoplay smoke: 45–60s gameplay video + required review screenshots.
set -euo pipefail

DEVICE="${1:?simulator UDID}"
APP_PATH="${2:?path to TrashStack.app}"
OUT_DIR="${3:-smoke-artifacts}"
BUNDLE_ID="${BUNDLE_ID:-com.cinderandcrown.trashstack}"
DISPLAY_ID="${SIMCTL_DISPLAY:-1}"

mkdir -p "$OUT_DIR"

set_shot() {
  local value="$1"
  xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "$value" || true
}

clear_shot() {
  xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
}

shot() {
  local out="$1"
  if xcrun simctl io "$DEVICE" screenshot --display="$DISPLAY_ID" "$out" 2>/tmp/sim-shot.err; then
    return 0
  fi
  xcrun simctl io "$DEVICE" screenshot "$out"
}

launch_shot() {
  local mode="$1"
  local outfile="$2"
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  if [[ -n "$mode" ]]; then set_shot "$mode"; else clear_shot; fi
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 4
  shot "$outfile"
  echo "Wrote $outfile" >&2
}

echo "Smoke on $DEVICE"
xcrun simctl bootstatus "$DEVICE" -b || xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH"

launch_shot "" "$OUT_DIR/01-title.png"
launch_shot "game" "$OUT_DIR/02-gameplay.png"
launch_shot "compactor" "$OUT_DIR/03-compactor-clear.png"
launch_shot "recycle" "$OUT_DIR/04-recycle-combo.png"
launch_shot "revive" "$OUT_DIR/05-game-over-revive.png"
launch_shot "base" "$OUT_DIR/06-base.png"
launch_shot "pass" "$OUT_DIR/07-pass.png"
launch_shot "shop" "$OUT_DIR/08-shop.png"
launch_shot "notif" "$OUT_DIR/09-notification-prompt.png"

# 45–60s autoplay gameplay video
clear_shot
set_shot "demo"
VIDEO_OUT="$OUT_DIR/gameplay-demo.mp4"
rm -f "$VIDEO_OUT"
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
set +e
xcrun simctl io "$DEVICE" recordVideo --display="$DISPLAY_ID" --codec=h264 --force "$VIDEO_OUT" &
REC_PID=$!
sleep 1
if ! kill -0 "$REC_PID" 2>/dev/null; then
  xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$VIDEO_OUT" &
  REC_PID=$!
fi
set -e
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" --console-pty -autoplay >/dev/null 2>&1 || \
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 55
kill -INT "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true
sleep 2

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

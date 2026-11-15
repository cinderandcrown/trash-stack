#!/usr/bin/env bash
# Capture App Store screenshots (6.9" + 6.5") and a 45–60s gameplay demo video
# from the iOS Simulator. Usage: ios-screenshots.sh <DerivedData-path>
set -euo pipefail

DERIVED="${1:?DerivedData path required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/artifacts/screenshots"
VID="$ROOT/artifacts/video"
mkdir -p "$OUT" "$VID"

APP_PATH="$(find "$DERIVED" -name 'App.app' -type d | head -n 1 || true)"
if [[ -z "$APP_PATH" ]]; then
  echo "Could not find App.app under $DERIVED" >&2
  exit 1
fi

BUNDLE_ID="com.cinderandcrown.trashstack"

set_shot_pref() {
  local udid="$1"
  local value="$2"
  xcrun simctl spawn "$udid" defaults write "$BUNDLE_ID" "trashStack.shot" -string "$value" || true
}

clear_shot_pref() {
  local udid="$1"
  xcrun simctl spawn "$udid" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
}

prepare_device() {
  local device_name="$1"
  local udid=""
  if ! xcrun simctl list devices available | grep -F "$device_name (" >/dev/null; then
    echo "Device type not available: $device_name" >&2
    return 1
  fi
  udid="$(xcrun simctl list devices available | grep -F "$device_name (" | head -n 1 | grep -oE '[0-9A-F-]{36}' || true)"
  if [[ -z "$udid" ]]; then
    echo "No UDID for $device_name" >&2
    return 1
  fi
  xcrun simctl bootstatus "$udid" -b 2>/dev/null || xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP_PATH"
  echo "$udid"
}

shot_once() {
  local udid="$1"
  local label="$2"
  local shot="$3"
  local outfile="$4"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  if [[ -n "$shot" ]]; then
    set_shot_pref "$udid" "$shot"
  else
    clear_shot_pref "$udid"
  fi
  xcrun simctl launch "$udid" "$BUNDLE_ID" || true
  sleep 5
  xcrun simctl io "$udid" screenshot "$outfile"
  echo "Wrote $outfile"
}

boot_and_shot() {
  local device_name="$1"
  local label="$2"
  local udid
  echo "Preparing simulator: $device_name ($label)"
  udid="$(prepare_device "$device_name")" || return 0

  shot_once "$udid" "$label" "" "$OUT/${label}-title.png"
  shot_once "$udid" "$label" "game" "$OUT/${label}-game.png"
  shot_once "$udid" "$label" "shop" "$OUT/${label}-shop.png"
  shot_once "$udid" "$label" "challenges" "$OUT/${label}-challenges.png"
  shot_once "$udid" "$label" "achievements" "$OUT/${label}-achievements.png"
  shot_once "$udid" "$label" "settings" "$OUT/${label}-settings.png"

  # Captioned marketing copies (same frames; captions noted in STORE.md)
  cp "$OUT/${label}-title.png" "$OUT/${label}-01-title-caption.png"
  cp "$OUT/${label}-game.png" "$OUT/${label}-02-compactor-caption.png"
  cp "$OUT/${label}-shop.png" "$OUT/${label}-03-shop-caption.png"
  cp "$OUT/${label}-challenges.png" "$OUT/${label}-04-hustle-caption.png"
  cp "$OUT/${label}-achievements.png" "$OUT/${label}-05-achievements-caption.png"
  cp "$OUT/${label}-settings.png" "$OUT/${label}-06-settings-caption.png"

  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
}

record_demo_video() {
  local device_name="iPhone 16 Pro Max"
  local udid
  echo "Recording gameplay demo on $device_name"
  udid="$(prepare_device "$device_name")" || return 0

  local raw="$VID/gameplay-demo-raw.mp4"
  local out="$VID/gameplay-demo.mp4"
  rm -f "$raw" "$out"

  clear_shot_pref "$udid"
  set_shot_pref "$udid" "demo"
  # Start recording, then launch so the demo sequence is captured
  xcrun simctl io "$udid" recordVideo --codec=h264 --force "$raw" &
  local rec_pid=$!
  sleep 1
  xcrun simctl launch "$udid" "$BUNDLE_ID" || true

  # Demo script is ~50s; record 55s then stop
  sleep 55
  kill -INT "$rec_pid" 2>/dev/null || true
  wait "$rec_pid" 2>/dev/null || true
  sleep 2

  if [[ -f "$raw" ]]; then
    # Prefer a trimmed copy under 60s if ffmpeg exists; else keep raw
    if command -v ffmpeg >/dev/null 2>&1; then
      ffmpeg -y -i "$raw" -t 58 -c copy "$out" >/dev/null 2>&1 || cp "$raw" "$out"
    else
      cp "$raw" "$out"
    fi
    # Also place under screenshots folder for a single artifact upload convenience
    cp "$out" "$OUT/gameplay-demo.mp4"
    ls -la "$out" "$OUT/gameplay-demo.mp4"
    echo "Demo video ready"
  else
    echo "WARNING: demo video was not produced" >&2
  fi

  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
}

boot_and_shot "iPhone 16 Pro Max" "iphone-6.9"

if xcrun simctl list devices available | grep -q "iPhone 15 Plus"; then
  boot_and_shot "iPhone 15 Plus" "iphone-6.5"
elif xcrun simctl list devices available | grep -q "iPhone 11 Pro Max"; then
  boot_and_shot "iPhone 11 Pro Max" "iphone-6.5"
elif xcrun simctl list devices available | grep -q "iPhone 14 Plus"; then
  boot_and_shot "iPhone 14 Plus" "iphone-6.5"
else
  echo "No 6.5-inch simulator runtime available on this runner" >&2
fi

record_demo_video

ls -la "$OUT" || true
ls -la "$VID" || true
echo "Screenshot + video capture complete"

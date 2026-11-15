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

# Echo ONLY the UDID on stdout. All simctl chatter goes to stderr.
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
  echo "Booting $device_name ($udid)" >&2
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  # Give SpringBoard a moment after first boot migrations
  sleep 3
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP_PATH" >&2
  printf '%s\n' "$udid"
}

shot_once() {
  local udid="$1"
  local shot="$2"
  local outfile="$3"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  if [[ -n "$shot" ]]; then
    set_shot_pref "$udid" "$shot"
  else
    clear_shot_pref "$udid"
  fi
  xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 5
  xcrun simctl io "$udid" screenshot "$outfile"
  echo "Wrote $outfile" >&2
}

boot_and_shot() {
  local device_name="$1"
  local label="$2"
  local udid
  echo "Preparing simulator: $device_name ($label)" >&2
  if ! udid="$(prepare_device "$device_name")"; then
    echo "Skipping $label — device unavailable" >&2
    return 0
  fi
  # Sanity: UDID must be a UUID only
  if ! [[ "$udid" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    echo "Bad UDID capture: [$udid]" >&2
    return 1
  fi

  shot_once "$udid" "" "$OUT/${label}-title.png"
  shot_once "$udid" "game" "$OUT/${label}-game.png"
  shot_once "$udid" "shop" "$OUT/${label}-shop.png"
  shot_once "$udid" "challenges" "$OUT/${label}-challenges.png"
  shot_once "$udid" "achievements" "$OUT/${label}-achievements.png"
  shot_once "$udid" "settings" "$OUT/${label}-settings.png"

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
  echo "Recording gameplay demo on $device_name" >&2
  if ! udid="$(prepare_device "$device_name")"; then
    echo "WARNING: could not prepare device for demo video" >&2
    return 0
  fi
  if ! [[ "$udid" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    echo "Bad UDID for video: [$udid]" >&2
    return 1
  fi

  local raw="$VID/gameplay-demo-raw.mp4"
  local out="$VID/gameplay-demo.mp4"
  rm -f "$raw" "$out"

  clear_shot_pref "$udid"
  set_shot_pref "$udid" "demo"

  # Record in background; stop with SIGINT so simctl finalizes the file
  xcrun simctl io "$udid" recordVideo --codec=h264 --force "$raw" >/dev/null 2>&1 &
  local rec_pid=$!
  sleep 2
  xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true

  sleep 55
  kill -INT "$rec_pid" 2>/dev/null || true
  # Wait up to 30s for finalize
  for _ in $(seq 1 30); do
    if ! kill -0 "$rec_pid" 2>/dev/null; then break; fi
    sleep 1
  done
  wait "$rec_pid" 2>/dev/null || true
  sleep 2

  if [[ -f "$raw" && -s "$raw" ]]; then
    if command -v ffmpeg >/dev/null 2>&1; then
      ffmpeg -y -i "$raw" -t 58 -c copy "$out" >/dev/null 2>&1 || cp "$raw" "$out"
    else
      cp "$raw" "$out"
    fi
    cp "$out" "$OUT/gameplay-demo.mp4"
    ls -la "$out" "$OUT/gameplay-demo.mp4" >&2
    echo "Demo video ready" >&2
  else
    echo "ERROR: demo video was not produced at $raw" >&2
    return 1
  fi

  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
}

ensure_device() {
  # Create a named simulator if missing (needed for 6.5" on some runners).
  local name="$1"
  local type_id="$2"
  if xcrun simctl list devices available | grep -F "$name (" >/dev/null; then
    return 0
  fi
  local runtime
  runtime="$(xcrun simctl list runtimes available | grep -E 'iOS [0-9]+' | tail -1 | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.[^ ]+' || true)"
  if [[ -z "$runtime" ]]; then
    echo "No iOS runtime to create $name" >&2
    return 1
  fi
  echo "Creating simulator $name ($type_id / $runtime)" >&2
  xcrun simctl create "$name" "$type_id" "$runtime" >/dev/null || true
}

boot_and_shot "iPhone 16 Pro Max" "iphone-6.9"

ensure_device "iPhone 15 Plus" "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Plus" || true
ensure_device "iPhone 11 Pro Max" "com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max" || true

if xcrun simctl list devices available | grep -q "iPhone 15 Plus"; then
  boot_and_shot "iPhone 15 Plus" "iphone-6.5"
elif xcrun simctl list devices available | grep -q "iPhone 11 Pro Max"; then
  boot_and_shot "iPhone 11 Pro Max" "iphone-6.5"
elif xcrun simctl list devices available | grep -q "iPhone 14 Plus"; then
  boot_and_shot "iPhone 14 Plus" "iphone-6.5"
elif xcrun simctl list devices available | grep -q "iPhone 16 Plus"; then
  # Closest available Plus form-factor if classic 6.5" types are unavailable
  boot_and_shot "iPhone 16 Plus" "iphone-6.5"
else
  echo "No 6.5-inch-class simulator available on this runner" >&2
fi

record_demo_video

ls -la "$OUT" >&2 || true
ls -la "$VID" >&2 || true
echo "Screenshot + video capture complete"

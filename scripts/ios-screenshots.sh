#!/usr/bin/env bash
# Capture App Store screenshots from the iOS Simulator for 6.9" and 6.5" phones.
# Usage: ios-screenshots.sh <DerivedData-path>
set -euo pipefail

DERIVED="${1:?DerivedData path required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/artifacts/screenshots"
mkdir -p "$OUT"

APP_PATH="$(find "$DERIVED" -name 'App.app' -type d | head -n 1 || true)"
if [[ -z "$APP_PATH" ]]; then
  echo "Could not find App.app under $DERIVED" >&2
  exit 1
fi

BUNDLE_ID="com.cinderandcrown.trashstack"

set_shot_pref() {
  local udid="$1"
  local value="$2"
  # Capacitor Preferences on iOS uses the app's standard UserDefaults suite.
  xcrun simctl spawn "$udid" defaults write "$BUNDLE_ID" "trashStack.shot" -string "$value" || true
}

boot_and_shot() {
  local device_name="$1"
  local label="$2"
  local udid

  echo "Preparing simulator: $device_name ($label)"
  if ! xcrun simctl list devices available | grep -F "$device_name (" >/dev/null; then
    echo "Device type not available: $device_name — skipping $label" >&2
    return 0
  fi

  udid="$(xcrun simctl list devices available | grep -F "$device_name (" | head -n 1 | grep -oE '[0-9A-F-]{36}' || true)"
  if [[ -z "$udid" ]]; then
    echo "No UDID for $device_name — skipping" >&2
    return 0
  fi

  xcrun simctl bootstatus "$udid" -b 2>/dev/null || xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP_PATH"

  # Title screen (no shot pref)
  xcrun simctl spawn "$udid" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$BUNDLE_ID" || true
  sleep 5
  xcrun simctl io "$udid" screenshot "$OUT/${label}-title.png"
  echo "Wrote $OUT/${label}-title.png"

  # Gameplay
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  set_shot_pref "$udid" "game"
  xcrun simctl launch "$udid" "$BUNDLE_ID" || true
  sleep 6
  xcrun simctl io "$udid" screenshot "$OUT/${label}-game.png"
  echo "Wrote $OUT/${label}-game.png"

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

ls -la "$OUT" || true
echo "Screenshot capture complete"

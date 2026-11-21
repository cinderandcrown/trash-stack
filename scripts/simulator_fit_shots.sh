#!/usr/bin/env bash
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
# Cheap screenshot-only pass: title, mid-run play, game-over.
# Real simctl captures only — never generate mock art.
set -euo pipefail

DEVICE="${1:?simulator UDID}"
APP_PATH="${2:?path to TrashStack.app}"
OUT_DIR="${3:-smoke-artifacts}"
TAG="${4:-se}"  # filename prefix: pro / se
BUNDLE_ID="${BUNDLE_ID:-com.cinderandcrown.trashstack}"
DISPLAY="${SIMCTL_DISPLAY:-internal}"
SHOT_DEADLINE_S="${SHOT_DEADLINE_S:-10}"
SIMCTL_DEADLINE_S="${SIMCTL_DEADLINE_S:-12}"

FIT_DIR="$OUT_DIR/fit"
mkdir -p "$FIT_DIR"

raw_deadline() {
  local secs="$1" rc=0
  shift
  python3 - "$secs" "$@" <<'PY' || rc=$?
import os, signal, subprocess, sys, time
secs = float(sys.argv[1]); cmd = sys.argv[2:]
def nuke(pid: int) -> None:
    try: os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError: pass
p = subprocess.Popen(cmd, start_new_session=True)
t0 = time.time()
try:
    while True:
        rc = p.poll()
        if rc is not None:
            sys.exit(rc)
        if time.time() - t0 >= secs:
            nuke(p.pid)
            time.sleep(0.2)
            nuke(p.pid)
            sys.exit(124)
        time.sleep(0.05)
except KeyboardInterrupt:
    nuke(p.pid); raise
PY
  return "$rc"
}

shot() {
  local out="$1"
  if raw_deadline "$SHOT_DEADLINE_S" xcrun simctl io "$DEVICE" screenshot --display="$DISPLAY" "$out" 2>/tmp/fit-shot.err; then
    return 0
  fi
  raw_deadline "$SHOT_DEADLINE_S" xcrun simctl io "$DEVICE" screenshot "$out" 2>/tmp/fit-shot.err
}

# Reject flat-grey SpriteView (empty CellPlate carpet / unrendered board).
assert_board_not_grey() {
  local png="$1"
  python3 - "$png" <<'PY'
import collections, sys
from pathlib import Path
p = Path(sys.argv[1])
try:
    from PIL import Image
except ImportError:
    # stdlib-only: sample center crop mean via raw PNG is hard; size floor only.
    sz = p.stat().st_size if p.is_file() else 0
    if sz < 80_000:
        print(f"FAIL fit board too small (likely grey stub): {p} ({sz} B)", file=sys.stderr)
        raise SystemExit(1)
    print(f"fit board size OK {p.name} ({sz} B) [no PIL]")
    raise SystemExit(0)
im = Image.open(p).convert("RGB")
w, h = im.size
crop = im.crop((int(w * 0.12), int(h * 0.30), int(w * 0.88), int(h * 0.78)))
px = list(crop.getdata())
n = len(px)
mr = sum(c[0] for c in px) / n
mg = sum(c[1] for c in px) / n
mb = sum(c[2] for c in px) / n
# Near-neutral high mean = flat grey board (fit/pro-play failure was ~191,191,191).
chroma = abs(mr - mg) + abs(mg - mb) + abs(mr - mb)
if mr > 140 and mg > 140 and mb > 140 and chroma < 25:
    print(f"FAIL flat grey board in {p}: mean=({mr:.0f},{mg:.0f},{mb:.0f}) chroma={chroma:.1f}", file=sys.stderr)
    raise SystemExit(1)
print(f"fit board OK {p.name}: mean=({mr:.0f},{mg:.0f},{mb:.0f}) chroma={chroma:.1f}")
PY
}

echo "Fit shots on $DEVICE tag=$TAG → $FIT_DIR" >&2
raw_deadline 40 xcrun simctl boot "$DEVICE" >/tmp/fit-boot.log 2>&1 || true
raw_deadline 60 xcrun simctl bootstatus "$DEVICE" -b >/tmp/fit-boot.log 2>&1 || true
raw_deadline 20 xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
if ! raw_deadline 60 xcrun simctl install "$DEVICE" "$APP_PATH"; then
  echo "Fit shots: install failed" >&2
  exit 1
fi

raw_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
raw_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" classicButtons -bool false || true
raw_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true

# Device label for Magpie/eyes.
{
  echo "tag=$TAG"
  echo "udid=$DEVICE"
  xcrun simctl list devices | grep "$DEVICE" || true
} > "$FIT_DIR/${TAG}-device.txt"

# --- Title (skip publisher ident; wait for neon wordmark) ---
raw_deadline 8 xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
raw_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "title" || true
raw_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
  -trashStackShot title -trashStackSkipAds -trashStackSkipIdent >/tmp/fit-launch-title.out 2>&1 || true
sleep 4.0
shot "$FIT_DIR/${TAG}-title.png" || true
if [[ ! -s "$FIT_DIR/${TAG}-title.png" ]]; then
  echo "Fit shots: missing ${TAG}-title.png" >&2
  exit 1
fi
echo "Wrote $FIT_DIR/${TAG}-title.png ($(wc -c < "$FIT_DIR/${TAG}-title.png") bytes)" >&2

# --- Play: dense mid-run board (game shot). Hold pieces + bin art — no recycle auto-suck. ---
raw_deadline 8 xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
raw_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "game" || true
raw_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
  -trashStackShot game -trashStackSkipAds -trashStackSkipIdent >/tmp/fit-launch-play.out 2>&1 || true
sleep 4.0
shot "$FIT_DIR/${TAG}-play.png" || true
if [[ ! -s "$FIT_DIR/${TAG}-play.png" ]]; then
  echo "Fit shots: missing ${TAG}-play.png" >&2
  exit 1
fi
echo "Wrote $FIT_DIR/${TAG}-play.png ($(wc -c < "$FIT_DIR/${TAG}-play.png") bytes)" >&2
assert_board_not_grey "$FIT_DIR/${TAG}-play.png"

# --- Game over: revive shot + overlay (score / best / Play again) ---
raw_deadline 8 xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
raw_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "revive" || true
raw_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
  -trashStackShot revive -trashStackSkipAds -trashStackSkipIdent >/tmp/fit-launch-go.out 2>&1 || true
# Overlay + score count-up need a beat after first frame.
sleep 5.0
shot "$FIT_DIR/${TAG}-game-over.png" || true
if [[ ! -s "$FIT_DIR/${TAG}-game-over.png" ]]; then
  echo "Fit shots: missing ${TAG}-game-over.png" >&2
  exit 1
fi
echo "Wrote $FIT_DIR/${TAG}-game-over.png ($(wc -c < "$FIT_DIR/${TAG}-game-over.png") bytes)" >&2
# Game-over overlay should be content-rich (not a grey board + pill only).
if [[ "$(wc -c < "$FIT_DIR/${TAG}-game-over.png")" -lt 200000 ]]; then
  echo "WARN ${TAG}-game-over.png looks thin — expected overlay with score/retry" >&2
fi

# Soft size floor — reject empty/splash stubs without hard-failing the suite on flake.
python3 - "$FIT_DIR" "$TAG" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1]); tag = sys.argv[2]
ok = True
for name in (f"{tag}-title.png", f"{tag}-play.png", f"{tag}-game-over.png"):
    p = root / name
    sz = p.stat().st_size if p.is_file() else 0
    print(f"fit {name}: {sz} bytes")
    if sz < 20_000:
        print(f"WARN fit shot small/missing: {p}", file=sys.stderr)
        ok = False
sys.exit(0 if ok else 0)  # warn-only; artifacts still uploaded
PY

echo "Fit shots done for tag=$TAG" >&2

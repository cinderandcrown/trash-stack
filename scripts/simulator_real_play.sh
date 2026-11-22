#!/usr/bin/env bash
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
# Record a real New Game session (no shot seeds / demo swaps) via XCUITest gestures.
# XCTest owns the launch (same as 1d0ae10). Do NOT pre-launch the app before
# recordVideo — that left an idle title on camera for the whole XCTest bootstrap,
# then the runner terminated it (home screen) before PLAY was ever tapped.
set -euo pipefail

DEVICE="${1:?simulator UDID}"
APP_PATH="${2:?path to TrashStack.app}"
OUT_DIR="${3:-smoke-artifacts}"
BUNDLE_ID="${BUNDLE_ID:-com.cinderandcrown.trashstack}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT_DIR"

RAW="$OUT_DIR/real-play-silent.mp4"
OUT="$OUT_DIR/real-play.mp4"
rm -f "$RAW" "$OUT" "$OUT_DIR"/real-play-silent.mp4.sb-* 2>/dev/null || true

echo "Real-play record on $DEVICE → $OUT" >&2

xcrun simctl boot "$DEVICE" >/tmp/real-play-boot.log 2>&1 || true
xcrun simctl bootstatus "$DEVICE" -b >/tmp/real-play-boot.log 2>&1 || true
xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH"

# Fresh profile: tutorial done, no shot mode, no seeded boards.
xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true >/dev/null 2>&1 || true
xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" classicButtons -bool false >/dev/null 2>&1 || true
xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true >/dev/null 2>&1 || true
xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shotActive" >/dev/null 2>&1 || true

REC_PID=""
finalize() {
  if [[ -n "${REC_PID:-}" ]] && kill -0 "$REC_PID" 2>/dev/null; then
    kill -INT "$REC_PID" 2>/dev/null || true
    sleep 3
    kill -KILL "$REC_PID" 2>/dev/null || true
  fi
  if [[ ! -s "$RAW" ]]; then
    best=""; best_sz=0
    for cand in "$OUT_DIR"/real-play-silent.mp4.sb-*; do
      [[ -f "$cand" ]] || continue
      sz=$(wc -c < "$cand" | tr -d ' ')
      if (( sz > best_sz )); then best="$cand"; best_sz=$sz; fi
    done
    if [[ -n "$best" && "$best_sz" -gt 200000 ]]; then
      echo "Promoting partial $best ($best_sz) → $RAW" >&2
      mv -f "$best" "$RAW"
    fi
  fi
}
trap finalize EXIT

# Stamp wall clock so we can trim XCTest bootstrap out of the export.
RECORD_START_EPOCH="$(python3 -c 'import time; print(f"{time.time():.6f}")')"
echo "$RECORD_START_EPOCH" > "$OUT_DIR/record-start-epoch.txt"

# Start recording, then XCTest launches straight into the board (-UITestRealPlay → .game).
xcrun simctl io "$DEVICE" recordVideo --display=internal --codec=h264 --force "$RAW" &
REC_PID=$!
sleep 1
if ! kill -0 "$REC_PID" 2>/dev/null; then
  xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$RAW" &
  REC_PID=$!
  sleep 1
fi
if ! kill -0 "$REC_PID" 2>/dev/null; then
  echo "recordVideo failed to start" >&2
  finalize
  trap - EXIT
  exit 1
fi
echo "Recording started at epoch $RECORD_START_EPOCH (XCTest → game board)" >&2

set +e
xcodebuild test-without-building \
  -project "$PROJECT_ROOT/TrashStack.xcodeproj" \
  -scheme TrashStack \
  -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath "$PROJECT_ROOT/DerivedData" \
  -only-testing:TrashStackUITests/RealPlayUITests/testRealPlaySession \
  -parallel-testing-enabled NO \
  >/tmp/real-play-xctest.log 2>&1
XC_EC=$?
set -e

if (( XC_EC != 0 )) && grep -Eqi 'isn.t a member|not found|does not contain|Unable to find|no such module' /tmp/real-play-xctest.log; then
  echo "UITests scheme/build miss — regenerating + xcodebuild test" >&2
  if command -v xcodegen >/dev/null 2>&1; then
    (cd "$PROJECT_ROOT" && xcodegen generate) >/tmp/real-play-xcodegen.log 2>&1 || true
  fi
  set +e
  xcodebuild test \
    -project "$PROJECT_ROOT/TrashStack.xcodeproj" \
    -scheme TrashStack \
    -destination "platform=iOS Simulator,id=$DEVICE" \
    -derivedDataPath "$PROJECT_ROOT/DerivedData" \
    -only-testing:TrashStackUITests/RealPlayUITests/testRealPlaySession \
    -parallel-testing-enabled NO \
    >/tmp/real-play-xctest.log 2>&1
  XC_EC=$?
  set -e
fi

# Always stop the recorder and mux — even when XCTest fails — so Magpie can review play.
grep -E 'RealPlay gestures=|testRealPlaySession|error:' /tmp/real-play-xctest.log | tail -n 40 >&2 || true

finalize
trap - EXIT
REC_PID=""

# Stamp the commit this app was built from (same-job DerivedData).
git -C "$PROJECT_ROOT" rev-parse HEAD > "$OUT_DIR/real-play-git-sha.txt" 2>/dev/null || true
echo "real-play git sha: $(cat "$OUT_DIR/real-play-git-sha.txt" 2>/dev/null || echo unknown)" >&2

if [[ ! -s "$RAW" ]]; then
  echo "real-play silent capture missing" >&2
  ls -la "$OUT_DIR"/real-play* >&2 || true
  exit 1
fi

FFMPEG_BIN="$(command -v ffmpeg || true)"
for cand in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
  [[ -z "$FFMPEG_BIN" && -x "$cand" ]] && FFMPEG_BIN="$cand"
done
MUSIC="$PROJECT_ROOT/TrashStack/Resources/Audio/game_loop.wav"

# Trim XCTest bootstrap so play starts within ~10s of the exported video.
# Prefer Documents stamp (reliable), then string defaults, then float defaults.
# simctl `defaults read` of a Double often returns empty — never rely on it alone.
SS="0"
GAME_EPOCH=""
CONTAINER="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)"
if [[ -n "${CONTAINER:-}" && -f "$CONTAINER/Documents/launch-timing.txt" ]]; then
  GAME_EPOCH="$(grep -E '^game_first_frame_wall_epoch=' "$CONTAINER/Documents/launch-timing.txt" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]')"
fi
if [[ -z "${GAME_EPOCH:-}" ]]; then
  GAME_EPOCH="$(xcrun simctl spawn "$DEVICE" defaults read "$BUNDLE_ID" trashStack.firstGameFrameWallEpochString 2>/dev/null | tr -d '[:space:]\"' || true)"
fi
if [[ -z "${GAME_EPOCH:-}" ]]; then
  GAME_EPOCH="$(xcrun simctl spawn "$DEVICE" defaults read "$BUNDLE_ID" trashStack.firstGameFrameWallEpoch 2>/dev/null | tr -d '[:space:]\"' || true)"
fi
if [[ -n "${GAME_EPOCH:-}" && -n "${RECORD_START_EPOCH:-}" ]]; then
  SS="$(python3 - <<PY
start=float("${RECORD_START_EPOCH}")
game=float("${GAME_EPOCH}")
ss=max(0.0, game - start - 0.4)
print(f"{min(ss, 90.0):.3f}")
PY
)"
fi
# Last resort: scan silent capture for first neon play frame (skip springboard + dark splash).
if python3 -c "import sys; sys.exit(0 if float('${SS:-0}') < 1.0 else 1)" 2>/dev/null; then
  DETECTED="$(python3 - "$RAW" <<'PY'
import subprocess, sys
path = sys.argv[1]
# Springboard = bright. Publisher splash = near-black, no neon. Play = dark + cyan/magenta neon.
# XCTest bootstrap can exceed 2 minutes — scan well past that.
for t in range(0, 200, 1):
    raw = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", str(t), "-i", path,
         "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "96x192", "pipe:1"],
        capture_output=True,
    ).stdout
    if len(raw) < 96 * 192 * 3:
        continue
    n = len(raw) // 3
    luma = 0.0
    neon = 0
    for i in range(0, len(raw), 3):
        r, g, b = raw[i], raw[i + 1], raw[i + 2]
        luma += 0.2126 * r + 0.7152 * g + 0.0722 * b
        if (g > 140 and b > 140 and r < 100) or (r > 160 and b > 120 and g < 100):
            neon += 1
    mean = luma / n
    if mean < 55 and neon >= 20:
        print(f"{max(0, t - 1)}")
        break
else:
    print("0")
PY
)"
  if [[ -n "${DETECTED:-}" && "${DETECTED}" != "0" ]]; then
    SS="$DETECTED"
    echo "real-play trim fallback scanned play@${SS}s" >&2
  fi
fi
echo "real-play trim start=${SS}s (record=$RECORD_START_EPOCH game=${GAME_EPOCH:-none})" >&2
# Guard: exported window must include play — if SS is still 0 on a long capture, force last 70s.
if python3 -c "import sys; sys.exit(0 if float('${SS:-0}') < 1.0 else 1)" 2>/dev/null; then
  RAW_DUR="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$RAW" 2>/dev/null || echo 0)"
  SS="$(python3 - <<PY
dur=float("${RAW_DUR}" or 0)
print(f"{max(0.0, dur - 72.0):.3f}")
PY
)"
  echo "real-play trim last-resort SS=${SS}s (dur=${RAW_DUR})" >&2
fi

# Preserve wall-clock pacing: reset PTS, then fps=30 holds/duplicates frames to fill
# gaps (calm beats stay calm; place/clear/chain keep their real duration). Packing with
# setpts=N/30/TB caused jumps. Never put -ss before -i on these files.
if [[ -n "$FFMPEG_BIN" && -f "$MUSIC" ]]; then
  "$FFMPEG_BIN" -hide_banner -y -i "$RAW" -stream_loop -1 -i "$MUSIC" \
    -filter_complex "[0:v]trim=start=${SS},setpts=PTS-STARTPTS,fps=30,trim=duration=90,setpts=PTS-STARTPTS[vout];[1:a]volume=0.34,atrim=start=${SS}:duration=90,asetpts=PTS-STARTPTS[aout]" \
    -map "[vout]" -map "[aout]" -r 30 -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
    -c:a aac -b:a 128k -ac 1 -movflags +faststart "$OUT" \
    >/tmp/real-play-mux.log 2>&1 || cp -f "$RAW" "$OUT"
elif [[ -n "$FFMPEG_BIN" ]]; then
  "$FFMPEG_BIN" -hide_banner -y -i "$RAW" \
    -vf "trim=start=${SS},setpts=PTS-STARTPTS,fps=30,trim=duration=90,setpts=PTS-STARTPTS" \
    -r 30 -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -an -movflags +faststart "$OUT" \
    >/tmp/real-play-mux.log 2>&1 || cp -f "$RAW" "$OUT"
else
  cp -f "$RAW" "$OUT"
fi

python3 - "$OUT" <<'PY'
import subprocess, sys, json, pathlib
path = pathlib.Path(sys.argv[1])
sz = path.stat().st_size
if sz < 1_000_000:
    print(f"FAIL real-play too small ({sz} B)", file=sys.stderr)
    raise SystemExit(1)
probe = None
for bin in ("ffprobe", "/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"):
    try:
        out = subprocess.check_output(
            [bin, "-v", "error", "-select_streams", "v:0",
             "-count_packets", "-show_entries", "stream=nb_read_packets,duration,avg_frame_rate",
             "-of", "json", str(path)],
            text=True, stderr=subprocess.DEVNULL,
        )
        probe = json.loads(out)
        break
    except Exception:
        continue
if probe and probe.get("streams"):
    s = probe["streams"][0]
    pkts = int(s.get("nb_read_packets") or 0)
    dur = float(s.get("duration") or 0)
    print(f"real-play OK {path.name}: {sz} bytes packets={pkts} duration={dur:.1f}s")
    if dur < 40:
        print(f"FAIL real-play too short ({dur:.1f}s)", file=sys.stderr)
        raise SystemExit(1)
    if pkts > 0 and pkts / max(dur, 1) < 12:
        print(f"FAIL real-play looks static (~{pkts/max(dur,1):.1f} fps packets)", file=sys.stderr)
        raise SystemExit(1)
else:
    print(f"real-play OK {path.name}: {sz} bytes (no ffprobe)")
PY

echo "Wrote $OUT ($(wc -c < "$OUT") bytes)" >&2
if (( XC_EC != 0 )); then
  echo "Real-play UITest failed (ec=$XC_EC) — mux kept for review" >&2
  tail -n 40 /tmp/real-play-xctest.log >&2 || true
fi
exit "$XC_EC"

#!/usr/bin/env bash
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
# Record a real New Game session (no shot seeds / demo swaps) via XCUITest gestures.
# Recording starts only after the app is frontmost so the clip begins on title, not Springboard.
set -euo pipefail

DEVICE="${1:?simulator UDID}"
APP_PATH="${2:?path to TrashStack.app}"
OUT_DIR="${3:-smoke-artifacts}"
BUNDLE_ID="${BUNDLE_ID:-com.cinderandcrown.trashstack}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT_DIR"

RAW="$OUT_DIR/real-play-silent.mp4"
OUT="$OUT_DIR/real-play.mp4"
rm -f "$RAW" "$OUT" "$OUT_DIR"/real-play-silent.mp4.sb-* /tmp/real-play-app-up 2>/dev/null || true

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

# Pre-launch to title so recordVideo begins on product UI (not Springboard).
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
  -UITestRealPlay -trashStackSkipAds -trashStackSkipIdent \
  >/tmp/real-play-prelaunch.log 2>&1 || true
sleep 2.5

xcrun simctl io "$DEVICE" recordVideo --display=internal --codec=h264 --force "$RAW" &
REC_PID=$!
sleep 2
if ! kill -0 "$REC_PID" 2>/dev/null; then
  xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$RAW" &
  REC_PID=$!
  sleep 2
fi
if ! kill -0 "$REC_PID" 2>/dev/null; then
  echo "recordVideo failed to start" >&2
  finalize
  trap - EXIT
  exit 1
fi
echo "Recording started (title pre-launch)" >&2

# XCTest relaunches into the same harness; gestures drive the live loop under recordVideo.
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
  if [[ -n "${REC_PID:-}" ]] && kill -0 "$REC_PID" 2>/dev/null; then
    kill -INT "$REC_PID" 2>/dev/null || true
    sleep 2
    kill -KILL "$REC_PID" 2>/dev/null || true
  fi
  REC_PID=""
  rm -f "$RAW"
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
    -UITestRealPlay -trashStackSkipAds -trashStackSkipIdent >/dev/null 2>&1 || true
  sleep 2
  xcrun simctl io "$DEVICE" recordVideo --display=internal --codec=h264 --force "$RAW" &
  REC_PID=$!
  sleep 2
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

if (( XC_EC != 0 )); then
  echo "Real-play UITest failed (ec=$XC_EC) — log tail:" >&2
  tail -n 120 /tmp/real-play-xctest.log >&2 || true
  finalize
  trap - EXIT
  exit "$XC_EC"
fi

finalize
trap - EXIT
REC_PID=""

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

if [[ -n "$FFMPEG_BIN" && -f "$MUSIC" ]]; then
  "$FFMPEG_BIN" -hide_banner -y -i "$RAW" -stream_loop -1 -i "$MUSIC" \
    -filter_complex "[1:a]volume=0.34,atrim=0:90[aout]" \
    -map 0:v -map "[aout]" -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
    -c:a aac -b:a 128k -ac 1 -t 90 -movflags +faststart "$OUT" \
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
    if dur < 45:
        print(f"FAIL real-play too short ({dur:.1f}s)", file=sys.stderr)
        raise SystemExit(1)
    if pkts > 0 and pkts / max(dur, 1) < 12:
        print(f"FAIL real-play looks static (~{pkts/max(dur,1):.1f} fps packets)", file=sys.stderr)
        raise SystemExit(1)
else:
    print(f"real-play OK {path.name}: {sz} bytes (no ffprobe)")
PY

echo "Wrote $OUT ($(wc -c < "$OUT") bytes)" >&2
exit "$XC_EC"

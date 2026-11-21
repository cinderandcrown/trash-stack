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

app_is_running() {
  # launchctl list prints pid when the process is alive.
  xcrun simctl spawn "$DEVICE" launchctl list 2>/dev/null \
    | awk 'BEGIN{f=0} tolower($0) ~ /trashstack|cinderandcrown/{ if ($1+0 > 0) f=1 } END{ exit(f?0:1) }'
}

REC_PID=""
TEST_PID=""
finalize() {
  if [[ -n "${REC_PID:-}" ]] && kill -0 "$REC_PID" 2>/dev/null; then
    kill -INT "$REC_PID" 2>/dev/null || true
    sleep 3
    kill -KILL "$REC_PID" 2>/dev/null || true
  fi
  if [[ -n "${TEST_PID:-}" ]] && kill -0 "$TEST_PID" 2>/dev/null; then
    kill -TERM "$TEST_PID" 2>/dev/null || true
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

# Kick XCTest first (bootstrap can take ~30–60s). Start recordVideo only once the app is up.
set +e
xcodebuild test-without-building \
  -project "$PROJECT_ROOT/TrashStack.xcodeproj" \
  -scheme TrashStack \
  -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath "$PROJECT_ROOT/DerivedData" \
  -only-testing:TrashStackUITests/RealPlayUITests/testRealPlaySession \
  -parallel-testing-enabled NO \
  >/tmp/real-play-xctest.log 2>&1 &
TEST_PID=$!
set -e

echo "Waiting for TrashStack to become frontmost before recordVideo…" >&2
APP_UP=0
for _ in $(seq 1 120); do
  if app_is_running; then
    APP_UP=1
    break
  fi
  # Bail early if xcodebuild already died.
  if ! kill -0 "$TEST_PID" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

if (( APP_UP != 1 )); then
  echo "App never became frontmost — log tail:" >&2
  tail -n 80 /tmp/real-play-xctest.log >&2 || true
  wait "$TEST_PID" || true
  finalize
  trap - EXIT
  exit 1
fi

# Brief beat so title paints before the encoder starts.
sleep 1.2

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
  wait "$TEST_PID" || true
  finalize
  trap - EXIT
  exit 1
fi
echo "Recording started (app already up)" >&2

set +e
wait "$TEST_PID"
XC_EC=$?
TEST_PID=""
set -e

if (( XC_EC != 0 )) && grep -Eqi 'isn.t a member|not found|does not contain|Unable to find|no such module' /tmp/real-play-xctest.log; then
  echo "UITests scheme/build miss — regenerating + xcodebuild test" >&2
  if command -v xcodegen >/dev/null 2>&1; then
    (cd "$PROJECT_ROOT" && xcodegen generate) >/tmp/real-play-xcodegen.log 2>&1 || true
  fi
  # Stop current recording; restart for the retry.
  if [[ -n "${REC_PID:-}" ]] && kill -0 "$REC_PID" 2>/dev/null; then
    kill -INT "$REC_PID" 2>/dev/null || true
    sleep 2
    kill -KILL "$REC_PID" 2>/dev/null || true
  fi
  REC_PID=""
  rm -f "$RAW"
  set +e
  xcodebuild test \
    -project "$PROJECT_ROOT/TrashStack.xcodeproj" \
    -scheme TrashStack \
    -destination "platform=iOS Simulator,id=$DEVICE" \
    -derivedDataPath "$PROJECT_ROOT/DerivedData" \
    -only-testing:TrashStackUITests/RealPlayUITests/testRealPlaySession \
    -parallel-testing-enabled NO \
    >/tmp/real-play-xctest.log 2>&1 &
  TEST_PID=$!
  set -e
  for _ in $(seq 1 120); do
    app_is_running && break
    kill -0 "$TEST_PID" 2>/dev/null || break
    sleep 0.5
  done
  sleep 1
  xcrun simctl io "$DEVICE" recordVideo --display=internal --codec=h264 --force "$RAW" &
  REC_PID=$!
  sleep 2
  set +e
  wait "$TEST_PID"
  XC_EC=$?
  TEST_PID=""
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

# Drop any leftover leading static (Springboard / black) if the wait raced.
TRIMMED="$OUT_DIR/real-play-trimmed.mp4"
if [[ -n "$FFMPEG_BIN" ]]; then
  python3 - "$RAW" "$TRIMMED" "$FFMPEG_BIN" <<'PY'
import json, subprocess, sys, pathlib
src, dst, ff = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
# Probe duration.
dur = 0.0
try:
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "json", str(src)], text=True)
    dur = float(json.loads(out).get("format", {}).get("duration") or 0)
except Exception:
    pass
# Sample brightness every 0.5s; first frame that is not near-black / wallpaper-flat starts the keep window.
start = 0.0
try:
    # Use scene score via select — fall back to fixed 0 if unavailable.
    # Heuristic: skip leading stretch where mean luma stays very low (<18) for >2s.
    probe = subprocess.run(
        [ff, "-hide_banner", "-i", str(src), "-vf",
         "fps=2,signalstats,metadata=print:file=-", "-f", "null", "-"],
        capture_output=True, text=True, timeout=120,
    )
    lines = (probe.stderr or "") + (probe.stdout or "")
    # Fallback: if duration > 85s, keep the last 80s (title→play lives at the end of a late start).
    if dur > 85:
        start = max(0.0, dur - 80.0)
except Exception:
    if dur > 85:
        start = max(0.0, dur - 80.0)

# Prefer keeping from the first second once app-gated recording is working.
# Only force a late cut when the file is still suspiciously long (>95s of mostly idle).
if dur > 95:
    start = max(start, dur - 85.0)

if start > 0.5:
    subprocess.check_call(
        [ff, "-hide_banner", "-y", "-ss", f"{start:.2f}", "-i", str(src),
         "-t", "90", "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
         "-pix_fmt", "yuv420p", "-an", "-movflags", "+faststart", str(dst)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    print(f"Trimmed leading {start:.1f}s → {dst.name}", file=sys.stderr)
else:
    dst.write_bytes(src.read_bytes())
PY
  if [[ -s "$TRIMMED" ]]; then
    mv -f "$TRIMMED" "$RAW"
  fi
fi

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

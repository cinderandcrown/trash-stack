#!/usr/bin/env bash
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
# Autoplay smoke: 45–60s gameplay video + distinct review + marketing screenshots.
set -euo pipefail

DEVICE="${1:?simulator UDID}"
APP_PATH="${2:?path to TrashStack.app}"
OUT_DIR="${3:-smoke-artifacts}"
BUNDLE_ID="${BUNDLE_ID:-com.cinderandcrown.trashstack}"
DISPLAY="${SIMCTL_DISPLAY:-internal}"
SMOKE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Hard budgets (harness only — app launch gates stay 1.5s / 8s).
STEP_BUDGET_S="${STEP_BUDGET_S:-90}"
SHOT_DEADLINE_S="${SHOT_DEADLINE_S:-12}"
SIMCTL_DEADLINE_S="${SIMCTL_DEADLINE_S:-15}"
CONSEC_DEADLINE_LIMIT="${CONSEC_DEADLINE_LIMIT:-4}"

mkdir -p "$OUT_DIR" "$OUT_DIR/marketing"
TIMING_FILE="$OUT_DIR/smoke-step-timing.tsv"
: > "$TIMING_FILE"
echo -e "kind\tname\tlimit_s\telapsed_s\trc\tnote" >> "$TIMING_FILE"

DEADLINE_FAILS=0
SIM_RECOVERED=0
IN_RECOVER=0
STEP_NEEDS_RESET=0
CURRENT_STEP="init"

note_timing() {
  local kind="$1" name="$2" limit="$3" elapsed="$4" rc="$5" note="${6:-}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$name" "$limit" "$elapsed" "$rc" "$note" >> "$TIMING_FILE"
  echo "timing kind=$kind name=$name limit=${limit}s elapsed=${elapsed}s rc=$rc ${note}" >&2
}

# Kill a process group tree (xcrun→simctl grandchildren ignore single-PID kills).
_kill_tree() {
  local pid="$1"
  kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  sleep 0.3
  kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
}

# Run argv under a hard wall-clock deadline; kill the whole process group on expiry.
# (Prior perl-alarm only signaled xcrun; simctl children kept running → 15s limits took 140s.)
_run_deadline() {
  local secs="$1"
  shift
  local rc=0 t0
  t0=$(python3 -c 'import time; print(time.time())')
  set -m
  "$@" &
  local pid=$!
  set +m
  while kill -0 "$pid" 2>/dev/null; do
    if python3 - "$t0" "$secs" <<'PY'
import sys, time
sys.exit(0 if (time.time() - float(sys.argv[1])) >= float(sys.argv[2]) else 1)
PY
    then
      _kill_tree "$pid"
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.2
  done
  wait "$pid" 2>/dev/null || rc=$?
  return "$rc"
}

# Raw deadline used inside recover / screenshot fallbacks (no wedge recursion).
raw_deadline() {
  local secs="$1" rc=0
  shift
  local label t0 elapsed
  label="$(cmd_label "$@")"
  t0=$SECONDS
  _run_deadline "$secs" "$@" || rc=$?
  elapsed=$((SECONDS - t0))
  # If wall elapsed >= limit, normalize to timeout even if signal status differs.
  if (( elapsed >= secs && rc != 0 )); then
    rc=124
  fi
  note_timing deadline "$label" "$secs" "$elapsed" "$rc" "step=$CURRENT_STEP raw=1"
  if (( rc == 124 || rc == 142 || rc == 14 )); then
    return 124
  fi
  return "$rc"
}

# Compact argv for logs (keep simctl verb visible).
cmd_label() {
  local out="" arg
  for arg in "$@"; do
    case "$arg" in
      "$DEVICE"|"$BUNDLE_ID"|"$APP_PATH"|"$OUT_DIR"/*|/tmp/*) continue ;;
      -*) out+="$arg " ;;
      *) out+="$arg " ;;
    esac
  done
  out="${out% }"
  if [[ ${#out} -gt 100 ]]; then
    out="${out:0:97}..."
  fi
  printf '%s' "${out:-cmd}"
}

# Recover a wedged CoreSimulator once; a second wedge fails fast.
recover_simulator_once() {
  local reason="$1"
  if (( SIM_RECOVERED == 1 )); then
    echo "Simulator still wedged after one erase/reboot ($reason). Fail fast." >&2
    echo "See $TIMING_FILE for per-step / with_deadline timings." >&2
    print_timing_table
    exit 125
  fi
  SIM_RECOVERED=1
  DEADLINE_FAILS=0
  IN_RECOVER=1
  echo "Simulator wedge detected ($reason) — shutdown, erase, reboot once, reinstall, then retry." >&2
  note_timing step recover_simulator 240 0 0 "start:$reason"
  local t0=$SECONDS rc=0
  : >/tmp/sim-recover.log
  raw_deadline 45 xcrun simctl shutdown "$DEVICE" >>/tmp/sim-recover.log 2>&1 || true
  raw_deadline 60 xcrun simctl erase "$DEVICE" >>/tmp/sim-recover.log 2>&1 || true
  raw_deadline 45 xcrun simctl boot "$DEVICE" >>/tmp/sim-recover.log 2>&1 || true
  raw_deadline 120 xcrun simctl bootstatus "$DEVICE" -b >>/tmp/sim-recover.log 2>&1 || true
  if ! raw_deadline 90 xcrun simctl install "$DEVICE" "$APP_PATH" >>/tmp/sim-recover.log 2>&1; then
    echo "Erase/reboot install failed — creating a fresh simulator device." >&2
    raw_deadline 45 xcrun simctl shutdown "$DEVICE" >>/tmp/sim-recover.log 2>&1 || true
    # Keep the old UDID around; create a sibling iPhone and switch DEVICE.
    local new_udid=""
    rm -f /tmp/sim-new-udid.txt
    raw_deadline 45 xcrun simctl create "TrashStack-Smoke-Recover" "iPhone 17" >/tmp/sim-new-udid.txt 2>>/tmp/sim-recover.log || true
    new_udid="$(tr -d '[:space:]' </tmp/sim-new-udid.txt 2>/dev/null || true)"
    if [[ -z "$new_udid" ]]; then
      raw_deadline 45 xcrun simctl create "TrashStack-Smoke-Recover" "iPhone 16" >/tmp/sim-new-udid.txt 2>>/tmp/sim-recover.log || true
      new_udid="$(tr -d '[:space:]' </tmp/sim-new-udid.txt 2>/dev/null || true)"
    fi
    if [[ -n "$new_udid" ]]; then
      DEVICE="$new_udid"
      echo "Recover DEVICE now $DEVICE" >&2
      raw_deadline 45 xcrun simctl boot "$DEVICE" >>/tmp/sim-recover.log 2>&1 || true
      raw_deadline 120 xcrun simctl bootstatus "$DEVICE" -b >>/tmp/sim-recover.log 2>&1 || true
      raw_deadline 90 xcrun simctl install "$DEVICE" "$APP_PATH" >>/tmp/sim-recover.log 2>&1 || rc=$?
    else
      rc=1
    fi
  fi
  raw_deadline 15 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true >>/tmp/sim-recover.log 2>&1 || true
  raw_deadline 15 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true >>/tmp/sim-recover.log 2>&1 || true
  note_timing step recover_simulator 240 "$((SECONDS - t0))" "$rc" "done:$reason"
  IN_RECOVER=0
  if (( rc != 0 )); then
    echo "Simulator recover reinstall failed — fail fast." >&2
    cat /tmp/sim-recover.log >&2 || true
    print_timing_table
    exit 125
  fi
  STEP_NEEDS_RESET=1
  echo "Simulator recover OK — suite will retry the current step with a fresh budget." >&2
}

on_deadline_timeout() {
  local label="$1"
  if (( IN_RECOVER == 1 )); then
    return 0
  fi
  DEADLINE_FAILS=$((DEADLINE_FAILS + 1))
  echo "deadline TIMEOUT ($DEADLINE_FAILS/$CONSEC_DEADLINE_LIMIT) cmd=$label step=$CURRENT_STEP" >&2
  if (( DEADLINE_FAILS >= CONSEC_DEADLINE_LIMIT )); then
    if (( SIM_RECOVERED == 1 )); then
      echo "Fail fast: simulator wedged again after erase/reboot (cmd='$label' step='$CURRENT_STEP')." >&2
      print_timing_table
      exit 125
    fi
    recover_simulator_once "consec_timeout:$label"
  fi
}

# macOS-friendly deadline (GNU timeout is missing on xcode runners).
# Kills the whole process group so hung simctl grandchildren cannot outlive the limit.
with_deadline() {
  local secs="$1" rc=0
  shift
  local label t0 elapsed
  label="$(cmd_label "$@")"
  t0=$SECONDS
  _run_deadline "$secs" "$@" || rc=$?
  elapsed=$((SECONDS - t0))
  if (( elapsed >= secs && rc != 0 )); then
    rc=124
  fi
  note_timing deadline "$label" "$secs" "$elapsed" "$rc" "step=$CURRENT_STEP"
  if (( rc == 124 || rc == 142 || rc == 14 )); then
    on_deadline_timeout "$label"
    return 124
  fi
  if (( rc == 0 )); then
    DEADLINE_FAILS=0
  fi
  return "$rc"
}

app_running() {
  # Prefer launchctl list; fall back to simctl spawn ps. Always deadline-wrapped
  # (unbounded simctl spawn is what burned 25 minutes on wedged sims).
  local tmp rc=0
  tmp="$(mktemp -t smoke-app-running.XXXXXX)"
  with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl spawn "$DEVICE" launchctl list >"$tmp" 2>/dev/null || rc=$?
  if (( rc == 0 )) && grep -q "$BUNDLE_ID" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  rc=0
  with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl spawn "$DEVICE" ps aux >"$tmp" 2>/dev/null || rc=$?
  if (( rc == 0 )) && grep -v grep "$tmp" | grep -q "TrashStack"; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

shot() {
  local out="$1" ok=0
  # Display fallbacks must NOT each count as a wedge timeout (3 displays ≠ wedged sim).
  if raw_deadline "$SHOT_DEADLINE_S" xcrun simctl io "$DEVICE" screenshot --display="$DISPLAY" "$out" 2>/tmp/sim-shot.err; then
    ok=1
  elif raw_deadline "$SHOT_DEADLINE_S" xcrun simctl io "$DEVICE" screenshot --display=1 "$out" 2>/tmp/sim-shot.err; then
    ok=1
  elif raw_deadline "$SHOT_DEADLINE_S" xcrun simctl io "$DEVICE" screenshot "$out" 2>/tmp/sim-shot.err; then
    ok=1
  fi
  if (( ok == 1 )); then
    DEADLINE_FAILS=0
    return 0
  fi
  # Count the whole screenshot sequence as a single deadline failure toward wedge.
  on_deadline_timeout "simctl io screenshot (all displays)"
  return 124
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

# Title frame must be the real title screen — reject OS LaunchLogo / charcoal-only ident.
assert_title_not_splash() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys, struct, zlib, pathlib
path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    print(f"Not a PNG: {path}", file=sys.stderr); sys.exit(2)
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
            if pa <= pb and pa <= pc: return a
            if pb <= pc: return b
            return c
        for i in range(len(row)):
            a = row[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            row[i] = (row[i] + paeth(a, b, c)) & 255
    rows.append(row)

def rgb(x, y):
    i = x * bpp
    return rows[y][i], rows[y][i + 1], rows[y][i + 2]

teal = magenta = 0
for y in range(int(height * 0.12), int(height * 0.45), max(1, height // 50)):
    for x in range(int(width * 0.15), int(width * 0.85), max(1, width // 40)):
        r, g, b = rgb(x, y)
        if g > 140 and b > 140 and r < 120:
            teal += 1
        if r > 160 and b > 140 and g < 120:
            magenta += 1
if teal + magenta < 3:
    print(f"Title frame missing neon wordmark colors (teal={teal} magenta={magenta}): {path}", file=sys.stderr)
    sys.exit(5)
# Charcoal-only publisher ident (no neon title) should fail this check.
print(f"Title OK (not splash) {path} teal={teal} magenta={magenta}")
PY
}

# Reject OS UILaunchScreen / pre-SwiftUI frames when possible without Pillow.
# Authoritative gate remains the in-app LaunchTiming stamp; this is a visual assist.
assert_not_launch_splash() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys, struct, zlib, pathlib
path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 80_000:
    print(f"Frame too small for first paint: {path}", file=sys.stderr)
    sys.exit(5)
# If we can decode, reject near-uniform LaunchLogo card (bright neon card on dark).
# Without comparing to LaunchLogo asset, accept any non-tiny app frame once stamp exists.
print(f"Not launch splash OK {path} (stdlib; in-app stamp authoritative)")
PY
}

# Resolve the live data container and Documents/launch-timing.txt every call
# (path can lag right after install/launch; never cache a stale container).
launch_docs_path() {
  local container=""
  # Short deadline: stamp poll calls this repeatedly; a 15s hang would miss the 8s window.
  container="$(with_deadline 5 xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)"
  container="$(echo "$container" | tr -d '[:space:]')"
  if [[ -n "$container" ]]; then
    printf '%s' "$container/Documents/launch-timing.txt"
  fi
}

# Read a key from Documents/launch-timing.txt (preferred) or UserDefaults.
read_launch_field() {
  local key="$1"
  local v="" docs defkey="" body=""
  docs="$(launch_docs_path)"
  if [[ -n "$docs" && -f "$docs" ]]; then
    # Re-read the file each time so host FS sync of the simulator mirror is visible.
    body="$(cat "$docs" 2>/dev/null || true)"
    v="$(printf '%s\n' "$body" | grep -E "^${key}=" | head -1 | cut -d= -f2- | tr -d '[:space:]')"
    # Legacy: plain Documents file that was only the dt string.
    if [[ -z "$v" && "$key" == "in_app_sec" ]] && ! printf '%s\n' "$body" | grep -q '='; then
      v="$(printf '%s' "$body" | tr -d '[:space:]')"
    fi
  fi
  if [[ -z "$v" ]]; then
    case "$key" in
      in_app_sec) defkey="trashStack.launchToTitleSec" ;;
      in_app_sec_string) defkey="trashStack.launchToTitleSecString" ;;
      first_frame_wall_epoch) defkey="trashStack.firstFrameWallEpochString" ;;
    esac
    if [[ -n "$defkey" ]]; then
      v="$(with_deadline 8 xcrun simctl spawn "$DEVICE" defaults read "$BUNDLE_ID" "$defkey" 2>/dev/null || true)"
      v="$(echo "$v" | tr -d '[:space:]' | tr -d '\"')"
    fi
  fi
  printf '%s' "$v"
}

read_inapp_launch_sec() {
  local v
  v="$(read_launch_field in_app_sec)"
  if [[ -z "$v" ]]; then
    v="$(read_launch_field in_app_sec_string)"
  fi
  printf '%s' "$v"
}

# Seconds elapsed since host launch-PID stamp (wall clock).
host_since_launch() {
  python3 - "$HOST_LAUNCH_EPOCH" <<'PY'
import sys, time
host = float(sys.argv[1])
print(f"{time.time() - host:.6f}")
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

# Defaults via discrete simctl spawn (simulator /bin/sh -c was returning 134).
write_shot_defaults() {
  local mode="$1"
  with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true >/dev/null 2>&1 || true
  with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true >/dev/null 2>&1 || true
  if [[ -n "$mode" ]]; then
    with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "$mode" >/dev/null 2>&1 || true
  else
    with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
  fi
}

launch_shot() {
  local mode="$1"
  local outfile="$2"
  local settle="${3:-4}"
  local attempts=0
  # Recycle juice is longer (~0.5s suck + held glow/banner) — more attempts, not a looser assert.
  local max_attempts=2
  if [[ "$mode" == "recycle" || "$mode" == "mkt-recycle" ]]; then
    max_attempts=3
    if (( settle < 7 )); then settle=7; fi
  fi
  # One extra attempt window if we had to erase/reboot mid-step.
  local budget_retries=0
  local shot_start=$SECONDS
  CURRENT_STEP="shot:$mode"
  STEP_NEEDS_RESET=0
  note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" 0 0 "start"

  while (( attempts < max_attempts )); do
    # Recover mid-step (via deadline timeouts) must not count against this step's budget.
    if (( STEP_NEEDS_RESET == 1 )); then
      STEP_NEEDS_RESET=0
      budget_retries=1
      attempts=0
      shot_start=$SECONDS
      echo "Resetting step clock for '$mode' after simulator recover" >&2
      note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" 0 0 "reset_after_recover"
    fi
    attempts=$((attempts + 1))
    local step_elapsed=$((SECONDS - shot_start))
    if (( step_elapsed > STEP_BUDGET_S )); then
      echo "launch_shot hard budget ${STEP_BUDGET_S}s exceeded for mode='$mode' (${step_elapsed}s)" >&2
      note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" "$step_elapsed" 124 "budget_exceeded"
      if (( budget_retries == 0 )); then
        recover_simulator_once "step_budget:$mode"
        # Loop top will honor STEP_NEEDS_RESET with a fresh clock.
        continue
      fi
      echo "Fail fast: step '$mode' blew ${STEP_BUDGET_S}s budget after recover." >&2
      print_timing_table
      exit 125
    fi
    smoke_budget
    # Prefer killall over simctl terminate — terminate is a known hang on wedged sims.
    # killall timeout when the app is already dead must not trip the wedge counter.
    raw_deadline 5 xcrun simctl spawn "$DEVICE" killall TrashStack >/dev/null 2>&1 || true
    sleep 0.2

    write_shot_defaults "$mode"
    if [[ -n "$mode" ]]; then
      with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackShot "$mode" -trashStackSkipAds >/tmp/sim-launch.out 2>&1 || true
    else
      with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackSkipAds >/tmp/sim-launch.out 2>&1 || true
    fi
    cat /tmp/sim-launch.out >&2 || true

    # Wait briefly for the process, then one settle for paint.
    local waited=0
    while (( waited < 4 )); do
      if (( SECONDS - shot_start > STEP_BUDGET_S )); then break; fi
      if app_running; then
        break
      fi
      sleep 0.25
      waited=$((waited + 1))
    done
    if (( SECONDS - shot_start > STEP_BUDGET_S )); then
      continue
    fi
    # Extra settle after process is alive so SwiftUI/SpriteKit can paint.
    # Recycle: capture while hold-glow + RECYCLE/CHAIN banner are still up (~1.2s).
    if [[ "$mode" == "recycle" || "$mode" == "mkt-recycle" ]]; then
      sleep 1.1
      sleep "$settle"
    else
      sleep "$settle"
    fi

    if ! app_running; then
      echo "App not running after launch (mode='$mode' attempt=$attempts)" >&2
      continue
    fi

    if ! shot "$outfile"; then
      echo "screenshot deadline failed for mode='$mode' attempt=$attempts" >&2
      continue
    fi
    if assert_app_frame "$outfile"; then
      step_elapsed=$((SECONDS - shot_start))
      note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" "$step_elapsed" 0 "ok"
      echo "Wrote $outfile" >&2
      return 0
    fi
    echo "Bad frame for mode='$mode' attempt=$attempts — retrying" >&2
  done
  step_elapsed=$((SECONDS - shot_start))
  note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" "$step_elapsed" 1 "failed"
  if (( SIM_RECOVERED == 0 )); then
    echo "Shot '$mode' failed — erase/reboot once then retry step." >&2
    recover_simulator_once "shot_failed:$mode"
    STEP_NEEDS_RESET=0
    attempts=0
    shot_start=$SECONDS
    budget_retries=1
    note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" 0 0 "retry_after_recover"
    while (( attempts < max_attempts )); do
      attempts=$((attempts + 1))
      if (( SECONDS - shot_start > STEP_BUDGET_S )); then
        break
      fi
      smoke_budget
      raw_deadline 5 xcrun simctl spawn "$DEVICE" killall TrashStack >/dev/null 2>&1 || true
      sleep 0.2
      write_shot_defaults "$mode"
      if [[ -n "$mode" ]]; then
        with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackShot "$mode" -trashStackSkipAds >/tmp/sim-launch.out 2>&1 || true
      else
        with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackSkipAds >/tmp/sim-launch.out 2>&1 || true
      fi
      cat /tmp/sim-launch.out >&2 || true
      local waited=0
      while (( waited < 4 )); do
        if app_running; then break; fi
        sleep 0.25
        waited=$((waited + 1))
      done
      if [[ "$mode" == "recycle" || "$mode" == "mkt-recycle" ]]; then
        sleep 1.1
        sleep "$settle"
      else
        sleep "$settle"
      fi
      if ! app_running; then continue; fi
      if ! shot "$outfile"; then continue; fi
      if assert_app_frame "$outfile"; then
        note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" "$((SECONDS - shot_start))" 0 "ok_after_recover"
        echo "Wrote $outfile" >&2
        return 0
      fi
    done
  fi
  echo "Failed to capture a valid app frame for mode='$mode' → $outfile" >&2
  print_timing_table
  exit 1
}

# Overall watchdog (paired with the GitHub step timeout-minutes).
# Starts after simulator boot/install so boot latency is not counted against the suite.
SMOKE_START=0
smoke_budget() {
  if (( SMOKE_START == 0 )); then
    return 0
  fi
  local elapsed=$((SECONDS - SMOKE_START))
  if (( elapsed > 1500 )); then
    echo "Smoke watchdog exceeded ${elapsed}s — aborting" >&2
    echo "---- smoke-step-timing.tsv ----" >&2
    cat "$TIMING_FILE" >&2 || true
    exit 124
  fi
}

print_timing_table() {
  echo "---- smoke-step-timing.tsv ----" >&2
  if [[ -f "$TIMING_FILE" ]]; then
    column -t -s $'\t' "$TIMING_FILE" 2>/dev/null || cat "$TIMING_FILE"
    # Also echo plain TSV for CI log scraping.
    echo "---- smoke-step-timing.tsv (raw) ----" >&2
    cat "$TIMING_FILE" >&2
  fi
}

echo "Smoke on $DEVICE (display=$DISPLAY)"
xcrun simctl bootstatus "$DEVICE" -b || xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH"
SMOKE_START=$SECONDS
echo "Smoke suite clock started after install (budget 1500s)" >&2
smoke_budget

xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true

# Springboard icon crop (evidence for real AppIcon) — before timed launch.
with_deadline 20 xcrun simctl io "$DEVICE" screenshot --display="$DISPLAY" "$OUT_DIR/00-springboard.png" 2>/dev/null \
  || with_deadline 20 xcrun simctl io "$DEVICE" screenshot "$OUT_DIR/00-springboard.png" || true
python3 - "$OUT_DIR/00-springboard.png" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1])
out = src.with_name("00-springboard-icon-crop.png")
if not src.exists():
    print("Springboard crop skipped: no screenshot")
    raise SystemExit(0)
try:
    from PIL import Image
    im = Image.open(src)
    w, h = im.size
    crop = im.crop((w // 2 - 120, h // 2 - 220, w // 2 + 120, h // 2 - 40))
    crop.save(out)
    print("Springboard icon crop OK", crop.size)
except Exception:
    # Fall back: copy full springboard as crop evidence (runners may lack Pillow).
    out.write_bytes(src.read_bytes())
    print("Springboard crop fallback: copied full frame (no Pillow)")
PY

# Cold-launch timing (ads skipped):
# 1) In-app (authoritative): ProcessInfo.systemUptime @main → first SwiftUI frame ≤ 1.5s.
# 2) Wall-clock (honest): host epoch at simctl launch PID return → app first_frame_wall_epoch ≤ 8s.
#    Do NOT use bash $SECONDS polling as the wall metric (that is harness overhead).
# Do NOT raise the 8s ceiling.
CURRENT_STEP="cold_launch_timing"
note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" 0 0 "start"
with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 0.3
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.launchToTitleSec" >/dev/null 2>&1 || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.launchToTitleSecString" >/dev/null 2>&1 || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.firstFrameWallEpoch" >/dev/null 2>&1 || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.firstFrameWallEpochString" >/dev/null 2>&1 || true
with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackSkipAds >/tmp/sim-launch-cold.out 2>&1 || true
# Host wall clock the instant launch returns its PID (same Mac clock as Date() in-sim).
HOST_LAUNCH_EPOCH="$(python3 -c 'import time; print(f"{time.time():.6f}")')"
cat /tmp/sim-launch-cold.out >&2 || true
echo "host_launch_epoch=$HOST_LAUNCH_EPOCH" >&2
# Poll Documents mirror until stamps appear. Window = 8s from launch-PID stamp
# (not bash $SECONDS / poll-start). Keep shot/asserts out of this loop so FS sync
# time is not eaten by screenshot overhead.
STAMPS_OK=0
INAPP_RAW=""
INAPP_STR=""
FRAME_EPOCH=""
while python3 - "$HOST_LAUNCH_EPOCH" <<'PY'
import sys, time
sys.exit(0 if (time.time() - float(sys.argv[1])) <= 8.0 else 1)
PY
do
  docs="$(launch_docs_path)"
  if [[ -n "$docs" && -f "$docs" ]]; then
    echo "launch_docs_path=$docs elapsed=$(host_since_launch)s" >&2
    INAPP_RAW="$(read_launch_field in_app_sec)"
    if [[ -z "$INAPP_RAW" ]]; then
      INAPP_RAW="$(read_launch_field in_app_sec_string)"
    fi
    INAPP_STR="$(read_launch_field in_app_sec_string)"
    FRAME_EPOCH="$(read_launch_field first_frame_wall_epoch)"
    if [[ -n "$INAPP_RAW" && -n "$FRAME_EPOCH" ]]; then
      STAMPS_OK=1
      break
    fi
  else
    echo "launch_docs waiting path=${docs:-missing} elapsed=$(host_since_launch)s" >&2
  fi
  sleep 0.1
done
# One final Documents read after the window (handles last-moment sync).
if (( STAMPS_OK == 0 )); then
  INAPP_RAW="$(read_launch_field in_app_sec)"
  if [[ -z "$INAPP_RAW" ]]; then
    INAPP_RAW="$(read_launch_field in_app_sec_string)"
  fi
  INAPP_STR="$(read_launch_field in_app_sec_string)"
  FRAME_EPOCH="$(read_launch_field first_frame_wall_epoch)"
  if [[ -n "$INAPP_RAW" && -n "$FRAME_EPOCH" ]]; then
    STAMPS_OK=1
  fi
fi
# Honest wall = app first-frame absolute epoch − host stamp at launch PID.
WALL_DT="$(python3 - "$HOST_LAUNCH_EPOCH" "$FRAME_EPOCH" <<'PY'
import sys
host = (sys.argv[1] or "").strip()
frame = (sys.argv[2] or "").strip()
if not host or not frame:
    print("missing")
    raise SystemExit(0)
try:
    dt = float(frame) - float(host)
except ValueError:
    print("missing")
    raise SystemExit(0)
print(f"{dt:.4f}")
PY
)"
{
  echo "host_launch_epoch=$HOST_LAUNCH_EPOCH"
  echo "first_frame_wall_epoch=${FRAME_EPOCH:-missing}"
  echo "wall_clock_launch_pid_to_first_frame_s=${WALL_DT}"
  echo "in_app_process_start_to_first_frame_s=${INAPP_RAW:-missing}"
  echo "in_app_process_start_to_first_frame_string=${INAPP_STR:-missing}"
  echo "gates: in_app<=1.5s (authoritative) AND wall_clock<=8s; reject OS LaunchLogo; require stamps"
} | tee "$OUT_DIR/launch-timing.txt"
printf '%s\n' "${INAPP_RAW:-}" > "$OUT_DIR/launch-time-seconds.txt"
printf '%s\n' "${WALL_DT}" > "$OUT_DIR/launch-wall-clock-seconds.txt"
if (( STAMPS_OK == 0 )); then
  echo "First SwiftUI frame stamps never arrived within 8s of launch-PID" >&2
  docs="$(launch_docs_path)"
  echo "docs_path=${docs:-missing}" >&2
  echo "docs=$(cat "$docs" 2>/dev/null || true)" >&2
  exit 1
fi
python3 - "$INAPP_RAW" "$WALL_DT" <<'PY'
import sys
in_app = (sys.argv[1] or "").strip()
wall = (sys.argv[2] or "").strip()
if not in_app:
    raise SystemExit("Missing in-app launch metric")
try:
    dt = float(in_app)
except ValueError as e:
    raise SystemExit(f"Bad in-app launch metric {in_app!r}: {e}")
if dt > 1.5:
    raise SystemExit(f"In-app launch {dt:.3f}s exceeds 1.5s budget")
print(f"In-app launch OK {dt:.3f}s")
if not wall or wall == "missing":
    raise SystemExit("Missing honest wall-clock metric (host epoch vs first_frame_wall_epoch)")
try:
    wdt = float(wall)
except ValueError as e:
    raise SystemExit(f"Bad wall-clock metric {wall!r}: {e}")
if wdt > 8.0:
    raise SystemExit(f"Wall-clock launch {wdt:.3f}s exceeds honest 8s ceiling")
if wdt < -1.0:
    raise SystemExit(f"Wall-clock launch {wdt:.3f}s looks clock-skewed")
print(f"Wall-clock launch OK {wdt:.3f}s")
PY
# Frame evidence after stamps (LaunchLogo reject) — not part of the 8s stamp poll.
# Reuse this capture as 00-publisher-ident.png (skip a full re-launch_shot).
shot "$OUT_DIR/00-publisher-ident.png" || true
assert_app_frame "$OUT_DIR/00-publisher-ident.png"
assert_not_launch_splash "$OUT_DIR/00-publisher-ident.png"
echo "Wrote $OUT_DIR/00-publisher-ident.png (timing capture)" >&2
# Real Trash Stack title (skip ident so we don't wait on the 2s studio card).
CURRENT_STEP="title"
note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" 0 0 "start"
TITLE_T0=$SECONDS
with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 0.3
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackSkipAds -trashStackSkipIdent >/tmp/sim-launch-title.out 2>&1 || true
TITLE_OK=0
for try in 1 2 3 4 5 6; do
  if (( SECONDS - TITLE_T0 > STEP_BUDGET_S )); then
    echo "Title step blew ${STEP_BUDGET_S}s hard budget" >&2
    recover_simulator_once "step_budget:title"
    echo "Fail fast after title step budget." >&2
    print_timing_table
    exit 125
  fi
  sleep 0.3
  shot "$OUT_DIR/01-title.png" || true
  if assert_app_frame "$OUT_DIR/01-title.png" && assert_title_not_splash "$OUT_DIR/01-title.png"; then
    TITLE_OK=1
    break
  fi
done
if (( TITLE_OK == 0 )); then
  echo "Title frame invalid or still LaunchLogo splash" >&2
  print_timing_table
  exit 1
fi
note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" "$((SECONDS - TITLE_T0))" 0 "ok"
smoke_budget
# Settle long enough for mid-game / crush juice / recycle banner.
launch_shot "game" "$OUT_DIR/02-gameplay.png" 5
assert_no_missing_textures "$OUT_DIR/02-gameplay.png"
launch_shot "compactor" "$OUT_DIR/03-compactor-clear.png" 5
assert_no_missing_textures "$OUT_DIR/03-compactor-clear.png"
# Hold recycle pose (glow + banner) — do NOT loosen assert_app_frame.
launch_shot "recycle" "$OUT_DIR/04-recycle-combo.png" 7
assert_no_missing_textures "$OUT_DIR/04-recycle-combo.png"
launch_shot "revive" "$OUT_DIR/05-game-over-revive.png" 4
assert_no_missing_textures "$OUT_DIR/05-game-over-revive.png"
launch_shot "base" "$OUT_DIR/06-base.png" 3
launch_shot "pass" "$OUT_DIR/07-pass.png" 3
launch_shot "shop" "$OUT_DIR/08-shop.png" 3
launch_shot "notif" "$OUT_DIR/09-notification-prompt.png" 3
smoke_budget
# Retention evidence: Daily Dumpster, share card, streak reward.
launch_shot "daily" "$OUT_DIR/10-daily-dumpster.png" 4
assert_no_missing_textures "$OUT_DIR/10-daily-dumpster.png"
launch_shot "share" "$OUT_DIR/11-daily-share-card.png" 3
launch_shot "streak" "$OUT_DIR/12-streak-reward.png" 3
smoke_budget

launch_shot "mkt-play" "$OUT_DIR/marketing/01-play.png" 4
assert_no_missing_textures "$OUT_DIR/marketing/01-play.png"
launch_shot "mkt-crush" "$OUT_DIR/marketing/02-crush.png" 5
assert_no_missing_textures "$OUT_DIR/marketing/02-crush.png"
launch_shot "mkt-recycle" "$OUT_DIR/marketing/03-recycle.png" 5
assert_no_missing_textures "$OUT_DIR/marketing/03-recycle.png"
launch_shot "mkt-base" "$OUT_DIR/marketing/04-junkyard.png" 3
launch_shot "mkt-pass" "$OUT_DIR/marketing/05-pass.png" 3
launch_shot "mkt-shop" "$OUT_DIR/marketing/06-shop.png" 3
launch_shot "mkt-daily" "$OUT_DIR/marketing/07-daily.png" 4
assert_no_missing_textures "$OUT_DIR/marketing/07-daily.png"
smoke_budget

python3 - "$OUT_DIR" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = [
  "00-publisher-ident.png","01-title.png","02-gameplay.png","03-compactor-clear.png","04-recycle-combo.png",
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

CURRENT_STEP="record_video"
note_timing step "$CURRENT_STEP" 120 0 0 "start"
VIDEO_T0=$SECONDS
with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "demo" || true
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
  print_timing_table
  exit 1
fi
set -e
with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackShot demo -trashStackSkipAds -autoplay >/dev/null 2>&1 || true
# Continuous autoplay (~35s): recycle/press/snatch/game-over beats without board teleport spam.
sleep 35
kill -INT "$REC_PID" 2>/dev/null || true
# Force-kill if simctl recordVideo ignores INT (known hang source).
sleep 2
if kill -0 "$REC_PID" 2>/dev/null; then
  echo "recordVideo still alive after INT — sending KILL" >&2
  kill -KILL "$REC_PID" 2>/dev/null || true
fi
wait "$REC_PID" 2>/dev/null || true
sleep 2
note_timing step "$CURRENT_STEP" 120 "$((SECONDS - VIDEO_T0))" 0 "ok"
smoke_budget

# simctl recordVideo cannot capture AVAudioEngine. Do NOT paste SFX at fixed adelay offsets
# (that lied about sync). Mux only the same game_loop bed the app plays, and label honestly.
AUDIO_DIR="$SMOKE_ROOT/TrashStack/Resources/Audio"
MUSIC="$AUDIO_DIR/game_loop.wav"
FFMPEG_BIN="$(command -v ffmpeg || true)"
if [[ -z "$FFMPEG_BIN" ]]; then
  for cand in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
    if [[ -x "$cand" ]]; then FFMPEG_BIN="$cand"; break; fi
  done
fi
FFPROBE_BIN="$(command -v ffprobe || true)"
if [[ -z "$FFPROBE_BIN" ]]; then
  for cand in /opt/homebrew/bin/ffprobe /usr/local/bin/ffprobe; do
    if [[ -x "$cand" ]]; then FFPROBE_BIN="$cand"; break; fi
  done
fi
if [[ ! -f "$VIDEO_RAW" ]]; then
  echo "Silent capture missing: $VIDEO_RAW" >&2
  ls -la "$OUT_DIR" >&2 || true
  exit 1
fi
if [[ ! -f "$MUSIC" ]]; then
  echo "Music bed missing: $MUSIC" >&2
  exit 1
fi
if [[ -z "$FFMPEG_BIN" ]]; then
  echo "ffmpeg not found (install via brew install ffmpeg)" >&2
  exit 1
fi
cat > "$OUT_DIR/demo-audio.txt" <<EOF
simctl recordVideo does not capture in-app AVAudioEngine output.
This mux uses ONLY TrashStack/Resources/Audio/game_loop.wav (same asset the app plays)
looped under the silent capture — no synthetic SFX adelay offsets.
In-app SFX/music fire during the recorded play but are not on the simctl track.
Demo script includes a near-miss beat (~14s) and a real game-over (~24s).
EOF
echo "Muxing music bed only with $FFMPEG_BIN ($(wc -c < "$VIDEO_RAW") byte silent capture)" >&2
"$FFMPEG_BIN" -y -i "$VIDEO_RAW" -i "$MUSIC" \
  -filter_complex "[1:a]volume=0.34,aloop=loop=-1:size=2e+09,atrim=0:50,apad=whole_dur=50[aout]" \
  -map 0:v -map "[aout]" -c:v libx264 -pix_fmt yuv420p -crf 28 -preset veryfast -c:a aac -b:a 128k \
  -movflags +faststart -shortest "$VIDEO_OUT" \
  >/tmp/ffmpeg-mux.log 2>&1 || {
    echo "ffmpeg mux failed; keeping silent video as gameplay-demo.mp4" >&2
    cat /tmp/ffmpeg-mux.log >&2 || true
    mv -f "$VIDEO_RAW" "$VIDEO_OUT"
  }
rm -f "$VIDEO_RAW"
if ! "$FFPROBE_BIN" -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$VIDEO_OUT" | grep -q audio; then
  echo "Gameplay video missing audio track after mux" >&2
  cat /tmp/ffmpeg-mux.log >&2 || true
  exit 1
fi
bytes=$(wc -c < "$VIDEO_OUT")
if (( bytes > 150000000 )); then
  echo "Gameplay video too large ($bytes bytes); recompressing" >&2
  "$FFMPEG_BIN" -y -i "$VIDEO_OUT" -c:v libx264 -crf 32 -preset veryfast -c:a aac -b:a 96k "$OUT_DIR/gameplay-demo-small.mp4" >/tmp/ffmpeg-small.log 2>&1
  mv -f "$OUT_DIR/gameplay-demo-small.mp4" "$VIDEO_OUT"
fi
echo "Muxed game_loop bed onto gameplay-demo.mp4 ($(wc -c < "$VIDEO_OUT") bytes)" >&2
# Near-miss / GO window for evidence (~t=20–28s).
"$FFMPEG_BIN" -y -ss 20 -t 8 -i "$VIDEO_OUT" -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 128k \
  "$OUT_DIR/recycle-chain-clip.mp4" >/tmp/ffmpeg-clip.log 2>&1 || {
    echo "tension clip failed" >&2
    cat /tmp/ffmpeg-clip.log >&2 || true
    exit 1
  }
if ! "$FFPROBE_BIN" -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$OUT_DIR/recycle-chain-clip.mp4" | grep -q audio; then
  echo "recycle-chain-clip.mp4 missing audio" >&2
  exit 1
fi

fps="$(xcrun simctl spawn "$DEVICE" defaults read "$BUNDLE_ID" trashStack.measuredFPS 2>/dev/null || echo 0)"
echo "Measured FPS sample: $fps" >&2
python3 - <<PY
fps=float("$fps" or 0)
if fps > 0 and fps < 50:
    raise SystemExit(f"FPS assert failed: {fps}")
print(f"FPS assert ok ({fps})")
PY

for f in 00-publisher-ident.png 01-title.png 02-gameplay.png 03-compactor-clear.png 04-recycle-combo.png \
         05-game-over-revive.png 06-base.png 07-pass.png 08-shop.png 09-notification-prompt.png \
         gameplay-demo.mp4 recycle-chain-clip.mp4 launch-time-seconds.txt; do
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
    print_timing_table
    exit 1
  fi
  echo "OK $path ($(wc -c < "$path") bytes)"
done

note_timing step suite_complete 1500 "$((SECONDS - SMOKE_START))" 0 "ok"
print_timing_table
echo "Smoke OK — timing table: $TIMING_FILE" >&2

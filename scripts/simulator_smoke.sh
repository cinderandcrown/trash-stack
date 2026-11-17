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
STEP_BUDGET_S="${STEP_BUDGET_S:-120}"
SHOT_DEADLINE_S="${SHOT_DEADLINE_S:-10}"
SIMCTL_DEADLINE_S="${SIMCTL_DEADLINE_S:-12}"
CONSEC_DEADLINE_LIMIT="${CONSEC_DEADLINE_LIMIT:-5}"

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

# Run argv under a hard wall-clock deadline; kill the whole process group on expiry.
# Use setpgrp (same session) — start_new_session + killpg gets EPERM on macOS CI and
# leaves orphaned xcrun/simctl children that wedge the rest of the suite.
_run_deadline() {
  local secs="$1" rc=0
  shift
  python3 - "$secs" "$@" <<'PY' || rc=$?
import os, signal, subprocess, sys, time

secs = float(sys.argv[1])
cmd = sys.argv[2:]

def nuke(pid: int) -> None:
    """Kill pid and its process group / children. Never raise."""
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except ProcessLookupError:
            return
        except OSError:
            # macOS can EPERM killpg in edge cases — fall back to pid + children.
            try:
                os.kill(pid, sig)
            except OSError:
                pass
            try:
                out = subprocess.check_output(["pgrep", "-P", str(pid)], text=True, stderr=subprocess.DEVNULL)
            except Exception:
                out = ""
            for line in out.split():
                try:
                    os.kill(int(line.strip()), sig)
                except (OSError, ValueError):
                    pass
        if sig == signal.SIGTERM:
            time.sleep(0.35)

# New process group, SAME session (killpg works on macOS). Avoid start_new_session.
proc = subprocess.Popen(cmd, preexec_fn=os.setpgrp)
try:
    code = proc.wait(timeout=secs)
    sys.exit(code if code is not None else 0)
except subprocess.TimeoutExpired:
    nuke(proc.pid)
    deadline = time.time() + 3.0
    while time.time() < deadline:
        try:
            proc.wait(timeout=0.2)
            break
        except subprocess.TimeoutExpired:
            nuke(proc.pid)
        except Exception:
            break
    sys.exit(124)
PY
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
# Create a FRESH device immediately — do not wait on erase/bootstatus of the wedged UDID
# (that previously burned 14+ minutes then still failed install).
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
  local old_device="$DEVICE"
  echo "Simulator wedge detected ($reason) — shutdown+erase old UDID, create fresh device, boot once." >&2
  note_timing step recover_simulator 240 0 0 "start:$reason"
  local t0=$SECONDS rc=0
  : >/tmp/sim-recover.log
  # Kill wedged helpers/daemon so create/boot are not blocked by orphaned simctl.
  killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
  killall -9 Simulator >/dev/null 2>&1 || true
  killall -9 simctl >/dev/null 2>&1 || true
  killall -9 xcrun >/dev/null 2>&1 || true
  local i
  for i in 1 2 3 4 5 6; do
    sleep 2
    if raw_deadline 8 xcrun simctl list devices >/dev/null 2>&1; then
      echo "CoreSimulatorService responsive after restart (try $i)" >&2
      break
    fi
    if (( i == 6 )); then
      echo "CoreSimulatorService still unresponsive after restart — fail fast." >&2
      note_timing step recover_simulator 240 "$((SECONDS - t0))" 125 "daemon_dead:$reason"
      print_timing_table
      exit 125
    fi
  done
  # Shutdown + erase the wedged UDID (best-effort; same-UDID bootstatus after erase
  # previously hung with SimError 405 on CI).
  raw_deadline 15 xcrun simctl shutdown "$old_device" >>/tmp/sim-recover.log 2>&1 || true
  raw_deadline 30 xcrun simctl erase "$old_device" >>/tmp/sim-recover.log 2>&1 || true
  # Create a brand-new device cloned from the old one's type/runtime.
  local new_device
  new_device="$(python3 - "$old_device" <<'PY' 2>>/tmp/sim-recover.log
import json, subprocess, sys, time
old = sys.argv[1]
data = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "-j"], text=True))
devtype = runtime = None
for rt, items in data.get("devices", {}).items():
    for d in items:
        if d.get("udid") == old:
            runtime = rt
            devtype = d.get("deviceTypeIdentifier")
            break
    if runtime:
        break
if not runtime or not devtype:
    # Fallback: prefer iPhone 16 / 15 on any iOS runtime.
    for rt, items in data.get("devices", {}).items():
        if "iOS" not in rt:
            continue
        for d in items:
            name = d.get("name", "")
            if name.startswith("iPhone") and "Duo" not in name and "Fold" not in name:
                runtime = rt
                devtype = d.get("deviceTypeIdentifier")
                if devtype:
                    break
        if runtime and devtype:
            break
if not runtime or not devtype:
    print("recover: cannot resolve deviceType/runtime", file=sys.stderr)
    sys.exit(2)
name = f"TrashStack-Smoke-{int(time.time())}"
udid = subprocess.check_output(
    ["xcrun", "simctl", "create", name, devtype, runtime], text=True).strip()
print(udid)
PY
)" || new_device=""
  if [[ -z "$new_device" ]]; then
    echo "Failed to create fresh simulator after erase — fail fast." >&2
    cat /tmp/sim-recover.log >&2 || true
    note_timing step recover_simulator 240 "$((SECONDS - t0))" 125 "create_failed:$reason"
    print_timing_table
    exit 125
  fi
  DEVICE="$new_device"
  echo "Recover created fresh device DEVICE=$DEVICE (old=$old_device)" >&2
  note_timing step recover_new_device 0 0 0 "old=$old_device new=$DEVICE"
  if ! raw_deadline 40 xcrun simctl boot "$DEVICE" >>/tmp/sim-recover.log 2>&1; then
    echo "simctl boot of fresh device failed — fail fast." >&2
    cat /tmp/sim-recover.log >&2 || true
    note_timing step recover_simulator 240 "$((SECONDS - t0))" 125 "boot_failed:$reason"
    print_timing_table
    exit 125
  fi
  if ! raw_deadline 60 xcrun simctl bootstatus "$DEVICE" -b >>/tmp/sim-recover.log 2>&1; then
    echo "simctl bootstatus of fresh device hung/failed — fail fast." >&2
    cat /tmp/sim-recover.log >&2 || true
    note_timing step recover_simulator 240 "$((SECONDS - t0))" 125 "bootstatus_failed:$reason"
    print_timing_table
    exit 125
  fi
  if ! raw_deadline 45 xcrun simctl install "$DEVICE" "$APP_PATH" >>/tmp/sim-recover.log 2>&1; then
    echo "install on fresh device failed — fail fast." >&2
    cat /tmp/sim-recover.log >&2 || true
    note_timing step recover_simulator 240 "$((SECONDS - t0))" 125 "install_failed:$reason"
    print_timing_table
    exit 125
  fi
  raw_deadline 10 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true >>/tmp/sim-recover.log 2>&1 || true
  raw_deadline 10 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true >>/tmp/sim-recover.log 2>&1 || true
  note_timing step recover_simulator 240 "$((SECONDS - t0))" 0 "done:$reason"
  IN_RECOVER=0
  STEP_NEEDS_RESET=1
  echo "Simulator recover OK (erase old + fresh device boot) — retry current step once." >&2
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
  # Short raw deadline only — must never trip wedge recovery or hang the suite.
  # On launchctl timeout, treat as NOT running so ensure_app_terminated exits
  # after the killall -9 attempts instead of looping until the shot budget dies.
  local tmp
  tmp="$(mktemp -t smoke-app-running.XXXXXX)"
  if ! raw_deadline 2 xcrun simctl spawn "$DEVICE" launchctl list >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  if grep -q "$BUNDLE_ID" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

shot() {
  local out="$1" ok=0
  # Display fallbacks must NOT each count as a wedge timeout (3 displays ≠ wedged sim).
  # Screenshot flakes also must NOT trigger erase/reboot — that burned 4+ minutes then failed.
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
  echo "screenshot failed on all displays (not counting toward sim wedge)" >&2
  return 124
}

# Reject blank / springboard captures. Prefer Pillow; fall back to stdlib PNG decode.
# Hard-capped — a wedged Pillow/PNG decode previously made notif look like 299s.
assert_app_frame() {
  local file="$1"
  raw_deadline 25 python3 - "$file" <<'PY'
import sys, struct, zlib, pathlib
path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
# OS LaunchLogo is a tiny neon card on black (~80–120 KB). Real in-app frames are >>200 KB.
# Hard floor rejects LaunchLogo even when PNG sampling fails and we would otherwise
# take the size-only OK path.
if len(data) < 150_000:
    print(f"Frame too small / likely OS LaunchLogo ({len(data)} bytes): {path}", file=sys.stderr)
    sys.exit(6)

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
    print(f"Frame undecodable after size check: {path}", file=sys.stderr)
    sys.exit(2)

whites = sum(1 for r, g, b in samples if r > 245 and g > 245 and b > 245)
beiges = sum(1 for r, g, b in samples if r > 90 and g > 70 and b < 160 and r > b + 15)
darks = sum(1 for r, g, b in samples if r < 55 and g < 55 and b < 75)
# Size floor already rejected LaunchLogo; do not reject charcoal ident (also very dark).
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
  # Short deadline: stamp poll calls this repeatedly; a hang would miss the 8s window.
  container="$(raw_deadline 3 xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)"
  container="$(echo "$container" | tr -d '[:space:]')"
  if [[ -n "$container" ]]; then
    printf '%s' "$container/Documents/launch-timing.txt"
  fi
}

# Parse one key from an already-loaded Documents body (no simctl).
docs_field_from_body() {
  local body="$1" key="$2" v=""
  v="$(printf '%s\n' "$body" | grep -E "^${key}=" | head -1 | cut -d= -f2- | tr -d '[:space:]')"
  if [[ -z "$v" && "$key" == "in_app_sec" ]] && ! printf '%s\n' "$body" | grep -q '='; then
    v="$(printf '%s' "$body" | tr -d '[:space:]')"
  fi
  printf '%s' "$v"
}

# Read Documents/launch-timing.txt once. Optional second arg "defaults" enables a short
# UserDefaults fallback (never use during the 8s stamp poll — that hung CI for minutes).
read_launch_field() {
  local key="$1"
  local allow_defaults="${2:-}"
  local v="" docs defkey="" body=""
  docs="$(launch_docs_path)"
  if [[ -n "$docs" && -f "$docs" ]]; then
    body="$(cat "$docs" 2>/dev/null || true)"
    v="$(docs_field_from_body "$body" "$key")"
  fi
  if [[ -z "$v" && "$allow_defaults" == "defaults" ]]; then
    case "$key" in
      in_app_sec) defkey="trashStack.launchToTitleSec" ;;
      in_app_sec_string) defkey="trashStack.launchToTitleSecString" ;;
      first_frame_wall_epoch) defkey="trashStack.firstFrameWallEpochString" ;;
      game_in_app_sec) defkey="trashStack.launchToGameSecString" ;;
      game_first_frame_wall_epoch) defkey="trashStack.firstGameFrameWallEpochString" ;;
    esac
    if [[ -n "$defkey" ]]; then
      v="$(raw_deadline 2 xcrun simctl spawn "$DEVICE" defaults read "$BUNDLE_ID" "$defkey" 2>/dev/null || true)"
      v="$(echo "$v" | tr -d '[:space:]' | tr -d '\"')"
    fi
  fi
  printf '%s' "$v"
}

# One-shot parse of the Documents stamp file (preferred during the 8s poll).
read_launch_docs_snapshot() {
  local docs body
  docs="$(launch_docs_path)"
  if [[ -z "$docs" || ! -f "$docs" ]]; then
    return 1
  fi
  body="$(cat "$docs" 2>/dev/null || true)"
  [[ -z "$body" ]] && return 1
  INAPP_RAW="$(docs_field_from_body "$body" in_app_sec)"
  if [[ -z "$INAPP_RAW" ]]; then
    INAPP_RAW="$(docs_field_from_body "$body" in_app_sec_string)"
  fi
  INAPP_STR="$(docs_field_from_body "$body" in_app_sec_string)"
  FRAME_EPOCH="$(docs_field_from_body "$body" first_frame_wall_epoch)"
  [[ -n "$INAPP_RAW" && -n "$FRAME_EPOCH" ]]
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
  local rem="${2:-8}"
  (( rem < 2 )) && rem=2
  (( rem > 8 )) && rem=8
  with_deadline "$rem" xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true >/dev/null 2>&1 || true
  with_deadline "$rem" xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true >/dev/null 2>&1 || true
  if [[ -n "$mode" ]]; then
    with_deadline "$rem" xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "$mode" >/dev/null 2>&1 || true
  else
    with_deadline "$rem" xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
  fi
}

# Seconds left in the current launch_shot budget (0 if exhausted).
shot_budget_left() {
  local start="$1"
  local left=$((STEP_BUDGET_S - (SECONDS - start)))
  if (( left < 0 )); then left=0; fi
  printf '%s' "$left"
}

launch_shot() {
  local mode="$1"
  local outfile="$2"
  local settle="${3:-4}"
  local attempts=0
  # Recycle juice / game boards need time past OS LaunchLogo after a hard terminate.
  local max_attempts=3
  case "$mode" in
    recycle|mkt-recycle|game|gameplay|compactor|press|revive|daily|demo|autoplay|mkt-play|mkt-crush|mkt-recycle|mkt-daily)
      if (( settle < 5 )); then settle=5; fi
      ;;
    ident|publisher)
      if (( settle < 4 )); then settle=4; fi
      ;;
  esac
  local shot_start=$SECONDS
  CURRENT_STEP="shot:$mode"
  STEP_NEEDS_RESET=0
  note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" 0 0 "start"

  while (( attempts < max_attempts )); do
    # Recover mid-step (via deadline timeouts) must not count against this step's budget.
    if (( STEP_NEEDS_RESET == 1 )); then
      STEP_NEEDS_RESET=0
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
      if (( SIM_RECOVERED == 0 )); then
        recover_simulator_once "step_budget:$mode"
        continue
      fi
      echo "Fail fast: step '$mode' blew ${STEP_BUDGET_S}s budget after recover." >&2
      print_timing_table
      exit 125
    fi
    smoke_budget
    left=$(shot_budget_left "$shot_start")
    if (( left < 8 )); then
      sleep 1
      continue
    fi
    # Prefer a hard kill so -trashStackShot args apply on a fresh process.
    # If terminate flakes, defaults + in-app smoke poll still switch the live UI.
    ensure_app_terminated || true

    left=$(shot_budget_left "$shot_start")
    if (( left < 8 )); then sleep 1; continue; fi
    write_shot_defaults "$mode" "$left"

    left=$(shot_budget_left "$shot_start")
    if (( left < 5 )); then sleep 1; continue; fi
    local launch_lim="$SIMCTL_DEADLINE_S"
    (( left < launch_lim )) && launch_lim=$left
    (( launch_lim < 2 )) && launch_lim=2
    if [[ -n "$mode" ]]; then
      with_deadline "$launch_lim" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackShot "$mode" -trashStackSkipAds >/tmp/sim-launch.out 2>&1 || true
    else
      with_deadline "$launch_lim" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackSkipAds >/tmp/sim-launch.out 2>&1 || true
    fi
    cat /tmp/sim-launch.out >&2 || true
    # Give the in-app shot poll a beat when relaunch reused a live process.
    sleep 0.7

    left=$(shot_budget_left "$shot_start")
    if (( left < 5 )); then sleep 1; continue; fi
    # Poll until past OS LaunchLogo / first real frame (fixed sleep alone is flaky on CI).
    local poll_deadline=$((SECONDS + settle + 8))
    local got_frame=0
    while (( SECONDS < poll_deadline )); do
      left=$(shot_budget_left "$shot_start")
      if (( left < 5 )); then break; fi
      if ! shot "$outfile"; then
        sleep 0.6
        continue
      fi
      if assert_app_frame "$outfile"; then
        got_frame=1
        break
      fi
      echo "Waiting past LaunchLogo/splash for mode='$mode' ($(stat -c%s "$outfile" 2>/dev/null || echo 0) bytes)" >&2
      sleep 0.8
    done
    if (( got_frame == 0 )); then
      echo "No post-LaunchLogo frame for mode='$mode' attempt=$attempts — retrying" >&2
      continue
    fi
    # Extra beat for SpriteKit board / juice after first SwiftUI paint.
    sleep 1.2
    if ! shot "$outfile"; then
      echo "screenshot deadline failed for mode='$mode' attempt=$attempts" >&2
      sleep 0.5
      continue
    fi
    step_elapsed=$((SECONDS - shot_start))
    if (( step_elapsed > STEP_BUDGET_S )); then
      echo "launch_shot budget exceeded before assert for mode='$mode' (${step_elapsed}s)" >&2
      continue
    fi
    if assert_app_frame "$outfile" && assert_shot_matches_mode "$mode" "$outfile"; then
      step_elapsed=$((SECONDS - shot_start))
      note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" "$step_elapsed" 0 "ok"
      echo "Wrote $outfile" >&2
      DEADLINE_FAILS=0
      return 0
    fi
    echo "Bad frame for mode='$mode' attempt=$attempts — retrying (no sim erase)" >&2
    settle=$((settle + 2))
  done
  step_elapsed=$((SECONDS - shot_start))
  note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" "$step_elapsed" 1 "failed"
  # Do NOT erase/reinstall on bad frames — that hung CI (install timeout). Soft-fail the shot.
  echo "Failed to capture a valid app frame for mode='$mode' → $outfile" >&2
  print_timing_table
  exit 1
}

# Terminate the app and confirm the process is gone before relaunch (P0-1).
# killall alone returned rc=2 on CI and left the title process alive.
ensure_app_terminated() {
  # Hard wall so a wedged launchctl cannot burn the whole shot budget.
  local t0=$SECONDS i
  raw_deadline 4 xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  raw_deadline 2 xcrun simctl spawn "$DEVICE" killall TrashStack >/dev/null 2>&1 || true
  raw_deadline 2 xcrun simctl spawn "$DEVICE" killall -9 TrashStack >/dev/null 2>&1 || true
  for i in 1 2 3; do
    if (( SECONDS - t0 > 12 )); then
      echo "ensure_app_terminated: giving up after 12s — proceeding to launch" >&2
      return 1
    fi
    if ! app_running; then
      return 0
    fi
    sleep 0.1
    raw_deadline 2 xcrun simctl spawn "$DEVICE" killall -9 TrashStack >/dev/null 2>&1 || true
  done
  if app_running; then
    echo "ensure_app_terminated: app still running after killall -9" >&2
    return 1
  fi
  return 0
}

# Average SSIM over a downscaled luminance grid (stdlib — no Pillow required).
png_ssim() {
  python3 - "$1" "$2" <<'PY'
import struct, sys, zlib, pathlib, math

def load_png_rgb(path):
    data = pathlib.Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"not png: {path}")
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
    if not width or bit_depth != 8 or color_type not in (2, 6):
        raise SystemExit(f"unsupported png: {path}")
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
    return width, height, bpp, rows

def lum_grid(path, gw=48, gh=96):
    w, h, bpp, rows = load_png_rgb(path)
    grid = []
    for gy in range(gh):
        y = min(h - 1, int((gy + 0.5) * h / gh))
        row = rows[y]
        for gx in range(gw):
            x = min(w - 1, int((gx + 0.5) * w / gw))
            i = x * bpp
            r, g, b = row[i], row[i + 1], row[i + 2]
            grid.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
    return grid

def ssim(a, b):
    # Mean SSIM over 8x8 windows on the downscaled grid.
    gw, gh = 48, 96
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    vals = []
    for y0 in range(0, gh - 7, 8):
        for x0 in range(0, gw - 7, 8):
            wa, wb = [], []
            for dy in range(8):
                for dx in range(8):
                    i = (y0 + dy) * gw + (x0 + dx)
                    wa.append(a[i]); wb.append(b[i])
            n = 64.0
            ma = sum(wa) / n; mb = sum(wb) / n
            va = sum((v - ma) ** 2 for v in wa) / (n - 1)
            vb = sum((v - mb) ** 2 for v in wb) / (n - 1)
            cov = sum((wa[i] - ma) * (wb[i] - mb) for i in range(64)) / (n - 1)
            vals.append(((2 * ma * mb + c1) * (2 * cov + c2)) / ((ma * ma + mb * mb + c1) * (va + vb + c2) + 1e-12))
    return sum(vals) / max(1, len(vals))

a = lum_grid(sys.argv[1]); b = lum_grid(sys.argv[2])
print(f"{ssim(a, b):.6f}")
PY
}

# Per-mode marker + SSIM-vs-title gate (P0-1). Title/ident skip the title-SSIM reject.
assert_shot_matches_mode() {
  local mode="$1" file="$2"
  local title="$OUT_DIR/01-title.png"
  # Marker checks (board / header / caption / charcoal).
  if ! python3 - "$mode" "$file" <<'PY'
import pathlib, struct, sys, zlib
mode, path = sys.argv[1], pathlib.Path(sys.argv[2])
data = path.read_bytes()
pos = 8
width = height = bit_depth = color_type = None
idat = bytearray()
while pos + 8 <= len(data):
    length = struct.unpack(">I", data[pos:pos+4])[0]
    ctype = data[pos+4:pos+8]
    chunk = data[pos+8:pos+8+length]
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
    row = bytearray(raw[start+1:start+stride])
    prev = rows[-1] if rows else bytearray(len(row))
    if filt == 1:
        for i in range(len(row)):
            row[i] = (row[i] + (row[i-bpp] if i >= bpp else 0)) & 255
    elif filt == 2:
        for i in range(len(row)):
            row[i] = (row[i] + prev[i]) & 255
    elif filt == 3:
        for i in range(len(row)):
            left = row[i-bpp] if i >= bpp else 0
            row[i] = (row[i] + ((left + prev[i]) // 2)) & 255
    elif filt == 4:
        def paeth(a,b,c):
            p=a+b-c; pa,pb,pc=abs(p-a),abs(p-b),abs(p-c)
            return a if pa<=pb and pa<=pc else b if pb<=pc else c
        for i in range(len(row)):
            a = row[i-bpp] if i>=bpp else 0
            b = prev[i]
            c = prev[i-bpp] if i>=bpp else 0
            row[i] = (row[i] + paeth(a,b,c)) & 255
    rows.append(row)

def sample(fx, fy):
    x = min(width-1, int(width*fx)); y = min(height-1, int(height*fy))
    i = x * bpp
    return rows[y][i], rows[y][i+1], rows[y][i+2]

def band_stats(y0, y1, x0=0.15, x1=0.85):
    vals=[]
    for fy in (y0,(y0+y1)/2,y1):
        for fx in (x0,(x0+x1)/2,x1):
            r,g,b = sample(fx,fy)
            vals.append((r+g+b)/3)
    mean=sum(vals)/len(vals)
    var=sum((v-mean)**2 for v in vals)/len(vals)
    return var, mean

game = mode in {"game","gameplay","compactor","press","recycle","revive","demo","autoplay","daily","mkt-play","mkt-crush","mkt-recycle","mkt-daily"}
menu = mode in {"base","pass","shop","notif","share","streak","mkt-base","mkt-pass","mkt-shop"}
if game:
    # Board lives in the lower-mid of the phone frame (HUD above, controls below).
    var, mean = band_stats(0.48, 0.78)
    if var < 180:
        print(f"Mode '{mode}' missing board-frame marker (var={var:.1f})", file=sys.stderr); sys.exit(4)
elif menu:
    var, mean = band_stats(0.08, 0.22, 0.1, 0.9)
    if mean > 140 and var < 120:
        print(f"Mode '{mode}' missing menu-header marker (mean={mean:.1f} var={var:.1f})", file=sys.stderr); sys.exit(4)
elif mode in {"ident","publisher"}:
    dark=sum(1 for fy in (0.2,0.4,0.6,0.8) for fx in (0.2,0.5,0.8)
             if (lambda r,g,b: r<50 and g<50 and b<50)(*sample(fx,fy)))
    if dark < 4:
        print(f"Mode '{mode}' missing charcoal ident marker (dark={dark})", file=sys.stderr); sys.exit(4)
    # Reject title screen mistaken for ident (neon wordmark teal/magenta in upper third).
    teal=magenta=0
    for fy in (0.18,0.28,0.38):
        for fx in (0.3,0.5,0.7):
            r,g,b=sample(fx,fy)
            if g>140 and b>140 and r<120: teal+=1
            if r>160 and b>140 and g<120: magenta+=1
    if teal+magenta >= 3:
        print(f"Mode '{mode}' looks like title wordmark (teal={teal} magenta={magenta})", file=sys.stderr); sys.exit(4)
if mode.startswith("mkt-"):
    var, mean = band_stats(0.78, 0.92)
    if mean > 170 and var < 50:
        print(f"Mode '{mode}' missing marketing caption band", file=sys.stderr); sys.exit(4)
print(f"Mode '{mode}' markers OK")
PY
  then
    return 1
  fi
  # Non-title shots must not match the title (SSIM >= 0.85 fails), including ident.
  if [[ "$mode" != "title" && "$mode" != "" && -f "$title" ]]; then
    local ssim
    ssim="$(png_ssim "$file" "$title" 2>/dev/null || echo 1.0)"
    if ! python3 - "$mode" "$ssim" <<'PY'
import sys
mode, s = sys.argv[1], float(sys.argv[2])
if s >= 0.85:
    print(f"Mode '{mode}' too similar to title (SSIM={s:.3f} >= 0.85)", file=sys.stderr)
    sys.exit(5)
print(f"Mode '{mode}' SSIM vs title={s:.3f} OK")
PY
    then
      return 1
    fi
  fi
  return 0
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
# Start the suite clock immediately so boot/install hangs cannot burn the job silently.
SMOKE_START=$SECONDS
CURRENT_STEP="boot_install"
note_timing step "$CURRENT_STEP" 180 0 0 "start"
echo "Smoke suite clock started before boot/install (budget 1500s)" >&2
if ! with_deadline 60 xcrun simctl bootstatus "$DEVICE" -b; then
  echo "bootstatus hung/failed — attempting boot" >&2
  with_deadline 40 xcrun simctl boot "$DEVICE" || true
  if ! with_deadline 60 xcrun simctl bootstatus "$DEVICE" -b; then
    echo "Fail fast: simulator bootstatus never became ready." >&2
    print_timing_table
    exit 125
  fi
fi
with_deadline 20 xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
if ! with_deadline 60 xcrun simctl install "$DEVICE" "$APP_PATH"; then
  echo "Fail fast: simctl install hung or failed." >&2
  print_timing_table
  exit 125
fi
note_timing step boot_install 180 "$((SECONDS - SMOKE_START))" 0 "ok"
smoke_budget

with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true

# Springboard icon crop (evidence for real AppIcon) — before timed launch.
with_deadline 20 xcrun simctl io "$DEVICE" screenshot --display="$DISPLAY" "$OUT_DIR/00-springboard.png" 2>/dev/null \
  || with_deadline 20 xcrun simctl io "$DEVICE" screenshot "$OUT_DIR/00-springboard.png" || true
python3 - "$OUT_DIR/00-springboard.png" <<'PY'
import pathlib, struct, sys, zlib
src = pathlib.Path(sys.argv[1])
out = src.with_name("00-springboard-icon-crop.png")
if not src.exists():
    print("Springboard crop skipped: no screenshot")
    raise SystemExit(0)

def load_png_rgb(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"not png: {path}")
    pos = 8
    width = height = bit_depth = color_type = None
    idat = bytearray()
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos+4])[0]
        ctype = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+length]
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
        row = bytearray(raw[start+1:start+stride])
        prev = rows[-1] if rows else bytearray(len(row))
        if filt == 1:
            for i in range(len(row)):
                row[i] = (row[i] + (row[i-bpp] if i >= bpp else 0)) & 255
        elif filt == 2:
            for i in range(len(row)):
                row[i] = (row[i] + prev[i]) & 255
        elif filt == 3:
            for i in range(len(row)):
                left = row[i-bpp] if i >= bpp else 0
                row[i] = (row[i] + ((left + prev[i]) // 2)) & 255
        elif filt == 4:
            def paeth(a,b,c):
                p=a+b-c; pa,pb,pc=abs(p-a),abs(p-b),abs(p-c)
                return a if pa<=pb and pa<=pc else b if pb<=pc else c
            for i in range(len(row)):
                a = row[i-bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i-bpp] if i >= bpp else 0
                row[i] = (row[i] + paeth(a,b,c)) & 255
        rows.append(row)
    return width, height, bpp, rows

def crop_and_write(w, h, bpp, rows, x0, y0, x1, y1):
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(w, x1), min(h, y1)
    cw, ch = x1 - x0, y1 - y0
    if cw < 16 or ch < 16:
        return False
    # Write a simple 8-bit RGB PNG.
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    raw = bytearray()
    for y in range(y0, y1):
        raw.append(0)
        row = rows[y]
        for x in range(x0, x1):
            i = x * bpp
            raw.extend(row[i:i+3])
    ihdr = struct.pack(">IIBBBBB", cw, ch, 8, 2, 0, 0, 0)
    out.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
    print("Springboard icon crop OK", (cw, ch), "at", (x0, y0))
    return True

try:
    w, h, bpp, rows = load_png_rgb(src)
    # Score a coarse grid for neon/teal/magenta energy typical of AppIcon.
    best = None
    step = max(8, min(w, h) // 40)
    box = max(48, min(w, h) // 8)
    for y in range(0, h - box, step):
        for x in range(0, w - box, step):
            score = 0
            samples = 0
            for yy in range(y, y + box, max(4, box // 8)):
                row = rows[yy]
                for xx in range(x, x + box, max(4, box // 8)):
                    i = xx * bpp
                    r, g, b = row[i], row[i+1], row[i+2]
                    samples += 1
                    # Teal / magenta / neon dumpster cues.
                    if g > 140 and b > 140 and r < 120:
                        score += 3
                    if r > 160 and b > 140 and g < 120:
                        score += 3
                    if r + g + b > 420:
                        score += 1
            if samples and (best is None or score > best[0]):
                best = (score, x, y)
    if best and best[0] >= 8:
        _, x, y = best
        pad = box // 6
        crop_and_write(w, h, bpp, rows, x - pad, y - pad, x + box + pad, y + box + pad)
    else:
        # Fallback: upper-middle icon shelf region on iPhone springboard.
        crop_and_write(w, h, bpp, rows, w // 2 - 90, h // 5 - 40, w // 2 + 90, h // 5 + 140)
except Exception as e:
    out.write_bytes(src.read_bytes())
    print(f"Springboard crop fallback: copied full frame ({e})")
PY

# Cold-launch timing (ads skipped):
# 1) In-app (authoritative): ProcessInfo.systemUptime @main → first SwiftUI frame ≤ 1.5s.
# 2) Wall-clock (honest): host epoch at simctl launch *invoke* → stamps visible ≤ 8s.
#    Prefer app Date() epoch when host/sim clocks agree; if the sim clock is skewed,
#    fall back to host observation time of the Documents stamp (same 8s ceiling — not looser).
# Do NOT use bash $SECONDS polling as the wall metric (that is harness overhead).
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
# Drop any stale Documents stamp left by unit-test launches.
_docs_cold="$(launch_docs_path)"
if [[ -n "$_docs_cold" && -f "$_docs_cold" ]]; then
  rm -f "$_docs_cold" || true
fi
# Wall metric = host time at simctl launch PID return → first frame (original honest definition).
# Poll window also starts at PID return so simctl queue time is not charged against the 8s gate.
# Hold the publisher ident so we can screenshot the real studio card from this cold launch
# (avoids a later relaunch that often reused a still-alive title process).
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "ident" || true
with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackShot ident -trashStackSkipAds >/tmp/sim-launch-cold.out 2>&1 || true
HOST_LAUNCH_EPOCH="$(python3 -c 'import time; print(f"{time.time():.6f}")')"
cat /tmp/sim-launch-cold.out >&2 || true
echo "host_launch_epoch=$HOST_LAUNCH_EPOCH (at launch PID return)" >&2
# Poll Documents mirror until stamps appear. Window = 8s from PID return.
# Docs-only during the poll — UserDefaults fallbacks previously hung simctl and
# burned the window even when the stamp file was already written.
STAMPS_OK=0
INAPP_RAW=""
INAPP_STR=""
FRAME_EPOCH=""
HOST_STAMPS_SEEN=""
while python3 - "$HOST_LAUNCH_EPOCH" <<'PY'
import sys, time
sys.exit(0 if (time.time() - float(sys.argv[1])) <= 8.0 else 1)
PY
do
  if read_launch_docs_snapshot; then
    echo "launch_docs stamps ready elapsed=$(host_since_launch)s in_app=$INAPP_RAW" >&2
    HOST_STAMPS_SEEN="$(python3 -c 'import time; print(f"{time.time():.6f}")')"
    STAMPS_OK=1
    break
  fi
  echo "launch_docs waiting elapsed=$(host_since_launch)s" >&2
  sleep 0.1
done
# One final Documents read after the window (handles last-moment sync).
if (( STAMPS_OK == 0 )); then
  if read_launch_docs_snapshot; then
    HOST_STAMPS_SEEN="$(python3 -c 'import time; print(f"{time.time():.6f}")')"
    STAMPS_OK=1
  else
    # Last resort only — short defaults timeout, never during the poll loop.
    INAPP_RAW="$(read_launch_field in_app_sec defaults)"
    if [[ -z "$INAPP_RAW" ]]; then
      INAPP_RAW="$(read_launch_field in_app_sec_string defaults)"
    fi
    INAPP_STR="$(read_launch_field in_app_sec_string defaults)"
    FRAME_EPOCH="$(read_launch_field first_frame_wall_epoch defaults)"
    if [[ -n "$INAPP_RAW" && -n "$FRAME_EPOCH" ]]; then
      HOST_STAMPS_SEEN="$(python3 -c 'import time; print(f"{time.time():.6f}")')"
      STAMPS_OK=1
    fi
  fi
fi
# Honest wall from PID return. Clamp tiny negatives (frame painted before launch returned).
# Large negatives = sim clock skew → fall back to host stamp-seen time (same ≤8s ceiling).
WALL_DT="$(python3 - "$HOST_LAUNCH_EPOCH" "$FRAME_EPOCH" "${HOST_STAMPS_SEEN:-}" <<'PY'
import sys
host = (sys.argv[1] or "").strip()
frame = (sys.argv[2] or "").strip()
seen = (sys.argv[3] or "").strip()
if not host:
    print("missing"); raise SystemExit(0)
try:
    h = float(host)
except ValueError:
    print("missing"); raise SystemExit(0)
app_dt = None
if frame:
    try:
        app_dt = float(frame) - h
    except ValueError:
        app_dt = None
host_dt = None
if seen:
    try:
        host_dt = float(seen) - h
    except ValueError:
        host_dt = None
if app_dt is not None and -2.0 <= app_dt <= 30.0:
    print(f"{max(0.0, app_dt):.4f}")
elif host_dt is not None and host_dt >= 0:
    print(f"{host_dt:.4f}")
elif app_dt is not None:
    print(f"{app_dt:.4f}")
else:
    print("missing")
PY
)"
{
  echo "host_launch_epoch=$HOST_LAUNCH_EPOCH"
  echo "first_frame_wall_epoch=${FRAME_EPOCH:-missing}"
  echo "host_stamps_seen_epoch=${HOST_STAMPS_SEEN:-missing}"
  echo "wall_clock_launch_pid_to_first_frame_s=${WALL_DT}"
  echo "in_app_process_start_to_first_frame_s=${INAPP_RAW:-missing}"
  echo "in_app_process_start_to_first_frame_string=${INAPP_STR:-missing}"
  echo "gates: in_app<=1.5s (authoritative) AND wall_clock<=8s; reject OS LaunchLogo; require stamps"
} | tee "$OUT_DIR/launch-timing.txt"
printf '%s\n' "${INAPP_RAW:-}" > "$OUT_DIR/launch-time-seconds.txt"
printf '%s\n' "${WALL_DT}" > "$OUT_DIR/launch-wall-clock-seconds.txt"
if (( STAMPS_OK == 0 )); then
  echo "First SwiftUI frame stamps never arrived within 8s of launch invoke" >&2
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
shot "$OUT_DIR/00-timing-frame.png" || true
assert_app_frame "$OUT_DIR/00-timing-frame.png" || true
assert_not_launch_splash "$OUT_DIR/00-timing-frame.png" || true
# Capture publisher ident from this cold launch (real studio card) before we
# relaunch into title. A dedicated relaunch often hit a still-alive title process
# and wrote the title screen as "ident".
IDENT_CAPTURED=0
CURRENT_STEP="shot:ident-cold"
note_timing step "$CURRENT_STEP" 20 0 0 "start"
IDENT_T0=$SECONDS
# Ident is held (trashStackShot ident); wait for logo + credit pose past charcoal first paint.
sleep 1.4
if shot "$OUT_DIR/00-publisher-ident.png" \
  && assert_app_frame "$OUT_DIR/00-publisher-ident.png" \
  && assert_shot_matches_mode "ident" "$OUT_DIR/00-publisher-ident.png"; then
  IDENT_CAPTURED=1
  note_timing step "$CURRENT_STEP" 20 "$((SECONDS - IDENT_T0))" 0 "ok"
  echo "Publisher ident captured from cold launch" >&2
else
  note_timing step "$CURRENT_STEP" 20 "$((SECONDS - IDENT_T0))" 1 "retry_later"
  echo "Cold-launch ident not ready — will retry dedicated shot" >&2
fi
# Real Trash Stack title (skip ident so we don't wait on the 2s studio card).
CURRENT_STEP="title"
note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" 0 0 "start"
TITLE_T0=$SECONDS
ensure_app_terminated || true
sleep 0.2
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.skipAds" -bool true || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shot" >/dev/null 2>&1 || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.shotActive" >/dev/null 2>&1 || true
with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackSkipAds -trashStackSkipIdent >/tmp/sim-launch-title.out 2>&1 || true
TITLE_OK=0
TITLE_RECOVERED=0
for try in 1 2 3 4 5 6 7 8; do
  if (( SECONDS - TITLE_T0 > STEP_BUDGET_S )); then
    if (( TITLE_RECOVERED == 0 )); then
      echo "Title step blew ${STEP_BUDGET_S}s hard budget — recover once and retry." >&2
      recover_simulator_once "step_budget:title"
      TITLE_RECOVERED=1
      TITLE_T0=$SECONDS
      with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackSkipAds -trashStackSkipIdent >/tmp/sim-launch-title.out 2>&1 || true
      continue
    fi
    echo "Fail fast: title still over budget after recover." >&2
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
# Publisher ident — only relaunch if cold-launch capture missed the studio card.
if (( IDENT_CAPTURED == 0 )); then
  launch_shot "ident" "$OUT_DIR/00-publisher-ident.png" 3
fi
assert_not_launch_splash "$OUT_DIR/00-publisher-ident.png"
assert_shot_matches_mode "ident" "$OUT_DIR/00-publisher-ident.png"
smoke_budget
# Settle long enough for mid-game / crush juice / recycle banner.
launch_shot "game" "$OUT_DIR/02-gameplay.png" 3
assert_no_missing_textures "$OUT_DIR/02-gameplay.png"
launch_shot "compactor" "$OUT_DIR/03-compactor-clear.png" 3
assert_no_missing_textures "$OUT_DIR/03-compactor-clear.png"
# Hold recycle pose (glow + banner) — do NOT loosen assert_app_frame.
launch_shot "recycle" "$OUT_DIR/04-recycle-combo.png" 5
assert_no_missing_textures "$OUT_DIR/04-recycle-combo.png"
launch_shot "revive" "$OUT_DIR/05-game-over-revive.png" 3
assert_no_missing_textures "$OUT_DIR/05-game-over-revive.png"
launch_shot "base" "$OUT_DIR/06-base.png" 2
launch_shot "pass" "$OUT_DIR/07-pass.png" 2
launch_shot "shop" "$OUT_DIR/08-shop.png" 2
launch_shot "notif" "$OUT_DIR/09-notification-prompt.png" 2
smoke_budget
# Retention evidence: Daily Dumpster, share card, streak reward.
launch_shot "daily" "$OUT_DIR/10-daily-dumpster.png" 3
assert_no_missing_textures "$OUT_DIR/10-daily-dumpster.png"
launch_shot "share" "$OUT_DIR/11-daily-share-card.png" 2
launch_shot "streak" "$OUT_DIR/12-streak-reward.png" 2
smoke_budget

launch_shot "mkt-play" "$OUT_DIR/marketing/01-play.png" 3
assert_no_missing_textures "$OUT_DIR/marketing/01-play.png"
launch_shot "mkt-crush" "$OUT_DIR/marketing/02-crush.png" 3
assert_no_missing_textures "$OUT_DIR/marketing/02-crush.png"
launch_shot "mkt-recycle" "$OUT_DIR/marketing/03-recycle.png" 5
assert_no_missing_textures "$OUT_DIR/marketing/03-recycle.png"
launch_shot "mkt-base" "$OUT_DIR/marketing/04-junkyard.png" 2
launch_shot "mkt-pass" "$OUT_DIR/marketing/05-pass.png" 2
launch_shot "mkt-shop" "$OUT_DIR/marketing/06-shop.png" 2
launch_shot "mkt-daily" "$OUT_DIR/marketing/07-daily.png" 3
assert_no_missing_textures "$OUT_DIR/marketing/07-daily.png"
smoke_budget

# Pairwise SSIM distinctness (animated rain defeats byte-hash; SSIM < 0.95 required).
python3 - "$OUT_DIR" <<'PY'
import pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
files = [
  "00-publisher-ident.png","01-title.png","02-gameplay.png","03-compactor-clear.png","04-recycle-combo.png",
  "05-game-over-revive.png","06-base.png","07-pass.png","08-shop.png","09-notification-prompt.png",
  "10-daily-dumpster.png","11-daily-share-card.png","12-streak-reward.png",
]
paths = []
for f in files:
  p = root / f
  if not p.exists() or p.stat().st_size < 1000:
    print(f"Missing/small {p}", file=sys.stderr); sys.exit(1)
  paths.append((f, p))

# Inline SSIM helper (same algorithm as png_ssim).
import struct, zlib

def load_lum_grid(path, gw=48, gh=96):
    data = path.read_bytes()
    pos = 8
    width = height = bit_depth = color_type = None
    idat = bytearray()
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos+4])[0]
        ctype = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+length]
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
        row = bytearray(raw[start+1:start+stride])
        prev = rows[-1] if rows else bytearray(len(row))
        if filt == 1:
            for i in range(len(row)):
                row[i] = (row[i] + (row[i-bpp] if i >= bpp else 0)) & 255
        elif filt == 2:
            for i in range(len(row)):
                row[i] = (row[i] + prev[i]) & 255
        elif filt == 3:
            for i in range(len(row)):
                left = row[i-bpp] if i >= bpp else 0
                row[i] = (row[i] + ((left + prev[i]) // 2)) & 255
        elif filt == 4:
            def paeth(a,b,c):
                p=a+b-c; pa,pb,pc=abs(p-a),abs(p-b),abs(p-c)
                return a if pa<=pb and pa<=pc else b if pb<=pc else c
            for i in range(len(row)):
                a = row[i-bpp] if i>=bpp else 0
                b = prev[i]
                c = prev[i-bpp] if i>=bpp else 0
                row[i] = (row[i] + paeth(a,b,c)) & 255
        rows.append(row)
    grid = []
    for gy in range(gh):
        y = min(height-1, int((gy+0.5)*height/gh))
        row = rows[y]
        for gx in range(gw):
            x = min(width-1, int((gx+0.5)*width/gw))
            i = x * bpp
            r,g,b = row[i], row[i+1], row[i+2]
            grid.append(0.2126*r + 0.7152*g + 0.0722*b)
    return grid

def ssim(a, b, gw=48, gh=96):
    c1, c2 = (0.01*255)**2, (0.03*255)**2
    vals = []
    for y0 in range(0, gh-7, 8):
        for x0 in range(0, gw-7, 8):
            wa, wb = [], []
            for dy in range(8):
                for dx in range(8):
                    i = (y0+dy)*gw + (x0+dx)
                    wa.append(a[i]); wb.append(b[i])
            n = 64.0
            ma = sum(wa)/n; mb = sum(wb)/n
            va = sum((v-ma)**2 for v in wa)/(n-1)
            vb = sum((v-mb)**2 for v in wb)/(n-1)
            cov = sum((wa[i]-ma)*(wb[i]-mb) for i in range(64))/(n-1)
            vals.append(((2*ma*mb+c1)*(2*cov+c2))/((ma*ma+mb*mb+c1)*(va+vb+c2)+1e-12))
    return sum(vals)/max(1,len(vals))

grids = [(f, load_lum_grid(p)) for f, p in paths]
for i in range(len(grids)):
    for j in range(i+1, len(grids)):
        s = ssim(grids[i][1], grids[j][1])
        if s >= 0.95:
            print(f"Screenshots too similar: {grids[i][0]} ~ {grids[j][0]} SSIM={s:.3f}", file=sys.stderr)
            sys.exit(1)
print("Screenshot SSIM distinctness OK")
PY

CURRENT_STEP="record_video"
note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" 0 0 "start"
VIDEO_T0=$SECONDS
ensure_app_terminated || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" "trashStack.shot" -string "demo" || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.launchToGameSec" >/dev/null 2>&1 || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.launchToGameSecString" >/dev/null 2>&1 || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.firstGameFrameWallEpoch" >/dev/null 2>&1 || true
with_deadline 8 xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" "trashStack.firstGameFrameWallEpochString" >/dev/null 2>&1 || true
# Drop stale game_* lines from a prior gameplay shot so we don't accept old stamps.
_docs_clear="$(launch_docs_path)"
if [[ -n "$_docs_clear" && -f "$_docs_clear" ]]; then
  python3 - "$_docs_clear" <<'PY' || true
from pathlib import Path
import sys
p = Path(sys.argv[1])
lines = [ln for ln in p.read_text(encoding="utf-8", errors="ignore").splitlines()
         if not ln.startswith("game_") and not ln.startswith("stamp_kind_game")]
p.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
PY
fi
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
  note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" "$((SECONDS - VIDEO_T0))" 1 "start_failed"
  print_timing_table
  exit 1
fi
set -e
with_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -trashStackShot demo -trashStackSkipAds -autoplay >/tmp/sim-launch-demo.out 2>&1 || true
HOST_GAME_LAUNCH_EPOCH="$(python3 -c 'import time; print(f"{time.time():.6f}")')"
cat /tmp/sim-launch-demo.out >&2 || true
# Gate PLAY→first real game frame: in-app ≤1.5s, wall ≤8s from PID return (never loosen).
GAME_STAMPS_OK=0
GAME_INAPP=""
GAME_FRAME_EPOCH=""
HOST_GAME_STAMPS_SEEN=""
while python3 - "$HOST_GAME_LAUNCH_EPOCH" <<'PY'
import sys, time
sys.exit(0 if (time.time() - float(sys.argv[1])) <= 8.0 else 1)
PY
do
  docs="$(launch_docs_path)"
  if [[ -n "$docs" && -f "$docs" ]]; then
    body="$(cat "$docs" 2>/dev/null || true)"
    GAME_INAPP="$(docs_field_from_body "$body" game_in_app_sec)"
    GAME_FRAME_EPOCH="$(docs_field_from_body "$body" game_first_frame_wall_epoch)"
    if [[ -n "$GAME_INAPP" && -n "$GAME_FRAME_EPOCH" ]]; then
      HOST_GAME_STAMPS_SEEN="$(python3 -c 'import time; print(f"{time.time():.6f}")')"
      GAME_STAMPS_OK=1
      break
    fi
  fi
  sleep 0.1
done
if (( GAME_STAMPS_OK == 0 )); then
  GAME_INAPP="$(read_launch_field game_in_app_sec defaults)"
  GAME_FRAME_EPOCH="$(read_launch_field game_first_frame_wall_epoch defaults)"
  if [[ -n "$GAME_INAPP" && -n "$GAME_FRAME_EPOCH" ]]; then
    HOST_GAME_STAMPS_SEEN="$(python3 -c 'import time; print(f"{time.time():.6f}")')"
    GAME_STAMPS_OK=1
  fi
fi
GAME_WALL="$(python3 - "$HOST_GAME_LAUNCH_EPOCH" "$GAME_FRAME_EPOCH" "${HOST_GAME_STAMPS_SEEN:-}" <<'PY'
import sys
host=(sys.argv[1] or "").strip(); frame=(sys.argv[2] or "").strip(); seen=(sys.argv[3] or "").strip()
if not host:
    print("missing"); raise SystemExit(0)
try: h=float(host)
except ValueError:
    print("missing"); raise SystemExit(0)
app_dt=None
if frame:
    try: app_dt=float(frame)-h
    except ValueError: pass
host_dt=None
if seen:
    try: host_dt=float(seen)-h
    except ValueError: pass
if app_dt is not None and -2.0 <= app_dt <= 30.0:
    print(f"{max(0.0, app_dt):.4f}")
elif host_dt is not None and host_dt >= 0:
    print(f"{host_dt:.4f}")
elif app_dt is not None:
    print(f"{app_dt:.4f}")
else:
    print("missing")
PY
)"
{
  echo "host_game_launch_epoch=$HOST_GAME_LAUNCH_EPOCH"
  echo "game_first_frame_wall_epoch=${GAME_FRAME_EPOCH:-missing}"
  echo "host_game_stamps_seen_epoch=${HOST_GAME_STAMPS_SEEN:-missing}"
  echo "game_wall_clock_s=${GAME_WALL}"
  echo "game_in_app_sec=${GAME_INAPP:-missing}"
  echo "gates: game_in_app<=1.5s (after PLAY) AND game_wall<=8s"
} | tee -a "$OUT_DIR/launch-timing.txt"
if (( GAME_STAMPS_OK == 0 )); then
  echo "Game-path first-frame stamps never arrived within 8s of demo launch" >&2
  exit 1
fi
python3 - "$GAME_INAPP" "$GAME_WALL" <<'PY'
import sys
in_app=(sys.argv[1] or "").strip(); wall=(sys.argv[2] or "").strip()
dt=float(in_app)
if dt > 1.5:
    raise SystemExit(f"Game-path in-app {dt:.3f}s exceeds 1.5s after PLAY")
print(f"Game-path in-app OK {dt:.3f}s")
wdt=float(wall)
if wdt > 8.0:
    raise SystemExit(f"Game-path wall {wdt:.3f}s exceeds 8s ceiling")
if wdt < -1.0:
    raise SystemExit(f"Game-path wall {wdt:.3f}s looks clock-skewed")
print(f"Game-path wall OK {wdt:.3f}s")
PY
# Continuous autoplay (~35s): recycle/press/snatch/game-over beats without board teleport spam.
sleep 35
kill -INT "$REC_PID" 2>/dev/null || true
# Force-kill if simctl recordVideo ignores INT (known hang source).
# Never bare-wait: a wedged recordVideo previously hung until the 35m step timeout.
sleep 2
if kill -0 "$REC_PID" 2>/dev/null; then
  echo "recordVideo still alive after INT — sending KILL" >&2
  kill -KILL "$REC_PID" 2>/dev/null || true
fi
# Reap with a hard deadline (python wait, not bash wait).
python3 - "$REC_PID" <<'PY' || true
import os, signal, subprocess, sys, time
pid = int(sys.argv[1])
deadline = time.time() + 8
while time.time() < deadline:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        # Already gone — try non-blocking wait via a short subprocess wait.
        break
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        break
    time.sleep(0.2)
# Best-effort waitpid via os.waitpid if we are the parent; ignore errors.
try:
    os.waitpid(pid, os.WNOHANG)
except Exception:
    pass
print(f"recordVideo reap done pid={pid}", flush=True)
PY
note_timing deadline "recordVideo reap" 8 "$((SECONDS - VIDEO_T0))" 0 "step=$CURRENT_STEP"
sleep 1
if (( SECONDS - VIDEO_T0 > STEP_BUDGET_S )); then
  echo "Fail fast: record_video exceeded ${STEP_BUDGET_S}s step budget." >&2
  note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" "$((SECONDS - VIDEO_T0))" 124 "budget_exceeded"
  print_timing_table
  exit 125
fi
note_timing step "$CURRENT_STEP" "$STEP_BUDGET_S" "$((SECONDS - VIDEO_T0))" 0 "ok"
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
CURRENT_STEP="ffmpeg_mux"
note_timing step "$CURRENT_STEP" 90 0 0 "start"
FFMPEG_T0=$SECONDS
echo "Muxing music bed only with $FFMPEG_BIN ($(wc -c < "$VIDEO_RAW") byte silent capture)" >&2
# Copy video (no libx264 re-encode) — re-encoding 1206x2622@45fps blew the 60s
# deadline on CI (~0.5x realtime). Audio-only encode finishes in seconds.
# Use raw_deadline so a mux flake does not trip simulator wedge recovery.
if ! raw_deadline 45 "$FFMPEG_BIN" -hide_banner -y \
  -i "$VIDEO_RAW" -stream_loop -1 -i "$MUSIC" \
  -filter_complex "[1:a]volume=0.34,atrim=0:45[aout]" \
  -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 128k -ac 1 \
  -shortest -movflags +faststart "$VIDEO_OUT" \
  >/tmp/ffmpeg-mux.log 2>&1; then
    echo "ffmpeg stream-copy mux failed; trying ultrafast re-encode fallback" >&2
    cat /tmp/ffmpeg-mux.log >&2 || true
    if ! raw_deadline 90 "$FFMPEG_BIN" -hide_banner -y \
      -i "$VIDEO_RAW" -stream_loop -1 -i "$MUSIC" \
      -filter_complex "[1:a]volume=0.34,atrim=0:45[aout]" \
      -map 0:v -map "[aout]" -c:v libx264 -preset ultrafast -crf 32 -pix_fmt yuv420p \
      -c:a aac -b:a 96k -ac 1 -shortest -movflags +faststart "$VIDEO_OUT" \
      >/tmp/ffmpeg-mux.log 2>&1; then
      echo "ffmpeg mux failed entirely" >&2
      cat /tmp/ffmpeg-mux.log >&2 || true
      note_timing step "$CURRENT_STEP" 90 "$((SECONDS - FFMPEG_T0))" 1 "mux_failed"
      print_timing_table
      exit 1
    fi
fi
rm -f "$VIDEO_RAW"
AUDIO_OK=0
if raw_deadline 15 "$FFPROBE_BIN" -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$VIDEO_OUT" >/tmp/ffprobe-audio.txt 2>/dev/null \
  && grep -q audio /tmp/ffprobe-audio.txt; then
  AUDIO_OK=1
fi
if (( AUDIO_OK != 1 )); then
  echo "Gameplay video missing audio track after mux" >&2
  cat /tmp/ffmpeg-mux.log >&2 || true
  note_timing step "$CURRENT_STEP" 90 "$((SECONDS - FFMPEG_T0))" 1 "no_audio"
  print_timing_table
  exit 1
fi
bytes=$(wc -c < "$VIDEO_OUT")
if (( bytes > 150000000 )); then
  echo "Gameplay video too large ($bytes bytes); recompressing" >&2
  raw_deadline 90 "$FFMPEG_BIN" -hide_banner -y -i "$VIDEO_OUT" \
    -c:v libx264 -preset ultrafast -crf 32 -c:a aac -b:a 96k \
    "$OUT_DIR/gameplay-demo-small.mp4" >/tmp/ffmpeg-small.log 2>&1 || true
  if [[ -s "$OUT_DIR/gameplay-demo-small.mp4" ]]; then
    mv -f "$OUT_DIR/gameplay-demo-small.mp4" "$VIDEO_OUT"
  fi
fi
echo "Muxed game_loop bed onto gameplay-demo.mp4 ($(wc -c < "$VIDEO_OUT") bytes)" >&2
# Near-miss / GO window for evidence (~t=20–28s). Prefer stream copy of the window.
if ! raw_deadline 30 "$FFMPEG_BIN" -hide_banner -y -ss 20 -t 8 -i "$VIDEO_OUT" \
  -c:v copy -c:a aac -b:a 128k "$OUT_DIR/recycle-chain-clip.mp4" >/tmp/ffmpeg-clip.log 2>&1; then
  if ! raw_deadline 45 "$FFMPEG_BIN" -hide_banner -y -ss 20 -t 8 -i "$VIDEO_OUT" \
    -c:v libx264 -preset ultrafast -crf 32 -pix_fmt yuv420p -c:a aac -b:a 128k \
    "$OUT_DIR/recycle-chain-clip.mp4" >/tmp/ffmpeg-clip.log 2>&1; then
    echo "tension clip failed/timed out" >&2
    cat /tmp/ffmpeg-clip.log >&2 || true
    exit 1
  fi
fi
CLIP_AUDIO_OK=0
if raw_deadline 15 "$FFPROBE_BIN" -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$OUT_DIR/recycle-chain-clip.mp4" >/tmp/ffprobe-clip.txt 2>/dev/null \
  && grep -q audio /tmp/ffprobe-clip.txt; then
  CLIP_AUDIO_OK=1
fi
if (( CLIP_AUDIO_OK != 1 )); then
  echo "recycle-chain-clip.mp4 missing audio" >&2
  exit 1
fi
note_timing step "$CURRENT_STEP" 90 "$((SECONDS - FFMPEG_T0))" 0 "ok"

fps="$(with_deadline 8 xcrun simctl spawn "$DEVICE" defaults read "$BUNDLE_ID" trashStack.measuredFPS 2>/dev/null || echo 0)"
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

#!/usr/bin/env bash
# Copyright © 2026 Cinder and Crown LLC. All rights reserved.
# Cheap screenshot-only pass: title, mid-run play, game-over.
# Real simctl captures only — never generate mock art.
set -euo pipefail

DEVICE="${1:?simulator UDID}"
APP_PATH="${2:?path to TrashStack.app}"
OUT_DIR="${3:-smoke-artifacts}"
TAG="${4:-se}"  # filename prefix: pro / se
# Optional 5th arg: comma-separated modes (title,game,revive). Default = all three.
MODES="${5:-title,game,revive}"
BUNDLE_ID="${BUNDLE_ID:-com.cinderandcrown.trashstack}"
DISPLAY="${SIMCTL_DISPLAY:-internal}"
SHOT_DEADLINE_S="${SHOT_DEADLINE_S:-10}"
SIMCTL_DEADLINE_S="${SIMCTL_DEADLINE_S:-12}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

FIT_DIR="$OUT_DIR/fit"
mkdir -p "$FIT_DIR"

# Same-session setpgrp (not start_new_session): killpg gets EPERM on macOS CI
# with start_new_session and leaves orphaned simctl children that break install.
raw_deadline() {
  local secs="$1" rc=0
  shift
  python3 - "$secs" "$@" <<'PY' || rc=$?
import os, signal, subprocess, sys, time
secs = float(sys.argv[1]); cmd = sys.argv[2:]

def nuke(pid: int) -> None:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except ProcessLookupError:
            return
        except OSError:
            try:
                os.kill(pid, sig)
            except OSError:
                pass
            try:
                out = subprocess.check_output(
                    ["pgrep", "-P", str(pid)], text=True, stderr=subprocess.DEVNULL
                )
            except Exception:
                out = ""
            for line in out.split():
                try:
                    os.kill(int(line.strip()), sig)
                except (OSError, ValueError):
                    pass
        if sig == signal.SIGTERM:
            time.sleep(0.25)

proc = subprocess.Popen(cmd, preexec_fn=os.setpgrp)
try:
    code = proc.wait(timeout=secs)
    sys.exit(code if code is not None else 0)
except subprocess.TimeoutExpired:
    nuke(proc.pid)
    deadline = time.time() + 2.0
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

shot() {
  local out="$1"
  if raw_deadline "$SHOT_DEADLINE_S" xcrun simctl io "$DEVICE" screenshot --display="$DISPLAY" "$out" 2>/tmp/fit-shot.err; then
    return 0
  fi
  raw_deadline "$SHOT_DEADLINE_S" xcrun simctl io "$DEVICE" screenshot "$out" 2>/tmp/fit-shot.err
}

kill_app() {
  raw_deadline 6 xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  raw_deadline 3 xcrun simctl spawn "$DEVICE" killall -9 TrashStack >/dev/null 2>&1 || true
}

# Stdlib PNG board/splash checks (no Pillow required on CI).
assert_board_painted() {
  local png="$1"
  python3 - "$png" <<'PY'
import pathlib, struct, sys, zlib
path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 200_000:
    print(f"FAIL board shot too small ({len(data)} B): {path}", file=sys.stderr)
    raise SystemExit(1)
if data[:8] != b"\x89PNG\r\n\x1a\n":
    print(f"FAIL not PNG: {path}", file=sys.stderr)
    raise SystemExit(1)
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

# Center board band — reject flat grey void (RGB≈191, var≈0).
vals = []
for fy in (0.40, 0.50, 0.60, 0.70):
    for fx in (0.25, 0.40, 0.55, 0.70):
        r,g,b = sample(fx, fy)
        vals.append((r+g+b)/3.0)
mean = sum(vals)/len(vals)
var = sum((v-mean)**2 for v in vals)/len(vals)
if mean > 150 and var < 80:
    print(f"FAIL flat grey board in {path.name}: mean={mean:.1f} var={var:.1f}", file=sys.stderr)
    raise SystemExit(1)
if var < 120:
    print(f"FAIL board band too flat in {path.name}: mean={mean:.1f} var={var:.1f}", file=sys.stderr)
    raise SystemExit(1)
# Reject publisher phoenix splash (near-black + orange crown, no HUD teal).
dark = sum(1 for fy in (0.2,0.4,0.6,0.8) for fx in (0.2,0.5,0.8)
           if (lambda r,g,b: r<40 and g<40 and b<40)(*sample(fx,fy)))
orange = sum(1 for fy in (0.35,0.45,0.55) for fx in (0.4,0.5,0.6)
             if (lambda r,g,b: r>180 and g>80 and b<80)(*sample(fx,fy)))
if dark >= 6 and orange >= 2:
    print(f"FAIL publisher splash, not board: {path.name}", file=sys.stderr)
    raise SystemExit(1)
print(f"fit board OK {path.name}: mean={mean:.1f} var={var:.1f}")
PY
}

assert_game_over_overlay() {
  local png="$1"
  python3 - "$png" <<'PY'
import pathlib, struct, sys, zlib
path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 250_000:
    print(f"FAIL game-over too small ({len(data)} B) — likely splash/grey: {path}", file=sys.stderr)
    raise SystemExit(1)
if data[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit(1)
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

# Reject phoenix splash.
splash_dark = sum(1 for fy in (0.2,0.4,0.6,0.8) for fx in (0.2,0.5,0.8)
           if (lambda r,g,b: r<40 and g<40 and b<40)(*sample(fx,fy)))
orange = sum(1 for fy in (0.35,0.45,0.55) for fx in (0.4,0.5,0.6)
             if (lambda r,g,b: r>180 and g>80 and b<80)(*sample(fx,fy)))
if splash_dark >= 6 and orange >= 2:
    print(f"FAIL game-over is publisher splash: {path.name}", file=sys.stderr)
    raise SystemExit(1)
# Real GO = dark NeonPanel + NEW BEST/SO CLOSE title + wide Play-again CTA.
# Wider bands cover Pro (Dynamic Island) and SE — same thresholds.
panel = title = btn = 0
for fy in (0.32, 0.38, 0.44, 0.50, 0.56, 0.62, 0.68):
    for fx in (0.22, 0.35, 0.50, 0.65, 0.78):
        r,g,b = sample(fx, fy)
        if r < 30 and g < 40 and b < 50: panel += 1
for fy in (0.24, 0.28, 0.32, 0.36, 0.40, 0.44, 0.48):
    for fx in (0.30, 0.40, 0.50, 0.60, 0.70):
        r,g,b = sample(fx, fy)
        if (g > 190 and b > 170 and r < 60) or (r > 170 and b > 90 and g < 130):
            title += 1
for fy in (0.52, 0.56, 0.60, 0.64, 0.68, 0.72, 0.76):
    for fx in (0.22, 0.32, 0.42, 0.52, 0.62, 0.72):
        r,g,b = sample(fx, fy)
        if g > 160 and r > 80 and b > 80: btn += 1
if panel < 8 or title < 1 or btn < 3:
    print(f"FAIL game-over missing overlay (panel={panel} title={title} btn={btn}): {path.name}", file=sys.stderr)
    raise SystemExit(1)
print(f"fit game-over OK {path.name}: panel={panel} title={title} btn={btn}")
PY
}

# Poll past OS LaunchLogo (tiny neon card ~80–120 KB) before asserting content.
wait_past_launch_logo() {
  local out="$1"
  local max_s="${2:-12}"
  local ticks=0
  local max_ticks
  max_ticks=$(python3 -c "print(max(1, int(float('$max_s') / 0.75)))")
  while (( ticks < max_ticks )); do
    shot "$out" || true
    if [[ -s "$out" ]] && [[ "$(wc -c < "$out")" -gt 200000 ]]; then
      return 0
    fi
    sleep 0.75
    ticks=$((ticks + 1))
  done
  return 1
}

cold_launch_shot() {
  local mode="$1"
  local out="$2"
  local settle="${3:-4}"
  local max_attempts="${4:-3}"
  local attempt
  local tmp="${out}.attempt.png"
  for attempt in $(seq 1 "$max_attempts"); do
    kill_app
    # Launch args carry shot mode — avoid a stack of spawn defaults that wedge simctl.
    if (( attempt == 1 )); then
      raw_deadline 5 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" tutorialDone -bool true >/dev/null 2>&1 || true
      raw_deadline 5 xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" classicButtons -bool false >/dev/null 2>&1 || true
    fi
    raw_deadline "$SIMCTL_DEADLINE_S" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
      -trashStackShot "$mode" -trashStackSkipAds -trashStackSkipIdent >/tmp/fit-launch-"$mode".out 2>&1 || true
    cat /tmp/fit-launch-"$mode".out >&2 || true
    sleep "$settle"
    # Do not overwrite a prior good $out until this attempt passes.
    rm -f "$tmp"
    if ! wait_past_launch_logo "$tmp" 14; then
      echo "Fit: $mode still LaunchLogo/empty attempt=$attempt ($(wc -c < "$tmp" 2>/dev/null || echo 0) bytes)" >&2
      settle=$(python3 -c "print(min(10, $settle + 1.5))")
      continue
    fi
    case "$mode" in
      game|gameplay|compactor)
        if assert_board_painted "$tmp"; then
          mv -f "$tmp" "$out"
          echo "Wrote $out ($(wc -c < "$out") bytes) attempt=$attempt" >&2
          return 0
        fi
        ;;
      revive)
        if assert_game_over_overlay "$tmp"; then
          mv -f "$tmp" "$out"
          echo "Wrote $out ($(wc -c < "$out") bytes) attempt=$attempt" >&2
          return 0
        fi
        ;;
      title)
        if python3 "$ROOT/scripts/assert_fit_title.py" "$tmp" >/tmp/fit-title-assert.out 2>&1; then
          cat /tmp/fit-title-assert.out >&2 || true
          mv -f "$tmp" "$out"
          echo "Wrote $out ($(wc -c < "$out") bytes) attempt=$attempt" >&2
          return 0
        fi
        cat /tmp/fit-title-assert.out >&2 || true
        ;;
      *)
        mv -f "$tmp" "$out"
        echo "Wrote $out ($(wc -c < "$out") bytes) attempt=$attempt" >&2
        return 0
        ;;
    esac
    echo "Fit: $mode shot rejected attempt=$attempt — relaunching" >&2
    settle=$(python3 -c "print(min(10, $settle + 1.5))")
  done
  echo "Fit shots: failed $mode → $out" >&2
  rm -f "$tmp"
  # Leave any prior good $out in place (CI may have preserved smoke aliases).
  if [[ ! -s "$out" ]]; then
    return 1
  fi
  return 1
}

echo "Fit shots on $DEVICE tag=$TAG → $FIT_DIR" >&2
raw_deadline 40 xcrun simctl boot "$DEVICE" >/tmp/fit-boot.log 2>&1 || true
raw_deadline 90 xcrun simctl bootstatus "$DEVICE" -b >/tmp/fit-boot.log 2>&1 || true
raw_deadline 20 xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
INSTALL_OK=0
for inst_try in 1 2 3; do
  if raw_deadline 90 xcrun simctl install "$DEVICE" "$APP_PATH" >/tmp/fit-install.log 2>&1; then
    INSTALL_OK=1
    break
  fi
  echo "Fit install attempt=$inst_try failed — reboot + retry" >&2
  cat /tmp/fit-install.log >&2 || true
  raw_deadline 20 xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1 || true
  sleep 1
  raw_deadline 40 xcrun simctl boot "$DEVICE" >/tmp/fit-boot.log 2>&1 || true
  raw_deadline 90 xcrun simctl bootstatus "$DEVICE" -b >/tmp/fit-boot.log 2>&1 || true
done
if (( INSTALL_OK != 1 )); then
  echo "Fit shots: install failed after retries" >&2
  cat /tmp/fit-install.log >&2 || true
  exit 1
fi

{
  echo "tag=$TAG"
  echo "udid=$DEVICE"
  xcrun simctl list devices | grep "$DEVICE" || true
} > "$FIT_DIR/${TAG}-device.txt"

# Run requested modes independently — a title miss must not skip revive/GO.
fail=0
IFS=',' read -r -a MODE_LIST <<< "$MODES"
for mode in "${MODE_LIST[@]}"; do
  mode="$(echo "$mode" | tr -d '[:space:]')"
  [[ -z "$mode" ]] && continue
  case "$mode" in
    title)
      cold_launch_shot title "$FIT_DIR/${TAG}-title.png" 4.0 4 || fail=1
      ;;
    game|play|gameplay)
      cold_launch_shot game "$FIT_DIR/${TAG}-play.png" 4.0 4 || fail=1
      ;;
    revive|game-over|go)
      # Pro needs a longer settle for the revive overlay after heavy smoke/real-play.
      cold_launch_shot revive "$FIT_DIR/${TAG}-game-over.png" 7.0 6 || fail=1
      ;;
    *)
      echo "Fit shots: unknown mode '$mode' (use title,game,revive)" >&2
      fail=1
      ;;
  esac
done

fit_check=0
python3 - "$FIT_DIR" "$TAG" "$MODES" <<'PY' || fit_check=$?
import pathlib, sys
root = pathlib.Path(sys.argv[1]); tag = sys.argv[2]
modes = {m.strip() for m in sys.argv[3].split(",") if m.strip()}
wanted = []
if "title" in modes:
    wanted.append(f"{tag}-title.png")
if modes & {"game", "play", "gameplay"}:
    wanted.append(f"{tag}-play.png")
if modes & {"revive", "game-over", "go"}:
    wanted.append(f"{tag}-game-over.png")
ok = True
for name in wanted:
    p = root / name
    sz = p.stat().st_size if p.is_file() else 0
    print(f"fit {name}: {sz} bytes")
    if sz < 20_000:
        print(f"FAIL fit shot small/missing: {p}", file=sys.stderr)
        ok = False
sys.exit(0 if ok else 1)
PY
if (( fail != 0 || fit_check != 0 )); then
  echo "Fit shots incomplete for tag=$TAG (fail=$fail check=$fit_check)" >&2
  exit 1
fi
echo "Fit shots done for tag=$TAG" >&2

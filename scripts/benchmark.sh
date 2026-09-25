#!/usr/bin/env bash
set -uo pipefail

APP="${BOTCH_APP:-/Applications/Botch.app}"
MOCK="${BOTCH_MOCK_CHROME:?set BOTCH_MOCK_CHROME to a synthetic Chrome directory}"
SOURCE="${BOTCH_SOURCE:-$(cd "$(dirname "$0")/.." && pwd)}"
OUT="${BENCH_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/botch-bench.XXXXXX")}"
PHASES="${BENCH_PHASES:-sizes memory cpu startup latency}"
PORT="${BENCH_PORT:-18765}"
RUNS="${BENCH_RUNS:-5}"
IDLE_WINDOW="${BENCH_IDLE_WINDOW:-60}"
ACTIVE_WINDOW="${BENCH_ACTIVE_WINDOW:-30}"
BIN="$APP/Contents/MacOS/Botch"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null)}"
if [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
  DEVELOPER_DIR="$(ls -d /Applications/Xcode*.app/Contents/Developer 2>/dev/null | head -1)"
fi
export DEVELOPER_DIR
export BOTCH_MOCK_CHROME="$MOCK"
mkdir -p "$OUT/www"
SERVER_PID=""
BOTCH_PID=""
HELPERS=""

cleanup() {
  pkill -x Botch 2>/dev/null
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
}
trap cleanup EXIT

say() { printf '%s\n' "$@"; }
mb_from_bytes() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1048576 }'; }
median() { sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }'; }
minimum() { sort -n | head -1; }
has_phase() { [[ " $PHASES " == *" $1 "* ]]; }

write_session() {
  local file="$1"; shift
  local tabs
  tabs="$(printf '"%s",' "$@")"
  printf '{"profile":"Default","tabs":[%s],"selected":0,"width":980,"height":640}\n' \
    "${tabs%,}" > "$file"
}

webkit_pids() { pgrep -f 'com.apple.WebKit' | sort; }

helper_name() {
  ps -o comm= -p "$1" | sed 's#.*/##; s#com.apple.WebKit.##'
}

launch_botch() {
  local session="$1" open_for="$2" settle="$3"
  pkill -x Botch 2>/dev/null
  sleep 2
  cp "$session" "$MOCK/session.json"
  webkit_pids > "$OUT/webkit-before.txt"
  if [ -n "$open_for" ]; then
    BOTCH_MOCK_OPEN="$open_for" "$BIN" >/dev/null 2>&1 &
  else
    "$BIN" >/dev/null 2>&1 &
  fi
  BOTCH_PID=$!
  sleep "$settle"
  webkit_pids > "$OUT/webkit-after.txt"
  HELPERS="$(comm -13 "$OUT/webkit-before.txt" "$OUT/webkit-after.txt" | tr '\n' ' ')"
}

stop_botch() {
  local leftovers
  pkill -x Botch 2>/dev/null
  sleep 2
  leftovers=""
  for p in $HELPERS; do kill -0 "$p" 2>/dev/null && leftovers="$leftovers $p"; done
  if [ -n "$leftovers" ]; then say "  warning: helpers still alive after quit:$leftovers"; fi
}

footprint_mb() {
  footprint "$1" 2>/dev/null | awk '/Footprint:/ { v = $(NF - 3); u = $(NF - 2);
    if (u == "KB") v /= 1024; if (u == "GB") v *= 1024; printf "%.1f", v; exit }'
}

memory_table() {
  local label="$1" total_fp=0 total_rss=0 fp rss name
  say "" "### memory: $label" "" "| process | pid | footprint (MB) | rss (MB) | started |" "|---|---|---|---|---|"
  for p in $BOTCH_PID $HELPERS; do
    name="$(helper_name "$p")"
    fp="$(footprint_mb "$p")"
    rss="$(ps -o rss= -p "$p" | awk '{ printf "%.1f", $1 / 1024 }')"
    say "| $name | $p | ${fp:-?} | ${rss:-?} | $(ps -o lstart= -p "$p" | awk '{ print $4 }') |"
    total_fp="$(awk -v a="$total_fp" -v b="${fp:-0}" 'BEGIN { print a + b }')"
    total_rss="$(awk -v a="$total_rss" -v b="${rss:-0}" 'BEGIN { print a + b }')"
  done
  say "| total | | $total_fp | $total_rss | |"
}

cpu_table() {
  local label="$1" window="$2" args=() total
  say "" "### cpu: $label (${window} s window, top -l 2 -s $window, second sample)" "" "| process | pid | cpu % |" "|---|---|---|"
  for p in $BOTCH_PID $HELPERS; do args+=(-pid "$p"); done
  top -l 2 -s "$window" -stats pid,cpu,command "${args[@]}" 2>/dev/null \
    | awk '/^PID/ { block++ } block == 2 && $1 ~ /^[0-9]+$/ { print $1, $2 }' > "$OUT/cpu.txt"
  total=0
  while read -r pid cpu; do
    say "| $(helper_name "$pid") | $pid | $cpu |"
    total="$(awk -v a="$total" -v b="$cpu" 'BEGIN { printf "%.1f", a + b }')"
  done < "$OUT/cpu.txt"
  say "| total | | $total |"
}

phase_sizes() {
  local archs arch thin
  say "## sizes" "" "| item | value | command |" "|---|---|---|"
  say "| app bundle | $(du -sh "$APP" | cut -f1) ($(du -sk "$APP" | cut -f1) KB) | du -sh, du -sk |"
  say "| executable | $(stat -f %z "$BIN") bytes | stat -f %z |"
  archs="$(lipo -archs "$BIN")"
  say "| architectures | $archs | lipo -archs |"
  for arch in $archs; do
    thin="$OUT/Botch-$arch"
    lipo -thin "$arch" -output "$thin" "$BIN" 2>/dev/null || cp "$BIN" "$thin"
    say "| executable $arch | $(stat -f %z "$thin") bytes, $(size "$thin" | awk 'NR == 2 { print "__TEXT " $1 ", __DATA " $2 }') | lipo -thin, size |"
  done
  say "| resources | $(du -sh "$APP/Contents/Resources" | cut -f1) | du -sh |"
  say "| bundled frameworks | $(ls "$APP/Contents/Frameworks" 2>/dev/null | wc -l | tr -d ' ') | ls Contents/Frameworks |"
  say "| system frameworks linked | $(otool -L "$BIN" | grep -c '/System/Library/Frameworks/') ($(otool -L "$BIN" | grep -o '/System/Library/Frameworks/[A-Za-z]*' | sed 's#.*/##' | tr '\n' ' ')) | otool -L |"
  say "| swift runtime dylibs linked | $(otool -L "$BIN" | grep -c '/usr/lib/swift/') | otool -L |"
  say "| code signature | $(codesign -dv "$APP" 2>&1 | grep -o 'Signature=.*') | codesign -dv |"
  if command -v gh >/dev/null && gh release download v0.1.0 --repo pulkitxm/botch --dir "$OUT/release" --clobber >/dev/null 2>&1; then
    say "| Botch.zip (v0.1.0 asset) | $(stat -f %z "$OUT/release/Botch.zip") bytes ($(mb_from_bytes "$(stat -f %z "$OUT/release/Botch.zip")") MB) | gh release download, stat |"
    say "| Botch.dmg (v0.1.0 asset) | $(stat -f %z "$OUT/release/Botch.dmg") bytes ($(mb_from_bytes "$(stat -f %z "$OUT/release/Botch.dmg")") MB) | gh release download, stat |"
    rm -rf "$OUT/release/unzipped" && mkdir -p "$OUT/release/unzipped" \
      && ditto -x -k "$OUT/release/Botch.zip" "$OUT/release/unzipped"
    say "| zip binary matches installed | $([ "$(shasum -a 256 "$OUT/release/unzipped/Botch.app/Contents/MacOS/Botch" | cut -d' ' -f1)" = "$(shasum -a 256 "$BIN" | cut -d' ' -f1)" ] && echo yes || echo no) | shasum -a 256 |"
  fi
  say "" "### other browsers installed" "" "| app | size | version |" "|---|---|---|"
  for app in /Applications/Google\ Chrome.app /System/Cryptexes/App/System/Applications/Safari.app \
    $(ls -d /Applications/*.app 2>/dev/null | grep -iE 'arc|dia|firefox|brave|edge|orion|zen|chromium|opera|vivaldi'); do
    [ -d "$app" ] || continue
    say "| $(basename "$app") | $(du -sh "$app" 2>/dev/null | cut -f1) | $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null) |"
  done
}

start_scroll_server() {
  cat > "$OUT/www/scroll.html" <<'HTML'
<html><head><title>Scrolling page</title><style>body{font:16px sans-serif;margin:0;padding:24px}p{max-width:720px}</style></head><body>
<script>for(let i=0;i<400;i++){document.write('<p>Paragraph '+i+': mock text that fills the page so there is something to scroll through while measuring cpu usage of the browser process and its helpers.</p>')}
let dir=1;setInterval(()=>{window.scrollBy(0,dir*6);if(window.scrollY+innerHeight>=document.body.scrollHeight-2)dir=-1;if(window.scrollY<=0)dir=1;},16)</script></body></html>
HTML
  (cd "$OUT/www" && python3 -m http.server "$PORT" >/dev/null 2>&1) &
  SERVER_PID=$!
  sleep 1
}

prepare_sessions() {
  write_session "$OUT/session-1.json" "https://example.com/"
  write_session "$OUT/session-5.json" "https://example.com/" "https://en.wikipedia.org/wiki/Notch" \
    "https://developer.mozilla.org/en-US/" "https://www.wikipedia.org/" "https://news.ycombinator.com/"
  write_session "$OUT/session-scroll.json" "http://127.0.0.1:$PORT/scroll.html"
  defaults write com.pulkit.botch.mock onboarded -bool true
  defaults write com.pulkit.botch.mock enabled -bool true
}

phase_memory_cpu() {
  say "" "## memory and cpu (mock profile, BOTCH_MOCK_OPEN drives open and collapse)"
  launch_botch "$OUT/session-1.json" "" 15
  has_phase memory && memory_table "idle collapsed, one saved tab, browser never opened"
  has_phase cpu && cpu_table "idle collapsed" "$IDLE_WINDOW"
  stop_botch
  launch_botch "$OUT/session-1.json" 900 20
  has_phase memory && memory_table "browser open on https://example.com/"
  has_phase cpu && cpu_table "open and idle on https://example.com/" "$ACTIVE_WINDOW"
  stop_botch
  launch_botch "$OUT/session-5.json" 900 30
  has_phase memory && memory_table "browser open with five tabs"
  stop_botch
  if has_phase cpu; then
    launch_botch "$OUT/session-scroll.json" 900 12
    cpu_table "page scrolling continuously" "$ACTIVE_WINDOW"
    stop_botch
  fi
  launch_botch "$OUT/session-5.json" 20 45
  has_phase memory && memory_table "collapsed after five tabs, tabs kept alive"
  has_phase cpu && cpu_table "collapsed after five tabs" "$IDLE_WINDOW"
  stop_botch
}

phase_startup() {
  local probe="$OUT/launchprobe" cold="$OUT/cold/Botch.app" i
  cat > "$OUT/launchprobe.swift" <<'SWIFT'
import CoreGraphics
import Foundation

let binary = CommandLine.arguments[1]
let layer = Int(CommandLine.arguments[2]) ?? 33
let process = Process()
process.executableURL = URL(fileURLWithPath: binary)
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice
let clock = ContinuousClock()
let start = clock.now
try process.run()
let pid = process.processIdentifier
var found = false
while !found, clock.now - start < .seconds(30) {
    let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    found = list.contains {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid
            && ($0[kCGWindowLayer as String] as? Int) == layer
    }
    usleep(2000)
}
let elapsed = clock.now - start
let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
print(found ? String(format: "%.0f", ms) : "timeout")
sleep(1)
process.terminate()
SWIFT
  swiftc -O -o "$probe" "$OUT/launchprobe.swift" || return
  pkill -x Botch 2>/dev/null; sleep 2
  cp "$OUT/session-1.json" "$MOCK/session.json"
  say "" "## startup" "" "| run | launch to notch panel window (ms) |" "|---|---|"
  : > "$OUT/warm.txt"
  for i in $(seq 1 "$RUNS"); do
    "$probe" "$BIN" 33 | tee -a "$OUT/warm.txt" | sed "s/^/| warm $i | /; s/$/ |/"
    sleep 2
  done
  say "| warm min | $(minimum < "$OUT/warm.txt") |" "| warm median | $(median < "$OUT/warm.txt") |"
  rm -rf "$OUT/cold" && mkdir -p "$OUT/cold" && cp -R "$APP" "$cold"
  say "| first launch of a fresh copy | $("$probe" "$cold/Contents/MacOS/Botch" 33) |"
  say "" "measured by spawning the executable and polling CGWindowListCopyWindowInfo every 2 ms for a window owned by the new pid at level 33 (statusBar + 8, the notch panel)"
}

phase_latency() {
  say "" "## open latency (in-process, swift test with BOTCH_TIMING=1)" ""
  (cd "$SOURCE" && BOTCH_TIMING=1 swift test --filter NotchOpenTimingTests 2>&1 | grep '^timing:' | sed 's/^timing: /- /')
}

say "# Botch benchmark" "" "date: $(date '+%Y-%m-%d %H:%M %Z')" "app: $APP ($(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist"))" \
  "machine: $(sysctl -n machdep.cpu.brand_string), $(($(sysctl -n hw.memsize) / 1073741824)) GB, $(sysctl -n hw.model)" \
  "macos: $(sw_vers -productVersion) ($(sw_vers -buildVersion))" "load average at start: $(sysctl -n vm.loadavg)" \
  "output: $OUT" ""
has_phase sizes && phase_sizes
if has_phase memory || has_phase cpu; then
  start_scroll_server
  prepare_sessions
  phase_memory_cpu
fi
if has_phase startup; then prepare_sessions; phase_startup; fi
has_phase latency && phase_latency
say "" "load average at end: $(sysctl -n vm.loadavg)"

#!/usr/bin/env bash
# Records a ~30 s demo of the Island for the README and release notes.
# Run it yourself (it needs Screen Recording permission for your terminal), with nothing else on screen:
#   scripts/record-demo.sh            → dist/demo/island-demo.mov (+ .gif if ffmpeg is installed)
# It builds and launches the DEBUG app (which accepts scripted commands), plays a fixed sequence, and
# records just the area around the notch. Quit it afterwards and reopen /Applications/Island.app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist/demo"
D="$ROOT/scripts/island-debug.sh"
DURATION=32
mkdir -p "$OUT"
rm -f "$OUT/island-demo.mov" "$OUT/island-demo.gif"

"$ROOT/scripts/run.sh" >/dev/null
sleep 6

# The notch's screen: a 900 × 320 pt area centred on it, so the Island and its expanded card fit.
read -r X Y W H < <(swift - <<'SWIFT' 2>/dev/null
import AppKit
let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
let main = NSScreen.screens[0].frame
let f = screen.frame
let w = 900.0, h = 320.0
// screencapture uses top-left coordinates on the main display.
let x = f.midX - w / 2, y = main.maxY - f.maxY
print(Int(x), Int(y), Int(w), Int(h))
SWIFT
)
[[ -n "${X:-}" ]] || { echo "Couldn't find the notch screen" >&2; exit 1; }

say() { echo "· $1"; }
pause() { sleep "$1"; }

"$D" clear; "$D" collapse; pause 1
screencapture -v -V "$DURATION" -R "$X,$Y,$W,$H" -x "$OUT/island-demo.mov" &
REC=$!
pause 1.5

say "music, compact";        "$D" music;        pause 2.5
say "open";                  "$D" expand;       pause 3
say "close";                 "$D" collapse;     pause 1.5
say "AirPods connect";       "$D" airpodspro;   pause 5
say "several activities";    "$D" timer; pause 1; "$D" download; pause 2.5
say "search";                "$D" collapse; "$D" search; pause 1; "$D" "query:timer 5 min"; pause 3
"$D" search; pause 1
say "teleprompter";          "$D" clear; "$D" prompter; pause 4; "$D" prompterstop; pause 1
say "file shelf";            "$D" shelfdemo;    pause 3; "$D" shelfclear
"$D" clear; "$D" collapse

wait "$REC" || true
echo "✓ $OUT/island-demo.mov"

if command -v ffmpeg >/dev/null; then
  ffmpeg -loglevel error -y -i "$OUT/island-demo.mov" \
    -vf "fps=30,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
    "$OUT/island-demo.gif"
  echo "✓ $OUT/island-demo.gif"
else
  echo "Tip: brew install ffmpeg, then re-run to also get a GIF for the README."
fi

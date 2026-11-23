#!/usr/bin/env bash
# Teleprompter with REAL mouse/keyboard input against a running DEBUG Island (needs Accessibility).
# Moves the pointer and presses Escape — don't use the Mac while it runs.
set -uo pipefail
cd "$(dirname "$0")/../.."
Q=.build/island/qa-input; R=scripts/island-debug.sh; D="$(getconf DARWIN_USER_TEMP_DIR)island-debug.txt"
PASS=0; FAIL=0
dump() { "$R" dump; sleep 0.25; }
mode() { dump; sed -n 's/^mode=\([a-z]*\).*/\1/p' "$D"; }
pfield() { dump; grep '^prompter=' "$D" | grep -o "$1=[^ ]*" | cut -d= -f2; }
pos() { dump; sed -n 's/^prompter=[a-z]* pos=\([0-9.]*\).*/\1/p' "$D"; }
check() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (got '$2', want '$3')"; FAIL=$((FAIL+1)); fi; }
grew() { awk -v a="$2" -v b="$3" 'BEGIN { exit !(b > a + 0.5) }' && check "$1" yes yes || check "$1" "$2→$3" "advancing"; }
still() { awk -v a="$2" -v b="$3" 'BEGIN { d = b - a; exit !(d < 0.2 && d > -0.2) }' && check "$1" yes yes || check "$1" "$2→$3" "unchanged"; }
away() { "$Q" move 300 650; sleep 0.5; }

echo "Teleprompter E2E (real input)"
"$R" clear; "$R" prompterstop; away
"$R" prompter; sleep 0.8
check "opens expanded" "$(mode)" expanded
check "hidden from capture" "$(pfield sharing)" 0
a=$(pos); sleep 2; b=$(pos); grew "scrolls on its own" "$a" "$b"
away; check "stays open with pointer away" "$(mode)" expanded
"$Q" click 300 650; sleep 0.6; check "stays open after clicking another app" "$(mode)" expanded
"$Q" glide 300 400 735 70 10 10; sleep 0.6
check "pointer over it pauses" "$(pfield hoverPaused)" true
a=$(pos); sleep 1.5; b=$(pos); still "position holds while paused" "$a" "$b"
away; sleep 0.3; check "leaving resumes" "$(pfield hoverPaused)" false
"$Q" key 53; sleep 0.6; check "Escape tucks it away" "$(mode)" compact
a=$(pos)
P=$("$Q" ax Island); "$Q" click ${P% *} 14; sleep 0.7
check "clicking the notch reopens it" "$(mode)" expanded
b=$(pos); awk -v a="$a" -v b="$b" 'BEGIN { exit !(b >= a) }' && check "keeps its place" yes yes || check "keeps its place" "$a→$b" ">= before"
away
"$R" prompterstop; sleep 0.6
check "close returns to idle" "$(mode)" idle
check "capture restored" "$(pfield sharing)" 1
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

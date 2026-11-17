#!/bin/sh
# ============================================================================
#  preview.sh - build a preview cartridge (game modules + a preview driver),
#               run it fullscreen, capture the screen, leave the PNG behind.
#
#  usage: tools/preview.sh tests/p_atlas.lua [seconds]
#
#  Capture lands in /tmp/shot.png (full screen) and /tmp/shot_s.png
#  (downscaled to 1400px wide - the one that gets inspected).
# ============================================================================
set -e

DIR=$(cd "$(dirname "$0")/.." && pwd)
TIC80="/Applications/TIC-80 Pro.app/Contents/MacOS/tic80"
DRIVER=${1:-"$DIR/tests/p_atlas.lua"}
WAIT=${2:-6}

CART="$DIR/build/preview.lua"
mkdir -p "$DIR/build"
sh "$DIR/tools/build.sh" "$CART" > /dev/null
cat "$DRIVER" >> "$CART"
printf '\n' >> "$CART"

pkill -9 -f "MacOS/tic80" 2>/dev/null || true
sleep 1

nohup "$TIC80" "$CART" --skip --volume=0 --fullscreen > "$DIR/build/preview.log" 2>&1 &
sleep "$WAIT"
screencapture -x /tmp/shot.png
sleep 1
pkill -9 -f "MacOS/tic80" 2>/dev/null || true

sips -Z 1400 /tmp/shot.png --out /tmp/shot_s.png > /dev/null 2>&1
echo "captured /tmp/shot_s.png"
echo "--- cart log ---"
cat "$DIR/build/preview.log"

#!/bin/sh
# ============================================================================
#  build.sh - assemble the playable TIC-80 cartridge from src/*.lua
#
#  The cartridge is a single Lua chunk, so the modules are simply concatenated
#  in lexical filename order. Files whose basename starts with "_" (probes,
#  scratch pads) are skipped.
#
#  usage: tools/build.sh [output.lua]
#         default output: ../kage.lua
# ============================================================================
set -e

DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$DIR/kage.lua"}

mkdir -p "$(dirname "$OUT")"
: > "$OUT"

count=0
for f in "$DIR"/src/*.lua; do
    base=$(basename "$f")
    case "$base" in
        _*) continue ;;
    esac
    cat "$f" >> "$OUT"
    printf '\n' >> "$OUT"
    count=$((count + 1))
done

size=$(wc -c < "$OUT" | tr -d ' ')
lines=$(wc -l < "$OUT" | tr -d ' ')
echo "built $OUT  ($count modules, $lines lines, $size bytes)"

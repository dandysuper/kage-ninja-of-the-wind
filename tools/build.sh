#!/bin/sh
# ============================================================================
#  build.sh - assemble the TIC-80 cartridge from src/*.lua
#
#  Modules are concatenated in lexical filename order into one Lua chunk.
#  Files whose basename starts with "_" are skipped (scratch/probes).
#  The playable cart ends with a <PALETTE> section (Pal.base from
#  src/02_pal.lua, both vbanks) so TIC-80's editors show the real colours.
#  TIC-80 ends the code at the first line starting with "-- <", so that
#  section must stay last; --code-only skips it for carts that get more code
#  appended (tools/test.sh).
#
#  usage: tools/build.sh [output.lua] [--code-only]
#         default output: kage.lua (project root)
# ============================================================================
set -e
DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT="$DIR/kage.lua"
CODE_ONLY=0
for a in "$@"; do
  case "$a" in
    --code-only) CODE_ONLY=1 ;;
    *) OUT=$a ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
count=0
for f in "$DIR"/src/*.lua; do
  base=$(basename "$f")
  case "$base" in _*) continue ;; esac
  cat "$f" >> "$OUT"
  printf '\n' >> "$OUT"
  count=$((count + 1))
done
if [ "$CODE_ONLY" -eq 0 ]; then
  PAL=$(sed -n '/^  base = {/,/^  },/p' "$DIR/src/02_pal.lua" | grep -o '0x[0-9a-fA-F]\{6\}' | sed 's/^0x//' | tr -d '\n' | tr 'A-F' 'a-f')
  if [ ${#PAL} -ne 96 ]; then
    echo "build.sh: could not read 16 colours from src/02_pal.lua" >&2
    exit 1
  fi
  printf -- '-- <PALETTE>\n-- 000:%s\n-- 001:%s\n-- </PALETTE>\n' "$PAL" "$PAL" >> "$OUT"
fi
size=$(wc -c < "$OUT" | tr -d ' ')
lines=$(wc -l < "$OUT" | tr -d ' ')
echo "built $OUT ($count modules, $lines lines, $size bytes)"

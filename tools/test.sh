#!/bin/sh
# ============================================================================
#  test.sh - run a test driver headless inside the real TIC-80 (--cli).
#
#  The driver is appended after all game modules, so it shares their chunk and
#  can reach every module table. Drivers report with trace() and must exit().
#  Frames dumped with Test.dump(tag) are converted to PNGs in build/shots/.
#
#  Never pass --volume here: --cli opens no audio device anyway, and TIC-80
#  saves an overridden volume into its options.json on exit, which mutes the
#  windowed emulator from then on.
#
#  usage: tools/test.sh tests/t_smoke.lua [timeout_seconds]
#  exit status: tic80's status, 124 on watchdog timeout, 1 if the log has a
#               Lua error or a "FAIL" line.
# ============================================================================
DIR=$(cd "$(dirname "$0")/.." && pwd)
TIC80=${TIC80:-"/Applications/TIC-80 Pro.app/Contents/MacOS/tic80"}
DRIVER=$1
LIMIT=${2:-90}
[ -f "$DRIVER" ] || { echo "no such driver: $DRIVER" >&2; exit 2; }
NAME=$(basename "$DRIVER" .lua)
CART="$DIR/build/$NAME.cart.lua"
LOG="$DIR/build/$NAME.log"
mkdir -p "$DIR/build/shots"
sh "$DIR/tools/build.sh" "$CART" --code-only > /dev/null || exit 3
cat "$DIR/tests/_harness.lua" "$DRIVER" >> "$CART"
"$TIC80" "$CART" --cli --skip > "$LOG" 2>&1 &
PID=$!
T=0
STATUS=0
while kill -0 "$PID" 2>/dev/null; do
  T=$((T + 1))
  if [ "$T" -ge $((LIMIT * 5)) ]; then
    kill -9 "$PID" 2>/dev/null
    echo "[watchdog] killed after ${LIMIT}s" >> "$LOG"
    STATUS=124
    break
  fi
  sleep 0.2
done
[ "$STATUS" -eq 0 ] && { wait "$PID" 2>/dev/null; STATUS=$?; }
python3 "$DIR/tools/frames.py" "$LOG" "$DIR/build/shots" 3
python3 - "$LOG" <<'EOF'
import sys
s = open(sys.argv[1], errors="replace").read()
out = []
skip = False
for line in s.split("\n"):
    if line.startswith("DUMP-BEGIN"):
        skip = True
        continue
    if line.startswith("DUMP-END"):
        skip = False
        continue
    if not skip:
        out.append(line)
print("\n".join(out)[-6000:])
EOF
if grep -a -q -E "(\[string|error:|attempt to|FAIL)" "$LOG"; then
  [ "$STATUS" -eq 0 ] && STATUS=1
fi
echo "--- $NAME: status $STATUS ---"
exit "$STATUS"

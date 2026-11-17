#!/bin/sh
# ============================================================================
#  test.sh - build a test cartridge (game modules + a test driver) and run it
#             headless, capturing trace() output and Lua errors.
#
#  usage: tools/test.sh tests/t_smoke.lua
#
#  The driver is appended after the game modules, so it shares their chunk and
#  can inspect every internal table. A driver is expected to call exit().
#  A watchdog kills the process if it never exits, so a test can never hang.
#  The TIC-80 process status is returned unchanged on a normal exit. A watchdog
#  timeout is reported as status 124.
# ============================================================================
set -e

DIR=$(cd "$(dirname "$0")/.." && pwd)
TIC80=${TIC80:-"/Applications/TIC-80 Pro.app/Contents/MacOS/tic80"}
DRIVER=${1:-"$DIR/tests/t_smoke.lua"}

if [ ! -f "$DRIVER" ]; then
    echo "no such test driver: $DRIVER" >&2
    exit 2
fi

if [ ! -x "$TIC80" ]; then
    echo "tic80 emulator missing or not executable: $TIC80" >&2
    exit 127
fi

# Keep every generated test artifact in build/; the source driver is input only.
CART="$DIR/build/test_cart.lua"
LOG="$DIR/build/test.log"

mkdir -p "$DIR/build"
sh "$DIR/tools/build.sh" "$CART" > /dev/null
cat "$DRIVER" >> "$CART"
printf '\n' >> "$CART"

: > "$LOG"
"$TIC80" "$CART" --cli --skip --volume=0 >> "$LOG" 2>&1 &
PID=$!

SECS=0
TIMED_OUT=0
while kill -0 "$PID" 2>/dev/null; do
    SECS=$((SECS + 1))
    if [ "$SECS" -ge 60 ]; then
        TIMED_OUT=1
        echo "[watchdog] killed test after 60s (cart did not exit)" >> "$LOG"
        if kill -9 "$PID" 2>/dev/null; then
            :
        else
            echo "[watchdog] process exited before SIGKILL" >> "$LOG"
        fi
        break
    fi
    sleep 1
done

# `wait` is deliberately conditional: a non-zero emulator status is data, not
# a shell failure that should prevent the captured log from being printed.
if wait "$PID" 2>/dev/null; then
    STATUS=0
else
    STATUS=$?
fi
if [ "$TIMED_OUT" -ne 0 ]; then
    STATUS=124
fi

echo "--- test: $(basename "$DRIVER") ---"
cat "$LOG"
echo "--- end (status $STATUS) ---"
exit "$STATUS"

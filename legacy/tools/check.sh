#!/bin/sh
# ============================================================================
#  check.sh - build the cartridge and run the headless regression drivers.
#
#  Drivers run in dependency order. The first non-zero driver status stops the
#  run and is returned to the caller. All test carts/logs are kept in build/.
# ============================================================================
set -eu

DIR=$(cd "$(dirname "$0")/.." && pwd)
TIC80=${TIC80:-"/Applications/TIC-80 Pro.app/Contents/MacOS/tic80"}
KAGE="$DIR/kage.lua"

if [ ! -x "$TIC80" ]; then
    echo "CHECK FAIL: tic80 emulator missing or not executable: $TIC80" >&2
    exit 127
fi

mkdir -p "$DIR/build"
echo "== build kage.lua =="
if sh "$DIR/tools/build.sh" "$KAGE"; then
    :
else
    status=$?
    echo "CHECK FAIL: build (exit $status)" >&2
    exit "$status"
fi

DRIVERS="t_smoke.lua t_world.lua t_tiles.lua t_player.lua t_game.lua qa_tic_api.lua"
for driver in $DRIVERS; do
    path="$DIR/tests/$driver"
    if [ ! -f "$path" ]; then
        echo "CHECK FAIL: missing test driver: $path" >&2
        exit 2
    fi

    echo "== $driver =="
    if sh "$DIR/tools/test.sh" "$path"; then
        :
    else
        status=$?
        echo "CHECK FAIL: $driver (exit $status)" >&2
        exit "$status"
    fi
done

echo "CHECK PASS"

#!/bin/sh
# ============================================================================
#  ppm.sh - reassemble a framebuffer PPM dump from a p_verify test log into a
#           PNG for visual inspection.
#
#  usage: tools/ppm.sh [log] [out.png]
#         defaults: build/test.log -> build/frame.png
# ============================================================================
set -e

DIR=$(cd "$(dirname "$0")/.." && pwd)
LOG=${1:-"$DIR/build/test.log"}
OUT=${2:-"$DIR/build/frame.png"}
PPM="$DIR/build/frame.ppm"

python3 - "$LOG" "$OUT" <<'EOF'
import sys, re

log, out = sys.argv[1], sys.argv[2]
with open(log) as f:
    text = f.read()
m = re.search(r"PPM-BEGIN \S+?([0-9a-f]{100,})PPM-END", text)
rows = []
if m:
    blob = m.group(1)
    rowlen = 240 * 6
    rows = [blob[i:i + rowlen] for i in range(0, len(blob), rowlen)]

if not rows:
    print("no PPM dump found in " + log)
    sys.exit(1)

w, h = 240, 136
data = bytearray()
for row in rows[:h]:
    for i in range(0, w * 6, 6):
        data += bytes.fromhex(row[i:i + 6])

try:
    from PIL import Image
    img = Image.frombytes("RGB", (w, h), bytes(data))
    img = img.resize((w * 3, h * 3), Image.NEAREST)
    img.save(out)
    print("wrote " + out)
except ImportError:
    ppm = out.replace(".png", ".ppm")
    with open(ppm, "wb") as f:
        f.write(b"P6\n%d %d\n255\n" % (w, h))
        f.write(bytes(data))
    print("PIL missing; wrote " + ppm)
EOF

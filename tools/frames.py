"""Convert framebuffer dumps (Test.dump in tests/_harness.lua) from a log to PNGs.

Dump format, one item per line:
  DUMP-BEGIN <tag>
  PAL0 <96 hex>      vbank 0 palette
  PAL1 <96 hex>      vbank 1 palette
  <136 rows of 240 chars>  '0'-'f' = vbank0 colour, 'g'-'v' = vbank1 colour
  DUMP-END
usage: frames.py <log> <outdir> [scale]
"""
import os
import re
import sys

from PIL import Image


def pal(hexs):
    return [tuple(int(hexs[i * 6 + j * 2:i * 6 + j * 2 + 2], 16) for j in range(3)) for i in range(16)]


def main():
    log, outdir = sys.argv[1], sys.argv[2]
    scale = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    text = open(log, errors="replace").read()
    pat = re.compile(r"DUMP-BEGIN (\S+)\nPAL0 ([0-9a-f]{96})\nPAL1 ([0-9a-f]{96})\n((?:[0-9a-v]{240}\n){136})DUMP-END")
    os.makedirs(outdir, exist_ok=True)
    for tag, p0, p1, rows in pat.findall(text):
        c0, c1 = pal(p0), pal(p1)
        img = Image.new("RGB", (240, 136))
        px = img.load()
        for y, row in enumerate(rows.strip().split("\n")):
            for x, ch in enumerate(row):
                v = int(ch, 32)
                px[x, y] = c0[v] if v < 16 else c1[v - 16]
        if scale != 1:
            img = img.resize((240 * scale, 136 * scale), Image.NEAREST)
        out = os.path.join(outdir, tag + ".png")
        img.save(out)
        print("shot", out)


if __name__ == "__main__":
    main()

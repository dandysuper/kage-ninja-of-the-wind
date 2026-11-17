"""Build the itch.io page images from the shot_itch driver log.

  sh tools/test.sh tests/shot_itch.lua 600   # stages the scenes -> build/shot_itch.log
  python3 tools/itch_art.py                  # -> itch/*.png

Screenshots are real frames (HUD included) scaled 4x with nearest neighbour.
The cover (630x500, itch.io's 315:250 ratio) and the page banner (960x300,
the page column's default width) are drawn at 2x: a stitched dusk panorama
of the world, the title in the game's own font and the gliding ninja sprite
at 4x. The page background (2560x1440) is a dimmed 4x panorama that dithers
out into the page colour at its edges.
"""
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(ROOT, "build", "shot_itch.log")
OUT = os.path.join(ROOT, "itch")

# store screenshots in upload order: dump tag -> file name
SCREENSHOTS = [
    ("itch_village", "01-hanamura-village"),
    ("itch_shuten_fire36_0096", "02-boss-oni-king"),
    ("itch_night_12", "03-night-survival"),
    ("itch_glide_24", "04-kite-glide"),
    ("itch_haunted", "05-haunted-wood"),
    ("itch_tengulord_volley40_0310", "06-boss-tengu-lord"),
    ("itch_climb_036", "07-climb-pagoda"),
    ("itch_craft", "08-crafting"),
    ("itch_map", "09-world-map"),
]
SHOT_SCALE = 4

DUMP = re.compile(r"DUMP-BEGIN (\S+)\nPAL0 ([0-9a-f]{96})\nPAL1 ([0-9a-f]{96})\n((?:[0-9a-v]{240}\n){136})DUMP-END")
SPRITE = re.compile(r"SPRITE (\S+) (\d+) (\d+) (\d+) (\d+)")

# palette indices (C_* in src/02_pal.lua)
INK, NIGHT, TAN, CREAM, WHITE, RED, PINK, GOLD = 0, 1, 10, 11, 12, 13, 14, 15
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def palette(hexs):
    return [tuple(int(hexs[i * 6 + j * 2:i * 6 + j * 2 + 2], 16) for j in range(3)) for i in range(16)]


def load(log):
    text = open(log, errors="replace").read()
    dumps = {tag: (palette(p0), palette(p1), rows.split()) for tag, p0, p1, rows in DUMP.findall(text)}
    sprites = {m[0]: tuple(int(v) for v in m[1:]) for m in SPRITE.findall(text)}
    return dumps, sprites


def frame(dump):
    """A dump as an RGB image (both video banks)."""
    p0, p1, rows = dump
    img = Image.new("RGB", (240, 136))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            v = int(ch, 32)
            px[x, y] = p0[v] if v < 16 else p1[v - 16]
    return img


def overlay(dump, box):
    """Only what was drawn on video bank 1 inside box, as RGBA."""
    x0, y0, w, h = box
    p1, rows = dump[1], dump[2]
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            v = int(rows[y0 + y][x0 + x], 32)
            if v >= 16:
                px[x, y] = p1[v - 16] + (255,)
    return img


def stitch(dumps, name):
    tiles = sorted(t for t in dumps if t.startswith("art_%s_" % name))
    rows = 1 + max(int(t.split("_")[-2]) for t in tiles)
    cols = 1 + max(int(t.split("_")[-1]) for t in tiles)
    pano = Image.new("RGB", (cols * 240, rows * 136))
    for r in range(rows):
        for c in range(cols):
            pano.paste(frame(dumps["art_%s_%d_%d" % (name, r, c)]), (c * 240, r * 136))
    return pano


def glyphs(dump, box, scale):
    """Text printed at `scale` on bank 1 -> 1x bitmap (set of (x, y))."""
    x0, y0, w, h = box
    rows = dump[2]
    pts = set()
    for y in range(0, h, scale):
        for x in range(0, w, scale):
            if int(rows[y0 + y][x0 + x], 32) >= 16:
                pts.add((x // scale, y // scale))
    return pts


def grow(pts, r):
    out = set()
    for x, y in pts:
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                out.add((x + dx, y + dy))
    return out


def scaled(pts, s):
    return {(x * s + i, y * s + j) for x, y in pts for i in range(s) for j in range(s)}


def plot(img, pts, color, ox, oy):
    px = img.load()
    w, h = img.size
    for x, y in pts:
        if 0 <= x + ox < w and 0 <= y + oy < h:
            px[x + ox, y + oy] = color


def panel(img, pal, x, y, w, h):
    """The game's UI panel: night fill, tan frame, cut corners."""
    px = img.load()
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            edge = xx in (x, x + w - 1) or yy in (y, y + h - 1)
            corner = xx in (x, x + w - 1) and yy in (y, y + h - 1)
            if not corner:
                px[xx, yy] = pal[TAN] if edge else pal[NIGHT]


def title(img, text, cx, top, s):
    """KAGE in the game's font at s x with the title screen's red underside and
    shadow plus a dark outline; the subtitle in gold on a game-style panel."""
    pal = text[1]
    logo = glyphs(text, (8, 8, 200, 56), 8)
    sub = glyphs(text, (8, 100, 100, 8), 1)
    big = scaled(logo, s)
    lw = (max(x for x, _ in logo) + 1) * s
    lh = (max(y for _, y in logo) + 1) * s
    lx = cx - lw // 2
    plot(img, grow(big, 3), pal[INK], lx + 3, top + 4)
    plot(img, grow(big, 2), pal[INK], lx, top)
    plot(img, big, pal[RED], lx, top + 2)
    plot(img, big, pal[WHITE], lx, top)
    lower = {(x, y) for x, y in big if y % s >= s - 2 and (x, y + 1) not in big}
    plot(img, lower, pal[CREAM], lx, top)
    sw = (max(x for x, _ in sub) + 1) * 2
    sh = (max(y for _, y in sub) + 1) * 2
    sy = top + lh + 12
    sx = cx - sw // 2
    panel(img, pal, sx - 9, sy - 5, sw + 18, sh + 10)
    small = scaled(sub, 2)
    plot(img, small, pal[NIGHT], sx + 1, sy + 1)
    plot(img, small, pal[GOLD], sx, sy)


def hero(img, dumps, sprites, name, x, y, s, flip=False):
    sx, sy, w, h = sprites[name]
    spr = overlay(dumps["art_sprites"], (sx, sy, w, h))
    if flip:
        spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
    spr = spr.resize((w * s, h * s), Image.NEAREST)
    img.paste(spr, (x, y), spr)


WIND = [(0, 34, 0), (5, 18, 12), (44, 26, 6), (52, 12, 20), (66, 22, 2)]


def streaks(img, pal, x, y, lines, back=1):
    """Wind lines trailing behind the glider (back=1: to the left, -1: to the
    right): (dy, length, gap) each."""
    px = img.load()
    for dy, length, gap in lines:
        for k in range(length):
            xx = x - back * (gap + k)
            if 0 <= xx < img.size[0] and (k < length * 2 // 3 or k % 2 == 0):
                px[xx, y + dy] = pal[WHITE] if k < length // 3 else pal[CREAM]


def petals(img, pal, at, s):
    """Sakura petals at s x: (x, y, flip) each."""
    shape = [(0, 0, PINK), (1, 0, PINK), (1, 1, WHITE), (2, 1, PINK)]
    for x, y, flip in at:
        for dx, dy, c in shape:
            px = (2 - dx) if flip else dx
            for i in range(s):
                for j in range(s):
                    xx, yy = x + px * s + i, y + dy * s + j
                    if 0 <= xx < img.size[0] and 0 <= yy < img.size[1]:
                        img.putpixel((xx, yy), pal[c])


def cover(dumps, sprites, out):
    """Hanamura at dusk, the gliding ninja riding the wind, the title on top."""
    pal = dumps["art_text"][1]
    img = stitch(dumps, "hanamura").crop((70, 70, 70 + 315, 70 + 250))
    hx, hy = 40, 100
    streaks(img, pal, hx - 3, hy + 6, WIND)
    hero(img, dumps, sprites, "n_glide", hx, hy, 4)
    petals(img, pal, [(hx + 96, hy + 22, False), (hx + 120, hy + 70, True), (hx - 22, hy + 88, False),
                      (hx + 70, hy + 104, True), (250, 140, False), (12, 150, True)], 2)
    title(img, dumps["art_text"], 157, 10, 7)
    img.resize((630, 500), Image.NEAREST).save(out)
    return out


def banner(dumps, sprites, out):
    """Kyo Castle between the snowy Fuyu foothills and the plains, the title
    on the snow, the ninja gliding in from the right."""
    pal = dumps["art_text"][1]
    img = stitch(dumps, "kyo").crop((60, 40, 60 + 480, 40 + 150))
    hx, hy = 350, 40
    streaks(img, pal, hx + 82, hy + 6, WIND, back=-1)
    hero(img, dumps, sprites, "n_glide", hx, hy, 4, flip=True)
    petals(img, pal, [(hx - 26, hy + 30, True), (hx + 40, hy + 92, False), (300, 120, True), (250, 20, False)], 2)
    title(img, dumps["art_text"], 130, 22, 7)
    img.resize((960, 300), Image.NEAREST).save(out)
    return out


def background(dumps, out):
    """Sakura Vale at dusk, dimmed, dithering out into the ink colour at the
    left, right and bottom edges so wider or taller windows blend in."""
    img = stitch(dumps, "vale").crop((40, 0, 40 + 640, 360))
    ink = dumps["art_text"][1][INK]
    px = img.load()
    w, h = img.size
    fade = 40
    for y in range(h):
        for x in range(w):
            d = min(x, w - 1 - x, h - 1 - y)
            if min(1, d / fade) * 16 <= BAYER[y % 4][x % 4]:
                px[x, y] = ink
            else:
                r, g, b = px[x, y]
                px[x, y] = (r * 3 // 5, g * 3 // 5, b * 3 // 5)
    img.resize((2560, 1440), Image.NEAREST).save(out)
    return out


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else LOG
    dumps, sprites = load(log)
    os.makedirs(os.path.join(OUT, "2-screenshots"), exist_ok=True)
    print(cover(dumps, sprites, os.path.join(OUT, "1-cover.png")))
    print(banner(dumps, sprites, os.path.join(OUT, "7-banner.png")))
    print(background(dumps, os.path.join(OUT, "8-background.png")))
    for tag, name in SCREENSHOTS:
        img = frame(dumps[tag]).resize((240 * SHOT_SCALE, 136 * SHOT_SCALE), Image.NEAREST)
        path = os.path.join(OUT, "2-screenshots", name + ".png")
        img.save(path)
        print(path)


if __name__ == "__main__":
    main()

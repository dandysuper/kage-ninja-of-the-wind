-- title:   KAGE - Ninja of the Wind
-- author:  dandimo
-- desc:    2.5D open-world ninja survival RPG. Explore feudal Japan, jump, climb, glide, craft, cook, and reclaim the Three Sacred Treasures.
-- site:    https://tic80.com
-- license: MIT License
-- version: 2.0
-- script:  lua
--
-- ============================================================================
--  KAGE - Ninja of the Wind  (TIC-80 Pro 1.3 / Lua 5.3)
--
--  A Don't Starve x Breath of the Wild style open world, rendered as a real
--  2.5D scene: a rotatable isometric camera, z-buffered textured triangles
--  (ttri) for terrain cliffs and 3D buildings, billboarded sprites, shadows,
--  day/night with DS-style darkness, and a HUD on VRAM bank 1.
--
--  CONTROLS (keyboard)
--    Arrows ......... move            SHIFT / C ...... sprint (stamina)
--    X .............. jump / hold to glide (kite)  / climb-leap
--    Z .............. katana (combo) / chop / mine / plunge in mid-air
--    A .............. interact: talk, pick up, open, cook, rest
--    S .............. throw shuriken
--    Q / E .......... rotate camera
--    TAB or I ....... inventory + crafting      M ...... map
--    J .............. quest journal             1-0 .... use hotbar slot
--
--  Source: tools/build.sh concatenates src/*.lua (lexical order) into
--  kage.lua. See HANDOFF.md for the architecture and the test harness.
-- ============================================================================

-- ============================================================================
--  01 CORE - math, hashing/noise, input, small utilities
--  Chunk-level locals are kept few (Lua allows 200 per function and the whole
--  cart is one chunk); modules expose tables instead.
-- ============================================================================
local flr, ceil, abs, sqrt = math.floor, math.ceil, math.abs, math.sqrt
local sin, cos, atan, min, max = math.sin, math.cos, math.atan, math.min, math.max
local PI, TAU = math.pi, math.pi * 2
local rnd = math.random
local fmt = string.format

function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function lerp(a, b, t) return a + (b - a) * t end
function sgn(v) if v > 0 then return 1 elseif v < 0 then return -1 end return 0 end
function approach(v, t, d) if v < t then return min(v + d, t) end return max(v - d, t) end
function angdiff(a, b) local d = (b - a) % TAU if d > PI then d = d - TAU end return d end
function dist2(ax, ay, bx, by) local dx, dy = bx - ax, by - ay return dx * dx + dy * dy end
function dist(ax, ay, bx, by) local dx, dy = bx - ax, by - ay return sqrt(dx * dx + dy * dy) end
function rndf(a, b) return a + rnd() * (b - a) end
function pick(t) return t[rnd(#t)] end
function chance(p) return rnd() < p end

-- deterministic integer hash -> [0,1)
function hash2(x, y, s)
  local h = (flr(x) * 374761393 + flr(y) * 668265263 + flr(s or 0) * 1442695041) & 0xffffffff
  h = ((h ~ (h >> 13)) * 1274126177) & 0xffffffff
  h = h ~ (h >> 16)
  return (h & 0xffffff) / 16777216
end

function vnoise(x, y, s)
  local xi, yi = flr(x), flr(y)
  local xf, yf = x - xi, y - yi
  local u, v = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
  local a, b = hash2(xi, yi, s), hash2(xi + 1, yi, s)
  local c, d = hash2(xi, yi + 1, s), hash2(xi + 1, yi + 1, s)
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
end

function fbm(x, y, s, oct)
  local t, amp, f, n = 0, 1, 1, 0
  for i = 1, oct do
    t = t + vnoise(x * f, y * f, s + i * 31) * amp
    n = n + amp
    amp = amp * 0.5
    f = f * 2
  end
  return t / n
end

-- ---------------------------------------------------------------------------
-- Input: logical actions built from gamepad buttons + keyboard keys.
-- In.h[a] held, In.p[a] pressed this frame. Tests set In.fake = {a=true...}.
-- ---------------------------------------------------------------------------
In = { h = {}, p = {}, fake = nil, any = false }
local ACTIONS = {
  up = { b = 0, k = { 58 } }, down = { b = 1, k = { 59 } },
  left = { b = 2, k = { 60 } }, right = { b = 3, k = { 61 } },
  atk = { b = 4 }, jump = { b = 5 }, use = { b = 6 }, throw = { b = 7 },
  run = { k = { 64, 3 } }, rotl = { k = { 17 } }, rotr = { k = { 5 } },
  menu = { k = { 49, 9 } }, map = { k = { 13 } }, quest = { k = { 10 } },
  ok = { k = { 50, 48 } },
  s1 = { k = { 28 } }, s2 = { k = { 29 } }, s3 = { k = { 30 } }, s4 = { k = { 31 } },
  s5 = { k = { 32 } }, s6 = { k = { 33 } }, s7 = { k = { 34 } }, s8 = { k = { 35 } },
  s9 = { k = { 36 } }, s10 = { k = { 27 } },
}
In.names = {}
for n in pairs(ACTIONS) do In.names[#In.names + 1] = n end
table.sort(In.names)

function In.poll()
  local f, h, p = In.fake, In.h, In.p
  local any = false
  for i = 1, #In.names do
    local n = In.names[i]
    local v = false
    if f then
      v = f[n] and true or false
    else
      local d = ACTIONS[n]
      if d.b and btn(d.b) then v = true end
      if not v and d.k then
        for j = 1, #d.k do if key(d.k[j]) then v = true break end end
      end
    end
    p[n] = v and not h[n]
    h[n] = v
    if p[n] then any = true end
  end
  In.any = any
end

-- direction from arrows, screen space (-1..1)
function In.axis()
  local h = In.h
  local x = (h.right and 1 or 0) - (h.left and 1 or 0)
  local y = (h.down and 1 or 0) - (h.up and 1 or 0)
  return x, y
end

-- ---------------------------------------------------------------------------
-- Misc
-- ---------------------------------------------------------------------------
Frame = 0
function wrapText(s, w)
  -- greedy wrap for the 6px system font (approx 6px/char, 5 for small)
  local lines, line = {}, ""
  for word in s:gmatch("%S+") do
    local test = line == "" and word or (line .. " " .. word)
    if #test * 6 > w and line ~= "" then
      lines[#lines + 1] = line
      line = word
    else
      line = test
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

-- ============================================================================
--  02 PALETTE - 16 colours (feudal Japan woodblock), day/night tint for
--  VRAM bank 0, palette-map helpers used to recolour sprites per draw call
--  (the palette map at 0x3FF0 is applied by spr/ttri at draw time).
-- ============================================================================
C_INK, C_NIGHT, C_INDIGO, C_BLUE, C_GRAY, C_DKGRN, C_GREEN, C_LIME = 0, 1, 2, 3, 4, 5, 6, 7
C_BROWN, C_WOOD, C_TAN, C_CREAM, C_WHITE, C_RED, C_PINK, C_GOLD = 8, 9, 10, 11, 12, 13, 14, 15

Pal = {
  base = {
    0x0d0b14, 0x25213b, 0x3d4377, 0x3f7cbf, 0x8288a0, 0x1f4d3a, 0x3e8c43, 0x9fd25c,
    0x5c3a2d, 0x9b6541, 0xd6a76c, 0xf3e3c3, 0xfbf8f0, 0xcc3340, 0xf39cb6, 0xf4c94e,
  },
  tint = { 1, 1, 1 }, -- current multiplier for bank 0
  map = {},
}

local function palWrite(t)
  for i = 0, 15 do
    local c = Pal.base[i + 1]
    local r, g, b = (c >> 16) & 255, (c >> 8) & 255, c & 255
    if t then
      r = math.min(255, math.floor(r * t[1]))
      g = math.min(255, math.floor(g * t[2]))
      b = math.min(255, math.floor(b * t[3]))
    end
    poke(0x3FC0 + i * 3, r)
    poke(0x3FC0 + i * 3 + 1, g)
    poke(0x3FC0 + i * 3 + 2, b)
  end
end

function Pal.apply()
  vbank(1) palWrite(nil)
  vbank(0) palWrite(Pal.tint)
end

-- tint bank 0 only (the world); HUD on bank 1 stays true-colour
function Pal.setTint(r, g, b)
  local t = Pal.tint
  if math.abs(t[1] - r) + math.abs(t[2] - g) + math.abs(t[3] - b) < 0.004 then return end
  t[1], t[2], t[3] = r, g, b
  vbank(0) palWrite(t)
end

-- palette map: colour i drawn as m[i] (m is a 0-based table of 16 entries)
function Pal.remap(m)
  for i = 0, 15 do poke4(0x7FE0 + i, m[i] or i) end
end
function Pal.reset()
  for i = 0, 15 do poke4(0x7FE0 + i, i) end
end
function Pal.solid(c)
  for i = 0, 15 do poke4(0x7FE0 + i, c) end
end
-- build a remap from pairs: Pal.mk{[from]=to,...}
function Pal.mk(t)
  local m = {}
  for i = 0, 15 do m[i] = t[i] or i end
  return m
end

-- ============================================================================
--  03 GFX - sprite-sheet painting and a texture atlas.
--
--  ttri() treats the tile+sprite banks as one 128x256 texture (u=x, v=y), so
--  billboards do not need 8x8 alignment. Map tiles (ground + wall textures)
--  live in tiles 0..127 (y 0..63); every other sprite is packed by a skyline
--  packer into y 64..255 and addressed by name: SPR[name] = {u,v,w,h}.
-- ============================================================================
Gfx = { sky = {} }
SPR = {}

function sset(x, y, c)
  poke4(0x8000 + ((y >> 3) * 16 + (x >> 3)) * 64 + (y & 7) * 8 + (x & 7), c)
end
function sget(x, y)
  return peek4(0x8000 + ((y >> 3) * 16 + (x >> 3)) * 64 + (y & 7) * 8 + (x & 7))
end

-- paint one 8x8 map tile from fn(x,y)->colour
function Gfx.tile(id, fn)
  local bx, by = (id % 16) * 8, (id // 16) * 8
  for y = 0, 7 do
    for x = 0, 7 do sset(bx + x, by + y, fn(x, y) or 0) end
  end
end

-- skyline packer over the sprite region
local SKY_TOP = 64
for i = 0, 127 do Gfx.sky[i] = SKY_TOP end

function Gfx.alloc(w, h)
  local sky = Gfx.sky
  local bestx, besty = -1, 1e9
  for x = 0, 128 - w do
    local y = 0
    for k = x, x + w - 1 do if sky[k] > y then y = sky[k] end end
    if y < besty then besty, bestx = y, x end
  end
  if bestx < 0 or besty + h > 256 then
    trace("ATLAS FULL for " .. w .. "x" .. h .. "\n")
    return 0, 0
  end
  for k = bestx, bestx + w - 1 do sky[k] = besty + h end
  return bestx, besty
end

-- parse an art string: rows separated by newlines or '|'; '.'=0, hex digit=colour
function Gfx.parse(s)
  local rows = {}
  for line in s:gmatch("[^\n|]+") do
    line = line:gsub("%s", "")
    if #line > 0 then rows[#rows + 1] = line end
  end
  return rows
end

-- sprites are queued, then packed tallest-first by Gfx.flush() (dense packing)
Gfx.queue = {}
function Gfx.add(name, art)
  local rows = type(art) == "string" and Gfx.parse(art) or art
  local h, w = #rows, 0
  for i = 1, h do if #rows[i] > w then w = #rows[i] end end
  Gfx.queue[#Gfx.queue + 1] = { name = name, w = w, h = h, rows = rows }
end

function Gfx.addfn(name, w, h, fn)
  Gfx.queue[#Gfx.queue + 1] = { name = name, w = w, h = h, fn = fn }
end

function Gfx.flush()
  local q = Gfx.queue
  table.sort(q, function(a, b)
    if a.h ~= b.h then return a.h > b.h end
    if a.w ~= b.w then return a.w > b.w end
    return a.name < b.name
  end)
  for _, s in ipairs(q) do
    local u, v = Gfx.alloc(s.w, s.h)
    if s.rows then
      for y = 1, s.h do
        local r = s.rows[y]
        for x = 1, #r do
          local ch = r:sub(x, x)
          sset(u + x - 1, v + y - 1, ch == "." and 0 or (tonumber(ch, 16) or 0))
        end
      end
    else
      for y = 0, s.h - 1 do
        for x = 0, s.w - 1 do sset(u + x, v + y, s.fn(x, y) or 0) end
      end
    end
    SPR[s.name] = { u, v, s.w, s.h }
  end
  Gfx.queue = {}
end

-- 8x8 icons go into unused map-tile slots first (saves sprite-region space)
Gfx.freeTiles = {}
for id = 30, 39 do Gfx.freeTiles[#Gfx.freeTiles + 1] = id end
for id = 69, 127 do Gfx.freeTiles[#Gfx.freeTiles + 1] = id end
function Gfx.icon(name, art)
  local rows = Gfx.parse(art)
  local id = table.remove(Gfx.freeTiles, 1)
  if not id then return Gfx.add(name, rows) end
  local u, v = (id % 16) * 8, (id // 16) * 8
  for y = 1, 8 do
    local r = rows[y] or ""
    for x = 1, 8 do
      local ch = r:sub(x, x)
      sset(u + x - 1, v + y - 1, (ch == "" or ch == ".") and 0 or (tonumber(ch, 16) or 0))
    end
  end
  SPR[name] = { u, v, 8, 8 }
end

-- row-array helpers for composing art
function Gfx.rows(s) return Gfx.parse(s) end
function Gfx.stack(a, b)
  local r = {}
  for i = 1, #a do r[#r + 1] = a[i] end
  for i = 1, #b do r[#r + 1] = b[i] end
  return r
end
function Gfx.mirror(rows)
  local r = {}
  for i = 1, #rows do r[i] = rows[i]:reverse() end
  return r
end

-- blit a sheet rect to the screen (no depth), optional flip and scale
function blit(rect, x, y, flip, sc)
  sc = sc or 1
  local u, v, w, h = rect[1], rect[2], rect[3], rect[4]
  local x1, y1 = x + w * sc, y + h * sc
  local u0, u1 = u, u + w
  if flip then u0, u1 = u1, u0 end
  ttri(x, y, x1, y, x, y1, u0, v, u1, v, u0, v + h, 0, 0)
  ttri(x1, y, x1, y1, x, y1, u1, v, u1, v + h, u0, v + h, 0, 0)
end

-- ============================================================================
--  04 TILES - procedural 8x8 ground textures (map tiles) and the wall/cliff
--  texture bands that live in map rows 112..135 (the "atlas"). Side faces of
--  terrain and buildings sample those rows with ttri(texsrc=1).
--  Pixel (4,4) of every ground tile is its representative colour: the world
--  map is drawn by sampling the map texture at 1px per cell.
-- ============================================================================
T = {
  OCEAN = 0, WATER = 1, SHALLOW = 2, GRASS1 = 3, GRASS2 = 4, GRASS3 = 5, FLOWERS = 6,
  SAKURA = 7, FOREST = 8, BAMBOO = 9, DIRT = 10, STONE = 11, PLAZA = 12, SAND = 13,
  SNOW1 = 14, SNOW2 = 15, ROCK = 16, GRAVEL = 17, WOOD = 18, PADDY = 19, MARSH = 20,
  HAUNT = 21, ASH = 22, LAVA = 23, FARM = 24, MOSS = 25, DARKWOOD = 26, ROOF = 27,
  SNOWPATH = 28, MAPLE = 29,
}
-- wall/cliff bands: first map row, rows, the colour used for its "lip"
BAND = {
  EARTH = { row = 112, n = 4 }, ROCK = { row = 116, n = 4 }, SAND = { row = 120, n = 1 },
  STONE = { row = 121, n = 2 }, HOUSE = { row = 123, n = 3 }, PLASTER = { row = 126, n = 2 },
  ROOF = { row = 128, n = 2 }, WOOD = { row = 130, n = 1 }, RED = { row = 131, n = 1 },
  THATCH = { row = 132, n = 2 }, DARK = { row = 134, n = 1 },
}
for _, b in pairs(BAND) do b.v = b.row * 8 b.h = b.n * 8 end

local function H(x, y, s) return hash2(x, y, s) end

-- generic speckle texture: base colour + list of {colour, probability}
local function speck(seed, base, specks)
  return function(x, y)
    local r = H(x, y, seed)
    local acc = 0
    for i = 1, #specks do
      acc = acc + specks[i][2]
      if r < acc then return specks[i][1] end
    end
    return base
  end
end

local function grass(seed, extra)
  return function(x, y)
    local r = H(x, y, seed)
    local up = H(x, (y + 7) % 8, seed)
    if extra then
      local e = H(x, y, seed + 99)
      if e < extra[2] then return extra[1] end
    end
    if r < 0.10 then return C_LIME end
    if up < 0.10 then return C_DKGRN end
    if r > 0.93 then return C_DKGRN end
    return C_GREEN
  end
end

local function water(seed, base, wave, glint, ph)
  return function(x, y)
    local xx = (x + ph) % 8
    if (y == 1 and xx >= 1 and xx <= 3) or (y == 5 and xx >= 5) or (y == 5 and xx == 0) then return wave end
    if (y == 2 and (xx == 0 or xx == 4)) or (y == 6 and (xx == 4 or xx == 1)) then return base end
    if H(x, y, seed + ph) < 0.025 then return glint end
    return base
  end
end

function Gfx.paintTiles()
  local t = Gfx.tile
  -- animated liquids are repainted in place every few frames (Gfx.animTiles)
  Gfx.liquid = {
    { T.OCEAN, function(f) return water(11, C_INDIGO, C_BLUE, C_GRAY, f * 2) end, C_INDIGO },
    { T.WATER, function(f) return water(12, C_BLUE, C_INDIGO, C_WHITE, f * 2) end, C_BLUE },
    { T.SHALLOW, function(f)
      return function(x, y)
        local xx = (x + f * 2) % 8
        if (y == 2 and xx < 3) or (y == 6 and xx >= 4 and xx < 7) then return C_WHITE end
        if H(x, y, 13) < 0.12 then return C_TAN end
        return C_BLUE
      end
    end, C_BLUE },
    { T.LAVA, function(f)
      return function(x, y)
        local n = (H(x, y, 14) + f * 0.25) % 1
        if n < 0.15 then return C_GOLD end
        if n < 0.45 then return C_RED end
        if H(x, y, 15) < 0.15 then return C_BROWN end
        return C_RED
      end
    end, C_RED },
  }
  for _, l in ipairs(Gfx.liquid) do t(l[1], l[2](0)) end
  t(T.GRASS1, grass(21))
  t(T.GRASS2, grass(22))
  t(T.GRASS3, grass(23, { C_GOLD, 0.02 }))
  t(T.FLOWERS, function(x, y)
    local r = H(x, y, 24)
    if r < 0.06 then return C_PINK elseif r < 0.10 then return C_WHITE elseif r < 0.13 then return C_GOLD end
    return grass(25)(x, y)
  end)
  t(T.SAKURA, function(x, y)
    local r = H(x, y, 26)
    if r < 0.16 then return C_PINK elseif r < 0.19 then return C_WHITE end
    return grass(27)(x, y)
  end)
  t(T.FOREST, speck(28, C_DKGRN, { { C_GREEN, 0.12 }, { C_BROWN, 0.10 }, { C_NIGHT, 0.04 } }))
  t(T.BAMBOO, speck(29, C_GREEN, { { C_LIME, 0.14 }, { C_TAN, 0.10 }, { C_DKGRN, 0.10 } }))
  t(T.DIRT, speck(30, C_WOOD, { { C_BROWN, 0.16 }, { C_TAN, 0.10 } }))
  t(T.STONE, function(x, y)
    local ox = (y >= 4) and 2 or 0
    local xx = (x + ox) % 4
    if y % 4 == 3 or xx == 3 then return C_INDIGO end
    if y % 4 == 0 and xx == 0 then return C_WHITE end
    if H(x, y, 31) < 0.15 then return C_CREAM end
    return C_GRAY
  end)
  t(T.PLAZA, function(x, y)
    if y == 7 or x == 7 then return C_INDIGO end
    if y == 0 or x == 0 then return C_CREAM end
    if H(x, y, 32) < 0.1 then return C_WHITE end
    return C_GRAY
  end)
  t(T.SAND, speck(33, C_TAN, { { C_CREAM, 0.16 }, { C_WOOD, 0.08 } }))
  t(T.SNOW1, speck(34, C_WHITE, { { C_CREAM, 0.14 }, { C_GRAY, 0.03 } }))
  t(T.SNOW2, speck(35, C_WHITE, { { C_CREAM, 0.08 }, { C_GRAY, 0.06 } }))
  t(T.ROCK, function(x, y)
    local r = H(x, y, 36)
    if (x + y * 3) % 7 == 0 and r < 0.6 then return C_INDIGO end
    if r < 0.12 then return C_WHITE end
    if r > 0.9 then return C_NIGHT end
    return C_GRAY
  end)
  t(T.GRAVEL, function(x, y)
    if y % 3 == 1 then return C_GRAY end
    if H(x, y, 37) < 0.1 then return C_TAN end
    return C_CREAM
  end)
  t(T.WOOD, function(x, y)
    if y % 4 == 3 then return C_BROWN end
    local seam = ((y // 4) % 2 == 0) and 2 or 6
    if x == seam then return C_BROWN end
    if H(x, y, 38) < 0.12 then return C_TAN end
    return C_WOOD
  end)
  t(T.PADDY, function(x, y)
    if x % 3 == 1 and (y % 4 == 1 or y % 4 == 2) then return y % 4 == 1 and C_LIME or C_GREEN end
    if H(x, y, 39) < 0.05 then return C_WHITE end
    return C_BLUE
  end)
  t(T.MARSH, speck(40, C_DKGRN, { { C_BROWN, 0.18 }, { C_INDIGO, 0.10 }, { C_GREEN, 0.10 } }))
  t(T.HAUNT, speck(41, C_INDIGO, { { C_NIGHT, 0.18 }, { C_DKGRN, 0.14 }, { C_GRAY, 0.05 } }))
  t(T.ASH, speck(42, C_NIGHT, { { C_BROWN, 0.2 }, { C_GRAY, 0.1 }, { C_RED, 0.02 } }))
  t(T.FARM, function(x, y)
    if y % 4 == 0 then return C_WOOD end
    if y % 4 == 2 and x % 4 == 1 then return C_LIME end
    return C_BROWN
  end)
  t(T.MOSS, speck(43, C_DKGRN, { { C_GREEN, 0.25 }, { C_LIME, 0.05 } }))
  t(T.DARKWOOD, function(x, y)
    if y % 4 == 3 then return C_NIGHT end
    if H(x, y, 44) < 0.1 then return C_WOOD end
    return C_BROWN
  end)
  t(T.ROOF, speck(45, C_INDIGO, { { C_GRAY, 0.2 } }))
  t(T.SNOWPATH, function(x, y)
    if (x + y) % 5 == 0 then return C_GRAY end
    if H(x, y, 46) < 0.2 then return C_CREAM end
    return C_WHITE
  end)
  t(T.MAPLE, function(x, y)
    local r = H(x, y, 47)
    if r < 0.14 then return C_RED elseif r < 0.22 then return C_GOLD end
    return grass(48)(x, y)
  end)

  -- representative colour at (4,4) for the 1px/cell world map
  local rep = {
    [T.OCEAN] = C_INDIGO, [T.WATER] = C_BLUE, [T.SHALLOW] = C_BLUE, [T.GRASS1] = C_GREEN,
    [T.GRASS2] = C_GREEN, [T.GRASS3] = C_GREEN, [T.FLOWERS] = C_GREEN, [T.SAKURA] = C_PINK,
    [T.FOREST] = C_DKGRN, [T.BAMBOO] = C_LIME, [T.DIRT] = C_TAN, [T.STONE] = C_CREAM,
    [T.PLAZA] = C_CREAM, [T.SAND] = C_CREAM, [T.SNOW1] = C_WHITE, [T.SNOW2] = C_WHITE,
    [T.ROCK] = C_GRAY, [T.GRAVEL] = C_CREAM, [T.WOOD] = C_WOOD, [T.PADDY] = C_LIME,
    [T.MARSH] = C_DKGRN, [T.HAUNT] = C_INDIGO, [T.ASH] = C_NIGHT, [T.LAVA] = C_RED,
    [T.FARM] = C_BROWN, [T.MOSS] = C_DKGRN, [T.DARKWOOD] = C_BROWN, [T.ROOF] = C_INDIGO,
    [T.SNOWPATH] = C_WHITE, [T.MAPLE] = C_RED,
  }
  for id, c in pairs(rep) do sset((id % 16) * 8 + 4, (id // 16) * 8 + 4, c) end

  -- ------------------------------------------------------------------------
  -- band textures (tile ids 40..79)
  -- ------------------------------------------------------------------------
  local function earthBody(seed)
    return function(x, y)
      local r = H(x, y, seed)
      if (y == 3 and r < 0.7) then return C_WOOD end
      if r < 0.08 then return C_TAN end
      if r > 0.9 then return C_NIGHT end
      return C_BROWN
    end
  end
  for k = 0, 1 do
    t(40 + k, function(x, y)
      if y == 0 then return H(x, 0, 50 + k) < 0.3 and C_LIME or C_GREEN end
      if y == 1 then return C_GREEN end
      if y == 2 then return H(x, 2, 52 + k) < 0.6 and C_DKGRN or C_BROWN end
      if y == 3 and H(x, 3, 54 + k) < 0.3 then return C_DKGRN end
      return earthBody(56 + k)(x, y)
    end)
  end
  for k = 0, 2 do t(42 + k, earthBody(60 + k)) end
  local function rockBody(seed)
    return function(x, y)
      local r = H(x, y, seed)
      if (x + (y // 4) * 3) % 8 == 0 then return C_INDIGO end
      if y % 4 == 0 and r < 0.6 then return C_WHITE end
      if y % 4 == 3 then return C_INDIGO end
      if r > 0.92 then return C_NIGHT end
      return C_GRAY
    end
  end
  for k = 0, 1 do
    t(45 + k, function(x, y)
      if y == 0 then return C_CREAM end
      if y == 1 then return H(x, 1, 70 + k) < 0.55 and C_CREAM or C_WHITE end
      if y == 2 and H(x, 2, 72 + k) < 0.25 then return C_CREAM end
      return rockBody(74 + k)(x, y)
    end)
  end
  for k = 0, 2 do t(47 + k, rockBody(78 + k)) end
  for k = 0, 1 do
    t(50 + k, function(x, y)
      if y == 0 then return C_CREAM end
      if y % 3 == 2 then return C_WOOD end
      if H(x, y, 82 + k) < 0.15 then return C_CREAM end
      return C_TAN
    end)
  end
  -- ishigaki stone wall: irregular blocks
  for k = 0, 3 do
    t(52 + k, function(x, y)
      local row = (y + (k % 2) * 2) // 4
      local off = (row % 2) * 3 + k
      local xx = (x + off) % 6
      if (y + (k % 2) * 2) % 4 == 3 or xx == 5 then return C_NIGHT end
      if (y + (k % 2) * 2) % 4 == 0 or xx == 0 then return C_CREAM end
      if H(x, y, 90 + k) < 0.12 then return C_INDIGO end
      return C_GRAY
    end)
  end
  -- house band: beam row / shoji row / lower wall row
  t(56, function(x, y)
    if y <= 1 then return C_NIGHT end
    if y <= 3 then return y == 2 and C_BROWN or C_WOOD end
    if y == 7 then return C_BROWN end
    return C_CREAM
  end)
  t(57, function(x, y)
    if x == 0 or x == 7 then return C_BROWN end
    if y == 0 or y == 7 then return C_BROWN end
    if x == 4 or y == 3 then return C_WOOD end
    return C_CREAM
  end)
  t(58, function(x, y)
    if x <= 1 then return C_BROWN end
    if x == 2 then return C_WOOD end
    if (x == 5) or y == 4 then return C_WOOD end
    return C_CREAM
  end)
  t(59, function(x, y)
    if y >= 6 then return y == 6 and C_INDIGO or C_GRAY end
    if x % 3 == 2 then return C_BROWN end
    if y == 0 then return C_BROWN end
    return C_WOOD
  end)
  -- plaster (castle tiers): white with dark timber
  t(60, function(x, y)
    if y <= 1 then return C_NIGHT end
    if x == 0 then return C_BROWN end
    if y == 7 then return C_BROWN end
    return C_WHITE
  end)
  t(61, function(x, y)
    if y >= 4 then return (x % 2 == 0) and C_NIGHT or C_INDIGO end
    if x == 0 then return C_BROWN end
    return C_WHITE
  end)
  -- kawara roof tiles: top row = ridge side, bottom row = eave
  t(62, function(x, y)
    if x % 4 == 0 then return C_NIGHT end
    if y % 4 == 0 then return C_GRAY end
    return C_INDIGO
  end)
  t(63, function(x, y)
    if y == 7 then return C_NIGHT end
    if y == 6 then return x % 4 == 2 and C_WHITE or C_GRAY end
    if x % 4 == 0 then return C_NIGHT end
    if y % 4 == 0 then return C_GRAY end
    return C_INDIGO
  end)
  t(64, function(x, y)
    if x % 4 == 3 then return C_BROWN end
    if H(x, y, 95) < 0.1 then return C_TAN end
    return C_WOOD
  end)
  t(65, function(x, y)
    if x == 0 or x == 7 then return C_BROWN end
    if x == 1 then return C_PINK end
    return C_RED
  end)
  for k = 0, 1 do
    t(66 + k, function(x, y)
      if k == 1 and y == 7 then return C_BROWN end
      local r = H(x, y, 96 + k)
      if (x + y) % 3 == 0 then return C_WOOD end
      if r < 0.2 then return C_CREAM end
      return C_TAN
    end)
  end
  t(68, function(x, y)
    if x % 4 == 0 then return C_NIGHT end
    if y == 0 then return C_WOOD end
    return C_BROWN
  end)
end

-- write the band rows into the map atlas (rows 112..135)
function Gfx.fillBands()
  local function fill(b, rowTiles)
    for r = 0, b.n - 1 do
      local opts = rowTiles[r + 1]
      for x = 0, 239 do
        mset(x, b.row + r, opts[1 + flr(hash2(x, r, b.row) * #opts)])
      end
    end
  end
  fill(BAND.EARTH, { { 40, 41 }, { 42, 43, 44 }, { 43, 44, 42 }, { 44, 42, 43 } })
  fill(BAND.ROCK, { { 45, 46 }, { 47, 48, 49 }, { 48, 49, 47 }, { 49, 47, 48 } })
  fill(BAND.SAND, { { 50, 51 } })
  fill(BAND.STONE, { { 52, 53 }, { 54, 55 } })
  -- house: beams over shoji/post alternation, lower wall
  for x = 0, 239 do
    mset(x, BAND.HOUSE.row, 56)
    mset(x, BAND.HOUSE.row + 1, (x % 3 == 0) and 58 or 57)
    mset(x, BAND.HOUSE.row + 2, 59)
    mset(x, BAND.PLASTER.row, 60)
    mset(x, BAND.PLASTER.row + 1, 61)
    mset(x, BAND.ROOF.row, 62)
    mset(x, BAND.ROOF.row + 1, 63)
    mset(x, BAND.WOOD.row, 64)
    mset(x, BAND.RED.row, 65)
    mset(x, BAND.THATCH.row, 66)
    mset(x, BAND.THATCH.row + 1, 67)
    mset(x, BAND.DARK.row, 68)
  end
end

-- liquid animation: call every frame
function Gfx.animTiles(f)
  if f % 12 ~= 0 then return end
  local k = (f // 12) % 4
  for _, l in ipairs(Gfx.liquid) do
    local fn = l[2](k)
    Gfx.tile(l[1], fn)
    sset((l[1] % 16) * 8 + 4, (l[1] // 16) * 8 + 4, l[3])
  end
end

-- ============================================================================
--  05 ART: CHARACTERS - hand-drawn sprites as hex rows ('.' = transparent).
--  Palette digits: 1 night/outline 2 indigo 3 blue 4 gray 5 dkgreen 6 green
--  7 lime 8 brown 9 wood a tan b cream c white d red e pink f gold
--  All side views face RIGHT; the renderer flips for left.
-- ============================================================================
Art = {}

-- ---------------------------------------------------------------- the ninja
local NH = [[
................
.......11111....
......1332221...
.....133222221..
...dd132222221..
..ddd1222bbbb1..
.dd..122bbb1b1..
.....122222221..
......1222221...
..ddd1ddddd1....
]]
-- side torso/leg variants (10 rows each)
local NS_IDLE = [[
.....1322221....
....132222221...
....12dddddb1...
....1422222b1...
....4.12222.1...
......12212.....
......12.12.....
......12.12.....
......12.12.....
.....111.111....
]]
local NS_WALK1 = [[
.....1322221....
....132222221...
....12dddddb1...
....142222221...
....4.122221....
.....1221122....
.....122..122...
....122....11...
....11..........
................
]]
local NS_WALK2 = [[
.....1322221....
....132222221...
....12dddddb1...
....142222221...
....4.122221....
......12221.....
......1222......
......1221......
......11221.....
.......111......
]]
local NS_JUMP = [[
....11322221....
...1b2222221....
....12ddddd1....
....1422222b1...
....4.1222221...
.....122.1221...
....122...111...
....11..........
................
................
]]
local NS_FALL = [[
.....1322221.1b.
....13222222221.
....12ddddd11...
....142222221...
....4.122221....
.....1221221....
.....122.122....
.....11...11....
................
................
]]
local NS_SLASH1 = [[
.....1322221....
....132222221...
....12ddddd2221b
....142222221...
....4.122221....
.....1221122....
.....122..122...
....122....11...
....11..........
................
]]
local NS_SLASH2 = [[
.....132222b1...
....1322222b1...
....12ddddd21...
....14222221....
....4.122221....
.....1221122....
....122...122...
...122.....11...
...11...........
................
]]
local NS_SWIM = [[
...1b2222222b1..
....11111111....
................
................
................
................
................
................
................
................
]]

-- front view (facing camera)
local NF_HEAD = [[
................
.....111111.....
....13322221....
...1332222221...
...1322222221...
...12bbbbbbb1...
...12b1bb1bb1...
...122222222d...
....1222221.dd..
....dddddddd.d..
]]
local NF_IDLE = [[
...1132222211...
..1b122222221b1.
..112dddddd2111.
...14222222241..
....1222222241..
....122112214...
....12211221....
....12211221....
....12211221....
....1111.111....
]]
local NF_WALK1 = [[
...1132222211...
..1b122222221b1.
..112dddddd2111.
...14222222241..
....1222222241..
....122112214...
....12211221....
....1221.111....
....1221........
....1111........
]]
-- back view (also used for climbing)
local NB_HEAD = [[
................
.....111111.....
....13322221....
...1332222221...
...1322222221...
...13222222d1...
...1222222dd1...
...122222222d...
....1222221.dd..
....dddddddd.d..
]]
local NB_IDLE = [[
...11322f2211...
..1b1224f2221b1.
..112ddd4ddd111.
...1422224222...
....122222221...
....122112221...
....12211221....
....12211221....
....12211221....
....1111.111....
]]
local NB_WALK1 = [[
...11322f2211...
..1b1224f2221b1.
..112ddd4ddd111.
...1422224222...
....122222221...
....122112221...
....12211221....
....1221.111....
....1221........
....1111........
]]
local NB_CLIMB = [[
.1b1.322f221.1b1
.1211224f2221121
..112ddd4ddd11..
...1422224222...
....122222221...
....122112221...
....1221.1221...
....1221.111....
....111.........
................
]]

-- glide: ninja hanging under a kite (wider sprite)
local N_GLIDE = [[
..1111111111111111..
.1dddeddddddeddddd1.
1ddeedddddddddeeddd1
.11111dd1111dd11111.
......1.1..1.1......
.......1.11.1.......
........1111........
.......133221.......
......1332222b1.....
....dd1222bbb11.....
...ddd122bb1b1......
.......1222221......
......1ddddd1.......
.....132222221......
.....12ddddd21......
......1222221.......
......122.122.......
.....122...122......
.....11.....11......
]]

local function nin(head, body) return Gfx.stack(Gfx.rows(head), Gfx.rows(body)) end

function Art.chars()
  local add = Gfx.add
  add("n_s_idle", nin(NH, NS_IDLE))
  add("n_s_walk1", nin(NH, NS_WALK1))
  add("n_s_walk2", nin(NH, NS_WALK2))
  add("n_s_jump", nin(NH, NS_JUMP))
  add("n_s_fall", nin(NH, NS_FALL))
  add("n_s_slash1", nin(NH, NS_SLASH1))
  add("n_s_slash2", nin(NH, NS_SLASH2))
  local sw = nin(NH, NS_SWIM)
  add("n_swim", { table.unpack(sw, 1, 12) })
  add("n_f_idle", nin(NF_HEAD, NF_IDLE))
  add("n_f_walk1", nin(NF_HEAD, NF_WALK1))
  add("n_b_idle", nin(NB_HEAD, NB_IDLE))
  add("n_b_walk1", nin(NB_HEAD, NB_WALK1))
  add("n_climb", nin(NB_HEAD, NB_CLIMB))
  add("n_glide", N_GLIDE)
end

-- ============================================================================
--  06 ART: WORLD - trees, rocks, plants, props, effects, decals.
--  Organic shapes are painted procedurally (lit from the upper left);
--  props are hand-drawn rows.
-- ============================================================================
local H = hash2

-- blobby canopy painter: circles {x,y,r}; ramp {light, mid, dark, outline}
local function canopy(w, h, circles, ramp, trunk, seed)
  return function(x, y)
    local inside, best, bd = false, nil, 1e9
    for i = 1, #circles do
      local c = circles[i]
      local dx, dy = x + 0.5 - c[1], y + 0.5 - c[2]
      local d = (dx * dx + dy * dy) / (c[3] * c[3])
      if d <= 1 then
        inside = true
        -- prefer the circle drawn "in front" (later, lower)
        best = c
        bd = d
      end
    end
    if inside then
      local dx, dy = (x + 0.5 - best[1]) / best[3], (y + 0.5 - best[2]) / best[3]
      local l = -(dx * 0.7 + dy * 0.9) + (H(x, y, seed) - 0.5) * 0.5
      if bd > 0.82 and (dx + dy) > 0.2 then return ramp[4] end
      if l > 0.45 then return ramp[1] end
      if l > -0.25 then return ramp[2] end
      return ramp[3]
    end
    if trunk then return trunk(x, y) end
    return 0
  end
end

local function trunkFn(x0, x1, y0, y1)
  return function(x, y)
    if y >= y0 and y <= y1 and x >= x0 and x <= x1 then
      if x == x0 then return C_WOOD end
      if x == x1 then return C_NIGHT end
      if (x + y) % 5 == 0 then return C_NIGHT end
      return C_BROWN
    end
    -- roots
    if y == y1 and (x == x0 - 1 or x == x1 + 1) then return C_BROWN end
    return 0
  end
end

local function pine(w, h, snow)
  return function(x, y)
    local cx = w / 2
    -- trunk
    if y >= h - 5 and math.abs(x + 0.5 - cx) < 1.6 then return (x + 0.5 < cx) and C_WOOD or C_BROWN end
    -- 4 tiers of triangles
    for t = 0, 3 do
      local top = 1 + t * 6
      local bot = top + 9
      if y >= top and y <= bot then
        local half = 1 + (y - top) * (0.55 + t * 0.12)
        local dx = x + 0.5 - cx
        if math.abs(dx) <= half then
          if snow and (y - top) <= 1 + (H(x, t, 5) < 0.5 and 1 or 0) then return C_WHITE end
          if y == bot or math.abs(dx) > half - 1 and dx > 0 then return C_NIGHT end
          if dx < -half * 0.3 then return snow and C_WHITE or C_GREEN end
          if H(x, y, 9) < 0.15 then return C_GREEN end
          return C_DKGRN
        end
      end
    end
    return 0
  end
end

local function rockFn(w, h, ore)
  local cx, cy = w / 2, h * 0.6
  return function(x, y)
    local dx, dy = (x + 0.5 - cx) / (w / 2), (y + 0.5 - cy) / (h * 0.62)
    if dy > 0.62 then return 0 end
    local d = dx * dx + dy * dy + (H(x, y, 3) - 0.5) * 0.12
    if d > 1 then return 0 end
    if d > 0.78 and (dx + dy) > -0.1 then return C_NIGHT end
    local l = -(dx * 0.6 + dy) + (H(x, y, 4) - 0.5) * 0.4
    if ore and H(x, y, 7) < 0.12 and d < 0.7 then return (H(x, y, 8) < 0.5) and C_GOLD or C_BLUE end
    if l > 0.55 then return C_WHITE end
    if l > -0.2 then return C_GRAY end
    return C_INDIGO
  end
end

local function bushFn(w, h, berries)
  return canopy(w, h, { { w * 0.3, h * 0.6, h * 0.5 }, { w * 0.7, h * 0.6, h * 0.5 }, { w * 0.5, h * 0.45, h * 0.55 } },
    { C_LIME, C_GREEN, C_DKGRN, C_NIGHT }, nil, 21), berries
end

function Art.world()
  local add, addfn = Gfx.add, Gfx.addfn
  -- trees ------------------------------------------------------------------
  addfn("tree", 24, 30, canopy(24, 30, {
    { 7, 12, 6.5 }, { 17, 11, 6.5 }, { 12, 7, 7 }, { 8, 17, 6 }, { 16, 17, 6.5 }, { 12, 14, 7 },
  }, { C_LIME, C_GREEN, C_DKGRN, C_NIGHT }, trunkFn(10, 13, 18, 29), 11))
  addfn("pine", 16, 32, pine(16, 32, false))
  addfn("willow", 22, 28, function(x, y)
    local c = canopy(22, 28, { { 6, 9, 6 }, { 15, 8, 6.5 }, { 11, 6, 6 }, { 11, 11, 7 } },
      { C_LIME, C_GREEN, C_DKGRN, C_NIGHT }, trunkFn(10, 12, 14, 27), 31)(x, y)
    if c ~= 0 then return c end
    -- drooping strands
    if y > 10 and y < 24 and x % 3 == 1 and H(x, 0, 32) < 0.8 and y < 14 + H(x, 1, 33) * 10 then
      return (y % 2 == 0) and C_GREEN or C_LIME
    end
    return 0
  end)
  add("deadtree", [[
.......1.....1..
......181...18..
...1..181..181..
..181.1881181...
...1881888881...
.....188881.....
..11.18881......
.18818881.......
..11888881......
.....18881......
......1881......
......18881.....
......18891.....
......18891.....
......18891.....
......18891.....
.....188891.....
.....1888891....
....118888911...
....1.1111.1....
]])
  add("bamboo", [[
......7..7..7.
.7...77.776.77
.77.767.67.677
..7.6...6..76.
....76..76..7.
....76..76..76
....76..76..76
....56..56..76
....76..76..56
....76..76..76
....76..76..76
....76..56..76
....56..76..76
....76..76..76
....76..76..56
....76..76..76
....76..76..76
....76..56..76
....76..76..76
....56..76..76
....76..76..56
....76..76..76
....76..76..76
....76..76..76
....76..56..76
....56..76..76
....76..76..76
....76..76..76
....76..76..76
...1561156115611
]])
  -- the bamboo stalks: use lime/green; fix blue placeholder via remap at draw
  -- rocks --------------------------------------------------------------------
  addfn("rock", 10, 7, rockFn(10, 9, false))
  addfn("boulder", 16, 13, rockFn(16, 16, false))
  addfn("ore", 16, 13, rockFn(16, 16, true))
  -- plants -------------------------------------------------------------------
  add("grass", [[
.7....7.
.67..76.
..6.76..
.56.65.7
.5665576
55666655
]])
  add("grasscut", [[
.5.6.5..
55665565
]])
  add("flower", [[
.e.e...
eefee..
.e6e...
..6..d.
..6.dfd
..66.6.
...66..
]])
  add("bush", [[
.....1111.....
...11677611...
..1677766761..
.167766667761.
.16676d6667d61
1666d6f66666d1
1d6666666d66651
15666d66666651.
.155666666551..
..1111111111...
]])
  add("bush_empty", [[
.....1111.....
...11677611...
..1677766761..
.167766667761.
.1667666667661
16666666666661
1566666666665.
15566666666551.
.155666666551..
..1111111111...
]])
  add("mushroom", [[
..1111..
.1dcdd1.
1dddcdd1
1cddddc1
.11bb11.
...bb...
..1bb1..
]])
  add("reeds", [[
.8....8.
.8..8.8.
.6..8.6.
.6..6.6.
.66.6.6.
..6.6.66
..6.66.6
..66.6.6
.5.6.6.6
.5.6.65.
..56.55.
..5655..
.55655..
555555..
]])
  add("herb", [[
..7.7..
.776.7.
..676..
.76.67.
..565..
...5...
]])
  add("rice", [[
..f.f..
.f.f.f.
..f7f..
.7.6.7.
..767..
...6...
..565..
.5.5.5.
]])
  add("stump", [[
..11111...
.1aaaa91..
.19aa991..
.1888881..
1188888911
.11...111.
]])
  add("bamboostump", [[
.1..1...
.7117.1.
.76.76.7
.76.76.3
.56.56.5
]])
  -- props --------------------------------------------------------------------
  add("toro", [[
...111...
..14441..
.1444441.
.1111111.
...1c1...
..14f41..
..1fff1..
..14441..
...141...
...141...
...141...
..14441..
.1444441.
.1111111.
]])
  add("jizo", [[
..1111..
.1cccc1.
.1c1c11.
.1cccc1.
.1dddd1.
.1dddd1.
.1cccc1.
1cccccc1
1cc44cc1
14444441
.111111.
]])
  add("grave", [[
..1111..
.144441.
.14c441.
.144c41.
.144441.
.14c441.
.144441.
.144441.
1144441.
14444441
11111111
]])
  add("fence", [[
.1..1..1..1.
1a11a11a11a1
1a19a19a19a1
1aaaaaaaaaa1
1a91a91a91a1
1a11a11a11a1
1aaaaaaaaaa1
1a91a91a91a1
1a11a11a11a1
.1..1..1..1.
]])
  add("crate", [[
1111111111
1a9999999a
19aa999aa1
199aa9aa91
1999aa9991
199aa9aa91
19aa999aa1
1a9999999a
1111111111
]])
  add("barrel", [[
.111111.
19a99a91
1888888a
19a99a91
19a99a91
1888888a
19a99a91
.111111.
]])
  add("sign", [[
1111111111
1aaaaaaaa1
1a888888a1
1aaaaaaaa1
1a8888a8a1
1aaaaaaaa1
1111991111
....99....
....98....
....98....
....98....
...1981...
]])
  add("banner", [[
1111..
1dd1..
1dc1..
1dd1..
1cd1..
1dd1..
1dd1..
1cc1..
1dd1..
1d11..
11....
91....
91....
91....
91....
91....
91....
91....
91....
91....
91....
191...
]])
  add("chest", [[
.1111111111.
1f988888891f
19888f888891
1111111f1111
1988818f8891
19888818f891
198888888891
1f888888888f
111111111111
]])
  add("chest_open", [[
.1111111111.
1f911111191f
19111111191.
1f988888891f
1111111111111
1988818f8891
19888818f891
198888888891
1f888888888f
111111111111
]])
  add("kodama1", [[
..111..
.1ccc1.
1cc1c11
1ccccc1
.1ccc1.
.1c1c1.
..1.1..
]])
  add("kodama2", [[
..111..
.1ccc1.
11c1cc1
1ccccc1
.1ccc1.
1c1.1c1
.1...1.
]])
  add("hokora", [[
.....1111.....
...11dddd11...
.11dddddddd11.
1dddddddddddd1
11111111111111
..1b8bbbb8b1..
..1b8b11b8b1..
..1b8b11b8b1..
..1b8bbbb8b1..
..1888888881..
..1a99999981..
.1144444444411
.1444444444441
.1111111111111
]])
  add("well", [[
..1111111111..
.1888888888881
..1.......1...
..1.......1...
..1...1...1...
..1..1b1..1...
.1144444444411
14444c4444c441
1444444444444.
13333333333331
14444444444441
.111111111111.
]])
  add("fire1", [[
.....d......
....dfd.....
...dffd.d...
...dfcfdfd..
..dffcffd...
..dfccffd...
.19dffd891..
1989aa9898.1
.1188889811.
..1111111...
]])
  add("fire2", [[
......d.....
...d.dfd....
...dfffd....
..dfcffdd...
..dffcfffd..
..dfcccfd...
.19dffd891..
1989aa9898.1
.1188889811.
..1111111...
]])
  add("logs", [[
............
............
............
............
............
............
.19889.891..
1989aa9898.1
.1188889811.
..1111111...
]])
  add("pot", [[
..1111111.
.144444441
1442222244
14422222441
1444444444
.1444444441
..11111111
.1.....1..
]])
  add("chochin", [[
..1...
.141..
1dddd1
1dfdd1
1dddd1
1dfdd1
1dddd1
.1111.
..91..
..91..
..91..
..91..
..91..
..91..
.1981.
]])
  add("web", [[
c.....c.....c...
.c....c....c....
..c...c...c.....
...cccccccc.....
...c..c...c.....
cccc..c...cccccc
...c..c...c.....
...cccccccc.....
..c...c...c.....
.c....c....c....
c.....c.....c...
]])
  add("bones", [[
.c...cc...
cbc.c..c..
.cbcbbc.c.
..cbbcbc..
.11111111.
]])
  add("statue", [[
....1111....
...1cccc1...
...1c1c11...
...1cccc1...
....1cc1....
..11cccc11..
.1ccccccccf1
.1cfcccccff1
.1cc4cc4cc1.
.1cc4cc4cc1.
..1c4cc4c1..
..1cccccc1..
..1c4444c1..
..1cccccc1..
.11cccccc11.
1444444444441
144c4444c4441
.11111111111.
]])
  -- fx -----------------------------------------------------------------------
  add("slash", [[
.........cc.....
.......ccbc.....
.....cbbb.......
...cbbb.........
..cbb...........
.cbb............
.cb.............
cbb.............
cb..............
cb..............
.c..............
]])
  add("spark", [[
...c...
.c.c.c.
..cfc..
ccfcfcc
..cfc..
.c.c.c.
...c...
]])
  add("puff", [[
..11..
.1cc1.
1cbbc1
1cbbc1
.1cc1.
..11..
]])
  add("shadow", [[
..111111..
.11111111.
1111111111
1111111111
1111111111
1111111111
1111111111
1111111111
.11111111.
..111111..
]])
  add("shuriken", [[
...1...
..141..
.1441c.
1441441
.c1441.
..141..
...1...
]])
  add("arrow", [[
1........
.1444444f
1........
]])
  add("feather", [[
..11.
.1221
12221
1221.
.11..
]])
  add("fireball", [[
..dd..
.dffd.
dffcfd
dfccfd
.dffd.
..dd..
]])
  add("exclaim", [[
.111.
1fff1
1fff1
.1f1.
.1f1.
..1..
.1f1.
..1..
]])
  add("question", [[
.1111.
1fccf1
.1.1f1
..1f1.
..1f1.
...1..
..1f1.
...1..
]])
  add("zzz", [[
1111.
..1..
.1...
1111.
]])
  add("ripple", [[
..cccc..
cc....cc
..cccc..
]])
  add("petal", [[
ec
.e
]])
  add("orb", [[
..111..
.13331.
13ccc31
13c3c31
13ccc31
.13331.
..111..
]])
  -- decals (on walls) -----------------------------------------------------------
  add("door", [[
1111111111
18a8a8a8a1
1a8a8a8a81
18a8a8a8a1
1a8a8a8a81
18a8a8a8a1
1a8a8a8a81
18a8a8a8a1
1a8a8a8a81
18a8a8a8a1
1a8a8a8a81
1111111111
]])
  add("noren", [[
1111111111111111
1222222222222221
1222c222222c2221
122ccc2222ccc221
1222c222222c2221
1222222222222221
1222.222222.2221
1222.222222.2221
.22...2222...22.
]])
  add("dojo_sign", [[
1111111111111111
1aaaaaaaaaaaaaa1
1a1a11a1aa1a11a1
1a11a1a1a11aa1a1
1a1a11a1aa1a11a1
1aaaaaaaaaaaaaa1
1111111111111111
]])
  add("cave", [[
....1111111111....
..11111111111111..
.1111111111111111.
111111111111111111
111111111111111111
111111111111111111
111111111111111111
111111111111111111
111111111111111111
111111111111111111
]])
end

-- ============================================================================
--  07 ART: ITEMS & UI - 8x8 icons (packed into unused map-tile slots).
-- ============================================================================
local ICONS = {
  wood = [[
........|....111.|...1aa91|..19aa91|.1999891|19998891|1888891.|.11111..]],
  bamboo = [[
.....1..|....171.|...1761.|..1561..|.1761...|.761....|1561....|.1......]],
  stone = [[
........|........|..1111..|.1c4441.|1c444441|14444441|.1111111|........]],
  flint = [[
........|....11..|...1c21.|..1c221.|.122221.|.122221.|..1111..|........]],
  grass = [[
.7.7..7.|.67.76..|..6766..|..1a1a..|...66...|..6666..|.66..66.|........]],
  reed = [[
.8.8..8.|.68.86..|..6866..|..1a1a..|...66...|..6666..|.66..66.|........]],
  iron = [[
........|..1111..|.14c341.|14344441|14443341|.1444441|..11111.|........]],
  gold = [[
........|...111..|..1fcf1.|.1ffff91|.1f9ff91|..19991.|...111..|........]],
  silk = [[
........|..1111..|.1cccc1.|.1c44c1.|.1cccc1.|.1c44c1.|..1111..|........]],
  pelt = [[
........|.1....1.|14411441|14444441|.144441.|.144441.|14411441|.1....1.]],
  feather = [[
......11|.....121|....1221|...1221.|..1221..|.1221...|.11.....|1.......]],
  petal = [[
........|..1e1...|.1eee1..|1eecee1.|.1eee1..|..1e1...|........|........]],
  pinecone = [[
........|...11...|..1991..|.199891.|.189891.|..1891..|...11...|........]],
  essence = [[
...cc...|..c33c..|.c3cc3c.|.c3c33c.|..c33c..|..c3c...|...c....|........]],
  ember = [[
...d....|..dfd...|.dfcfd..|.dfccfd.|.dfcfd..|..dfd...|...d....|........]],
  rope = [[
........|..1111..|.1a99a1.|1a9..9a1|1a9..9a1|.1a99a1.|..11a1..|.....1..]],
  paper = [[
........|.111111.|1cccccc1|1c4444c1|1cccccc1|1c4444c1|1cccccc1|.111111.]],
  flower = [[
........|..1e1...|.1efe1..|..1e1...|...6....|..76....|...6....|........]],
  berries = [[
....6...|...76...|..1d1...|.1dcd11.|.1ddd1d1|..1111d1|....1d1.|.....1..]],
  mushroom = [[
........|..1111..|.1dcdd1.|1ddddcd1|11111111|..1bb1..|..1bb1..|...11...]],
  gmush = [[
........|..1111..|.189891.|18988981|11111111|..1aa1..|..1aa1..|...11...]],
  herb = [[
........|.7..7...|.67.67..|..676...|.7.6.7..|..767...|...6....|........]],
  rice = [[
...11...|..1aa1..|..1aa1..|.1bbbb1.|1bbbbbb1|1bbbbbb1|.1bbbb1.|..1111..]],
  onigiri = [[
...11...|..1cc1..|.1cccc1.|.1cccc1.|1c1111c1|1c1111c1|.111111.|........]],
  meat = [[
........|..1111..|.1dddd1.|1dddcd1.|1dddd1cc|.1111.cc|........|........]],
  cmeat = [[
........|..1111..|.198891.|1989981.|199991cc|.1111.cc|........|........]],
  fish = [[
........|........|.1111..1|13cc311.|1c33331.|.1111..1|........|........]],
  gfish = [[
........|........|.1111..1|19aa911.|1a99991.|.1111..1|........|........]],
  shoot = [[
...1....|..171...|..161...|.17761..|.16a61..|1a9a9a1.|1aaaaa1.|.11111..]],
  cshoot = [[
...1....|..1a1...|..1a1...|.1aaa1..|.1a9a1..|1a9a9a1.|1aaaaa1.|.11111..]],
  cucumber = [[
........|.....11.|....1761|...1761.|..1761..|.1761...|.161....|..1.....]],
  sushi = [[
........|........|.111111.|1dcddcd1|11111111|1cccccc1|1cccccc1|.111111.]],
  mochi = [[
........|..1111..|.1cccc1.|1cceccc1|1cccccc1|1cccccc1|.111111.|........]],
  stew = [[
..c.c...|...c.c..|.111111.|1d6b9d61|19999991|.144441.|..1111..|........]],
  tea = [[
........|..c.c...|.111111.|16766661|17666611|.166661.|..1111..|........]],
  dango = [[
......1.|.....e..|....1e1.|...1c1..|..161...|.1.1....|1.......|........]],
  bandage = [[
........|.111111.|1cccccc1|1cc1dcc1|1c1ddd1c|1cc1dcc1|1cccccc1|.111111.]],
  axe = [[
..1111..|.14cc1..|.144441.|..1491..|...191..|...191..|...191..|...11...]],
  pick = [[
.111111.|1c4444c1|.1.19.1.|....91..|...91...|..91....|.91.....|.1......]],
  torch = [[
...d....|..dfd...|..dfd...|..1a1...|..191...|..191...|..191...|..111...]],
  lantern = [[
...1....|..1d1...|.1dfd1..|.1dfd1..|.1dfd1..|.1ddd1..|..111...|........]],
  campfire = [[
........|....d...|...dfd..|...dfd..|.19a991.|19898891|.111111.|........]],
  potkit = [[
........|..1111..|.144441.|14222241|14444441|.144441.|.1....1.|........]],
  bedroll = [[
........|........|.111111.|1aaaaaa1|1a9a9aa1|1aaaaaa1|.111111.|........]],
  bokken = [[
.......1|......19|.....19.|....19..|...19...|.1891...|..81....|.1.1....]],
  katana = [[
.......1|......1c|.....1c.|....1c..|...1c...|.1f11...|..21....|.1.1....]],
  steel = [[
.......1|......cc|.....c3.|....c3..|...c3...|.1ff1...|..d1....|.1.1....]],
  kusanagi = [[
......cf|.....c3f|....c3f.|...c3f..|..c3f...|.fff1...|..f1....|.f.f....]],
  shuriken = [[
...1....|..141...|.1441c..|1441441.|.c1441..|..141...|...1....|........]],
  barmor = [[
........|.1....1.|.177771.|.167671.|.177771.|.167671.|.177771.|..1111..]],
  sarmor = [[
........|.1....1.|.1dddd1.|.1d44d1.|.1dddd1.|.1d44d1.|.1dddd1.|..1111..]],
  cloak = [[
...11...|..1441..|.144441.|14411441|14411441|14411441|14441441|.11..11.]],
  hat = [[
........|........|...11...|..1aa1..|.1a99a1.|1aaaaaa1|.111111.|........]],
  package = [[
........|.111111.|1a9a9a91|1999d991|1ddddddd|1999d991|1a9ad9a1|.111111.]],
  magatama = [[
........|..1111..|.1666661|.16c6661|..16661.|...1661.|....161.|.....1..]],
  mirror = [[
..1111..|.1ffff1.|1fcc3cf1|1fc33cf1|1f3c3cf1|1fcc3cf1|.1ffff1.|..1111..]],
  charm = [[
.1....1.|1c1..1c1|1cccccc1|1c1cc1c1|1cdccdc1|1cccccc1|.1cccc1.|..1111..]],
  cat = [[
.1....1.|1a1..1a1|1aaaaaa1|1a1aa1a1|1aaeaaa1|.1aaaa1.|..1111..|........]],
  -- UI / special
  ryo = [[
..1111..|.1ffff1.|1ff11ff1|1f1ff1f1|1f1ff1f1|1ff11ff1|.1ffff1.|..1111..]],
  seed = [[
........|...11...|..1771..|.177761.|.176661.|..1661..|...11...|........]],
  orbi = [[
..1111..|.133331.|13cccc31|13c33c31|13c33c31|13cccc31|.133331.|..1111..]],
  heart = [[
.11.11..|1dd1dd1.|1dcddd1.|1ddddd1.|.1ddd1..|..1d1...|...1....|........]],
  heart0 = [[
.11.11..|1221221.|1222221.|1222221.|.12221..|..121...|...1....|........]],
  bowl = [[
........|.c..c...|..c..c..|11111111|1dcdddd1|.1dddd1.|..1111..|........]],
  key_z = [[
1111111.|1cccccc1|1c1111c1|1ccc1cc1|1cc1ccc1|1c1111c1|1cccccc1|.111111.]],
  key_x = [[
1111111.|1cccccc1|1c1cc1c1|1cc11cc1|1cc11cc1|1c1cc1c1|1cccccc1|.111111.]],
  key_a = [[
1111111.|1cccccc1|1cc11cc1|1c1cc1c1|1c1111c1|1c1cc1c1|1cccccc1|.111111.]],
  key_s = [[
1111111.|1cccccc1|1cc111c1|1c1cccc1|1cc11cc1|1cccc1c1|1c111cc1|.111111.]],
  tab_tools = [[
..1111..|.14cc1..|.144441.|..1491..|...191..|...191..|...191..|...11...]],
  tab_light = [[
...d....|..dfd...|..dfd...|..1a1...|..191...|..191...|..191...|..111...]],
  tab_surv = [[
........|..1111..|.144441.|14222241|14444441|.144441.|.1....1.|........]],
  tab_combat = [[
...1....|..141...|.1441c..|1441441.|.c1441..|..141...|...1....|........]],
  tab_dress = [[
........|........|...11...|..1aa1..|.1a99a1.|1aaaaaa1|.111111.|........]],
  pin = [[
..111...|.1ddd1..|1dcdddd1|1ddddd1.|.1ddd1..|..1d1...|...1....|........]],
  towerico = [[
...1....|..111...|.1dddd1.|..1c1...|.111111.|..1c1...|.1dddd1.|.111111.]],
  shrineico = [[
........|1dddddd1|.1dddd1.|..1..1..|..1..1..|..1..1..|.11..11.|........]],
  townico = [[
...11...|..1221..|.122221.|11111111|.1b8b81.|.1b8b81.|.111111.|........]],
  bossico = [[
.1....1.|1d1..1d1|1dddddd1|1dcddcd1|1dddddd1|.1c11c1.|..1111..|........]],
  skull = [[
.111111.|1cccccc1|1c11c11c|1c11c11c|1cccccc1|.1c11c1.|..1cc1..|...11...]],
}

function Art.items()
  for name, art in pairs(ICONS) do
    local key = (ITEM[name] and ("i_" .. name)) or name
    Gfx.icon(key, art)
  end
end

-- ============================================================================
--  08 ART: NPCs & ENEMIES (side views face right; front views face camera)
-- ============================================================================
local MOBS = {
  -- villager in a straw kasa
  vil_f1 = [[
................
.......11.......
.....1aaaa1.....
...11a9a9aa11...
..1aaaaaaaaaa1..
...1111111111...
.....1bbbb1.....
.....1b1b1b1....
.....1bbbbb1....
......1bbb1.....
....113333311...
...1b3233323b1..
...1b13333 31b1.
....1d3dddd31...
....133333331...
....132223331...
....13333 331...
.....133 331....
.....1bb1bb1....
.....111.111....
]],
  -- woman in kimono with hair bun
  wom_f1 = [[
................
......1111......
.....111111.....
....11111111....
...1111ff1111...
...111bbbb111...
...11b1bb1b11...
....1bbbbbb1....
.....1beeb1.....
....11eeee11....
...1beeceeeb1...
...1be1ee1eb1...
....1dddddd1....
....1eeeeee1....
....1eceeee1....
....1eeeece1....
....1eeeeee1....
....1eeceee1....
.....1b11b1.....
.....11..11.....
]],
  -- elder / sensei: white hair, beard, grey robe, staff
  eld_f1 = [[
................
.....11111......
....1cccccc1....
...1cccccccc1...
...1cbbbbbbc1...
...1b1bbbb1b1...
...1bbbbbbbb1...
....1cccccc1..1.
....1ccccccc1.91
...11ccccccc1191
..1444cccc4441b1
..14b4444444b191
..1144dddd441.91
...1444444441.91
...1444444441.91
...1444444441.91
...1444444441.91
....14411441..91
....1bb11bb1..91
....111..111..11
]],
  -- samurai guard with kabuto and spear
  grd_f1 = [[
.............c..
......f....f.4..
.....1f1111f14..
....1222222221..
...122222222214.
...1bbbbbbbbb14.
...1b1bbbb1bb14.
....1bbbbbbb1.4.
...11dddddddd114
..1d2dd22dd2d1b4
..1db1dddd1bdb14
..1d11d22d11d1.4
...1dd2222dd1..4
...1dddddddd1..4
...1d2dddd2d1..4
...1dddddddd1..4
....1221122 1..4
....1221.1221..4
....1111.1111..4
...............1
]],
  -- child
  kid_f1 = [[
............
....1111....
...111111...
..11111111..
..1bbbbbb1..
..1b1bb1b1..
..1bbbbbb1..
...1beeb1...
..1e7777e1..
.1b7777777b.
..1767767 1.
..1777777 1.
...177771...
...1b11b1...
...11..11...
]],
  -- lady Sayo (court lady): long black hair, layered kimono
  lady_f1 = [[
................
.....111111.....
....11111111....
...111f11f111...
...11bbbbbb11...
...11b1bb1b11...
...111bbbb111...
...1111bb1111...
..111eeeeee111..
..11e2eeee2e11..
..11ee2ee2ee11..
...1eedddde 1...
...12eeeeee21...
...1e2eeee2e1...
...12eeeeee21...
...1e2eeee2e1...
..12eeeeeeee21..
..1eeeeeeeeee1..
..111111111111..
................
]],
  -- bandit ronin (side), attack frame has raised blade
  ban_s1 = [[
........11......
.......1111.....
......1dddd1....
.....1d1111d1...
.....1bbbbbb1...
.....1bbb1bb1...
......1bbbbb1...
.....1191bb1....
....19988881....
...198988891....
...1b989889b1...
...1b19888 1b1..
....1dddddd14...
....18889981.4..
....1888 881..4.
.....19989 1....
....1991.1991...
....1981..1981..
....111....111..
................
]],
  ban_s2 = [[
........11......
.......1111.....
......1dddd1....
.....1d1111d1...
.....1bbbbbb1...
.....1bbb1bb1...
......1bbbbb1...
.....1191bb1....
....19988881....
...198988891....
...1b989889b1...
...1b19888 1b1..
....1dddddd14...
....18889981.4..
....1888 881..4.
.....199891.....
.....19981......
.....1981.......
.....1111.......
................
]],
  ban_atk = [[
...........c....
........11.c....
.......1111c....
......1dddd1c...
.....1d1111dc...
.....1bbbbbb1...
.....1bbb1bb1...
......1bbbbb1...
.....1191bb1b...
....19988881b...
...198988891....
...1b989889 1...
....1dddddd1....
....18889981....
....1888 881....
.....19989 1....
....1991.1991...
....1981..1981..
....111....111..
................
]],
  -- wolf (side, 20x13)
  wolf1 = [[
...............11...
..............1441..
.............14c441.
..1.........144441c1
.141.......14441111.
..1411111114444441..
...144444444c444 1..
...14c4444444441....
....14444444441.....
....141.1441.141....
...141...141..141...
...11.....11...11...
....................
]],
  wolf2 = [[
...............11...
..............1441..
..1..........14c441.
.141........144441c1
..1411111111444111..
...1444444444444441.
...14c4444444441 1..
....1444444444 1....
.....1414441441.....
....141.1441.141....
...141....11..11....
...11...............
....................
]],
  -- boar (side)
  boar1 = [[
..................
.......1111111....
.....11888888811..
....1888888888891.
...188888888889a91
..18898888889991c1
.1888888888891c1.1
.18888888888891...
..188888888891....
...181.181.181....
...11..11..11.....
..................
]],
  boar2 = [[
..................
.......1111111....
.....11888888811..
....1888888888891.
...188888888889a91
..18898888889991c1
.1888888888891c1.1
.18888888888891...
..188888888891....
....181181.181....
....11.11..11.....
..................
]],
  -- kappa (side): green, shell, beak, dish on head
  kap1 = [[
.....1111.....
....1cccc1....
...1c3333c1...
...16666661...
..1666661661..
..16666666ff1.
..1666666ff1..
...16666661...
..1a1666661...
.1a9a166661...
.1a9a166661...
.1a9a16666 1..
..1a1166661...
....1661661...
....1661.1661.
....111..111..
]],
  kap2 = [[
.....1111.....
....1cccc1....
...1c3333c1...
...16666661...
..1666661661..
..16666666ff1.
..1666666ff1..
...16666661...
..1a1666661...
.1a9a166661...
.1a9a166661...
.1a9a16666 1..
..1a1166661...
....16611661..
...1661..111..
...111........
]],
  -- tengu (side): red face, long nose, black wings, yamabushi cap
  ten1 = [[
.......11.........
......1221........
.....1dddd1.......
....1dddd1ddd1....
....1dd1ddddddd1..
....1dddddd11111..
.11..1dddd1.......
1221.1cccc1....11.
12221111111..1221.
.122221c22c11222 1
..1222212222122221
...12221222212221.
....1112222211 1..
.......1d22d1.....
.......122221.....
......1221.1221...
......1ff1..1ff1..
......111....111..
]],
  ten2 = [[
.......11.........
......1221........
.....1dddd1.......
....1dddd1ddd1....
....1dd1ddddddd1..
....1dddddd11111..
.....1dddd1.......
.....1cccc1.......
....111111111.....
1111121c22c1211111
1222212222122222 1
.122221222212222 1
..11112222211111..
.......1d22d1.....
.......122221.....
......1221.1221...
......1ff1..1ff1..
......111....111..
]],
  -- yurei ghost (front): white robe, long black hair, no feet
  yur1 = [[
.....11111....
....1111111...
...111111111..
...11cccccc11.
...11c1cc1c11.
...11cccccc11.
...1111cc1111.
..11cccccccc11
.1c1ccc1cccc1c
1c11ccc1cccc11
.1.1cccccccc1.
...1ccc1cccc1.
...1cccccccc1.
...1cccc1ccc1.
....1cccccc1..
.....1ccc1c1..
......1c1.1...
.......1......
]],
  yur2 = [[
.....11111....
....1111111...
...111111111..
...11cccccc11.
...11c1cc1c11.
...11cccccc11.
...1111cc1111.
..11cccccccc11
.1c1ccc1cccc1c
1c11ccc1cccc11
.1.1cccccccc1.
...1ccc1cccc1.
...1cccccccc1.
...1ccc1cccc1.
....1cccccc1..
....1c1ccc1...
.....1.1c1....
........1.....
]],
  -- onibi wisp
  wisp1 = [[
....c.....
...c3c....
..c33c3...
.c3cc3c3..
.c3cccc3c.
c3ccccc3c.
c3cc1c1c3.
.c3ccccc3.
..c33333..
...ccccc..
]],
  wisp2 = [[
.....c....
....c3c...
...3c33c..
..3c3cc3c.
.c3cccc3c.
.c3ccccc3c
.3c1c1cc3c
.3ccccc3c.
..33333c..
..ccccc...
]],
  -- oni (side, big): red skin, horns, tiger cloth, iron club
  oni1 = [[
.........c...c........
.........cc.cc........
........1dddddd1......
.......1dddddddd1.....
.......1dd1ddd1d1.....
.......1ddcdddcd1.....
.......1dddddddd1.....
.......1dd1cc1dd1.....
........1dddddd1......
.....11ddddddddd11....
....1ddddddddddddd1...
...1dd1dddddddd1dd1...
...1dd1dddddddd1dd1.1.
...1d11dddddddd11d1141
...1dd1fff1ff1f1dd1141
....11.f1ff1ff1.111441
.......ff1ff1ff..14441
.......1dd111dd1.14441
......1ddd1.1ddd114441
......1dd1...1dd1.1441
.....11dd1...1dd11.11.
.....1111.....1111....
]],
  oni_atk = [[
................1111..
...............14441..
.........c...c.144441.
.........cc.cc144441..
........1dddddd1441...
.......1dddddddd1.....
.......1dd1ddd1d1.....
.......1ddcdddcd1.....
.......1dddddddd1.....
.......1dd1cc1dd1.....
........1dddddd1d1....
.....11ddddddddd1d1...
....1ddddddddddddd1...
...1dd1dddddddd1......
...1dd1dddddddd1......
...1d11dddddddd1......
...1dd1fff1ff1f1......
....11.f1ff1ff1.......
.......ff1ff1ff.......
.......1dd111dd1......
......1ddd1.1ddd1.....
......1dd1...1dd1.....
.....11dd1...1dd11....
.....1111.....1111....
]],
  -- spider
  spi1 = [[
..1....11....1....
.1.1..1221..1.1...
1...11222211...1..
.1.1.122221.1.1...
..1.1222222 1.1...
...12d22d2221.....
..1.122222221.1...
.1.1..12221..1.1..
1...1..111..1...1.
.....1......1.....
]],
  spi2 = [[
.1.....11.....1...
1.1...1221...1.1..
...1.122221.1.....
..1.1222222 1.1...
.1.1222222221..1..
...12d22d2221.....
.1..122222221..1..
1.1...12221...1.1.
...1...111...1....
....1.......1.....
]],
  -- kitsune fox (side)
  fox1 = [[
................1.
...............191
.c............19c1
1cc1.........1999.
1c991.......1c991.
.19991111111999 1.
..19999999999c91..
...199999999991...
....19c99999c1....
....191.1991.91...
...191...191..91..
...11.....11...11.
]],
  fox2 = [[
................1.
...............191
..............19c1
.cc1.........1999.
1c991.......1c991.
1199911111119991..
..19999999999c91..
...199999999991...
....19c9999c91....
.....19119191.....
....191..191......
....11...11.......
]],
  -- orochi serpent head
  oro1 = [[
......111111........
....11555555 11.....
...1555555555551....
..15556555565551....
..1555d155d15551....
.1555555555555551...
.15555555555555551..
1555555555555555551.
155555c5c5c5c55551..
1555511111111111....
1555c5c5c5c51.......
.15555555555551.....
..1155555555551.....
....15555555551.....
....1555555551......
....155555551.......
...1555555551.......
...155555551........
..1555555551........
..155555551.........
]],
  oro2 = [[
......111111........
....11555555 11.....
...1555555555551....
..15556555565551....
..1555d155d15551....
.1555555555555551...
.15555555555555551..
1555555555555555551.
155555c5c5c5c5555 1.
15555dddddddddd1....
1555dddddddd1.......
155555c5c5c5c51.....
.1155555555555 1....
....15555555551.....
....1555555551......
....155555551.......
...1555555551.......
...155555551........
..1555555551........
..155555551.........
]],
  cat1 = [[
.1...1..
1a1.1a1.
1aaaaa1.
1a1a1a1.
1aaeaa1.
.1aaa11.
1aaaaaa1
1a1a1a11
]],
}

function Art.mobs()
  local order = { "oni1", "oni_atk", "oro1", "oro2", "ten1", "ten2", "wolf1", "wolf2", "boar1", "boar2",
    "spi1", "spi2", "fox1", "fox2", "vil_f1", "wom_f1", "eld_f1", "grd_f1", "lady_f1", "ban_s1", "ban_s2", "ban_atk",
    "yur1", "yur2", "kap1", "kap2", "kid_f1", "wisp1", "wisp2", "cat1" }
  for _, n in ipairs(order) do Gfx.add(n, MOBS[n]) end
end

-- ============================================================================
--  10 WORLD - deterministic open-world generation on the 240x112 cell map.
--
--  Per-cell arrays (index i = y*240 + x + 1):
--    WH  height in world units (multiples of 4, water = -4)
--    WT  ground tile id (mirrors the TIC map, used as the ground texture)
--    WO  static object id (OBJ table, 0 = none)
--    WF  flags (F_*)
--    WR  region index (REG)
--  1 cell = 8 world units. Rows 112..135 of the TIC map hold wall textures.
-- ============================================================================
W = { w = 240, h = 112 }
WH, WT, WO, WF, WR = {}, {}, {}, {}, {}
F_ROAD, F_TOWN, F_ROOF, F_MODEL, F_BRIDGE, F_NOSPAWN, F_WATER, F_SHALLOW, F_HAZ =
  1, 2, 4, 8, 16, 32, 64, 128, 256

REG = {
  { name = "Sakura Vale", x = 62, y = 86, rx = 36, ry = 20, base = 8, rough = 8, step = 4, biome = "sakura", music = 1 },
  { name = "Whispering Bamboo", x = 30, y = 56, rx = 27, ry = 24, base = 16, rough = 14, step = 8, biome = "bamboo", music = 2 },
  { name = "Kyo Plains", x = 118, y = 62, rx = 42, ry = 24, base = 12, rough = 8, step = 4, biome = "plains", music = 1 },
  { name = "Mount Fuyu", x = 116, y = 20, rx = 44, ry = 18, base = 36, rough = 20, step = 8, biome = "snow", music = 3 },
  { name = "Haunted Wood", x = 38, y = 20, rx = 26, ry = 16, base = 20, rough = 12, step = 8, biome = "haunted", music = 4 },
  { name = "Minato Coast", x = 198, y = 42, rx = 30, ry = 24, base = 8, rough = 8, step = 4, biome = "coast", music = 1 },
  { name = "Kappa Marsh", x = 176, y = 78, rx = 30, ry = 17, base = 4, rough = 4, step = 4, biome = "marsh", music = 2 },
  { name = "Onigashima", x = 216, y = 98, rx = 14, ry = 9, base = 12, rough = 14, step = 8, biome = "volcano", music = 5 },
}
RG_SAKURA, RG_BAMBOO, RG_PLAINS, RG_SNOW, RG_HAUNT, RG_COAST, RG_MARSH, RG_ONI = 1, 2, 3, 4, 5, 6, 7, 8

function cidx(x, y) return y * 240 + x + 1 end
function inmap(x, y) return x >= 0 and y >= 0 and x < 240 and y < 112 end

-- cell height with ocean outside the map
function cellH(x, y)
  if x < 0 or y < 0 or x >= 240 or y >= 112 then return -4 end
  return WH[y * 240 + x + 1]
end

function setTile(x, y, t)
  WT[y * 240 + x + 1] = t
  mset(x, y, t)
end

local SUMMIT_X, SUMMIT_Y = 122, 13

-- ---------------------------------------------------------------------------
-- terrain
-- ---------------------------------------------------------------------------
local function genTerrain()
  local nreg = #REG
  for y = 0, 111 do
    for x = 0, 239 do
      local i = y * 240 + x + 1
      local best, bm = 1, -1e9
      local sw, sb, sr = 0, 0, 0
      local mm = {}
      for r = 1, nreg do
        local R = REG[r]
        local dx, dy = (x - R.x) / R.rx, (y - R.y) / R.ry
        local m = 1 - (dx * dx + dy * dy)
        mm[r] = m
        if m > bm then bm, best = m, r end
        local w = m + 0.6
        if w > 0 then
          w = w * w * w
          sw = sw + w
          sb = sb + w * R.base
          sr = sr + w * R.rough
        end
      end
      local n = (fbm(x / 14, y / 14, 7, 3) - 0.5) * 0.8
      -- one continent (superellipse) plus the separate Onigashima island
      local ex, ey = math.abs(x - 112) / 110, math.abs(y - 54) / 52
      local cm = 1 - ex * ex * ex - ey * ey * ey
      local shore = cm * 1.3 + n
      if mm[RG_ONI] > -0.6 then shore = math.min(shore, -0.05) end
      if best == RG_ONI then shore = mm[RG_ONI] * 1.2 + n * 0.5 end
      WR[i] = best
      WO[i] = 0
      WF[i] = 0
      if shore <= 0 or x < 2 or y < 2 or x > 237 or y > 109 then
        WH[i] = -4
        WT[i] = T.OCEAN
        WF[i] = F_WATER
      else
        local base = sw > 0 and sb / sw or 8
        local rough = sw > 0 and sr / sw or 8
        local h = base + rough * (fbm(x / 9, y / 9, 3, 4) - 0.5) * 2.2
        local dx, dy = (x - SUMMIT_X), (y - SUMMIT_Y) * 1.6
        local d = math.sqrt(dx * dx + dy * dy)
        if d < 30 then h = h + 84 * (1 - d / 30) ^ 1.5 end
        local st = REG[best].step
        if h >= 44 then st = 12 end
        if shore < 0.08 then
          h = 0
        elseif shore < 0.16 then
          h = math.min(h, 4)
        end
        h = math.max(0, flr(h / st) * st)
        WH[i] = h
        WT[i] = T.GRASS1
      end
    end
  end
  -- remove one-cell spikes and pits
  for pass = 1, 2 do
    for y = 1, 110 do
      for x = 1, 238 do
        local i = y * 240 + x + 1
        local h = WH[i]
        if h >= 0 then
          local a, b, c, d = WH[i - 1], WH[i + 1], WH[i - 240], WH[i + 240]
          local lo = math.min(a, b, c, d)
          local hi = math.max(a, b, c, d)
          if h > hi then WH[i] = math.max(hi, 0) end
          if h < lo and lo >= 0 then WH[i] = lo end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- polyline carving helpers
-- ---------------------------------------------------------------------------
-- walk a polyline cell by cell, calling fn(x,y,t) (t = 0..1 along path)
local function walkPath(pts, fn, wiggle, seed)
  local cells = {}
  local total = 0
  for k = 1, #pts - 1 do
    total = total + dist(pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2])
  end
  local acc = 0
  local lx, ly
  for k = 1, #pts - 1 do
    local ax, ay, bx, by = pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]
    local L = dist(ax, ay, bx, by)
    local steps = math.max(1, flr(L * 2))
    for s = 0, steps do
      local t = s / steps
      local px, py = ax + (bx - ax) * t, ay + (by - ay) * t
      if wiggle then
        local q = (acc + L * t) / 6
        px = px + (vnoise(q, 0.5, seed) - 0.5) * wiggle
        py = py + (vnoise(q, 7.5, seed) - 0.5) * wiggle
      end
      local cx, cy = flr(px + 0.5), flr(py + 0.5)
      if cx ~= lx or cy ~= ly then
        cells[#cells + 1] = { cx, cy, (acc + L * t) / total }
        lx, ly = cx, cy
      end
    end
    acc = acc + L
  end
  for k = 1, #cells do fn(cells[k][1], cells[k][2], cells[k][3], k, cells) end
  return cells
end
W.walkPath = walkPath

local function carveWater(x, y, r, shallowEdge)
  for yy = y - r, y + r do
    for xx = x - r, x + r do
      if inmap(xx, yy) and (xx - x) ^ 2 + (yy - y) ^ 2 <= r * r + 0.5 then
        local i = cidx(xx, yy)
        WH[i] = -4
        WT[i] = T.WATER
        WF[i] = (WF[i] | F_WATER) & ~F_SHALLOW
        WO[i] = 0
      end
    end
  end
end

local RIVERS = {
  { { 130, 26 }, { 132, 40 }, { 140, 52 }, { 146, 64 }, { 152, 78 }, { 160, 92 }, { 164, 111 } },
  { { 80, 32 }, { 84, 46 }, { 92, 58 }, { 94, 70 }, { 88, 86 }, { 90, 98 }, { 92, 111 } },
  { { 22, 30 }, { 20, 46 }, { 16, 60 }, { 10, 78 }, { 0, 86 } },
  { { 176, 72 }, { 166, 84 }, { 162, 92 } },
}

local function genWater()
  for r = 1, #RIVERS do
    walkPath(RIVERS[r], function(x, y, t)
      local w = (t < 0.15) and 0 or 1
      carveWater(x, y, w)
    end, 5, 40 + r)
  end
  -- the Great Lake (Orochi) with an island in the middle
  for y = 60, 86 do
    for x = 160, 194 do
      local dx, dy = (x - 177) / 14, (y - 73) / 9
      local d = dx * dx + dy * dy + (vnoise(x / 4, y / 4, 77) - 0.5) * 0.3
      if d < 1 then carveWater(x, y, 0) end
    end
  end
  for y = 70, 76 do
    for x = 174, 180 do
      local dx, dy = (x - 177) / 3.6, (y - 73) / 3.2
      if dx * dx + dy * dy < 1 then
        local i = cidx(x, y)
        WH[i] = 4
        WT[i] = T.ROCK
        WF[i] = 0
      end
    end
  end
  -- marsh pools (shallow)
  for y = 62, 96 do
    for x = 150, 205 do
      local i = cidx(x, y)
      if WR[i] == RG_MARSH and WH[i] >= 0 and vnoise(x / 3, y / 3, 81) > 0.66 then
        WH[i] = 0
        WT[i] = T.SHALLOW
        WF[i] = WF[i] | F_SHALLOW
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- ground tiles by biome
-- ---------------------------------------------------------------------------
local function genTiles()
  for y = 0, 111 do
    for x = 0, 239 do
      local i = y * 240 + x + 1
      local h = WH[i]
      local t = WT[i]
      if h >= 0 and t ~= T.SHALLOW and t ~= T.WATER then
        local r = REG[WR[i]].biome
        local n = vnoise(x / 5, y / 5, 9)
        local v = hash2(x, y, 3)
        local g = (v < 0.4) and T.GRASS1 or (v < 0.8 and T.GRASS2 or T.GRASS3)
        -- beach: sand near ocean at low height
        local nearSea = false
        if h <= 4 then
          for dy = -2, 2 do
            for dx = -2, 2 do
              local xx, yy = x + dx, y + dy
              if inmap(xx, yy) and WT[cidx(xx, yy)] == T.OCEAN then nearSea = true end
            end
          end
        end
        if nearSea then
          t = T.SAND
        elseif r == "sakura" then
          t = n > 0.62 and T.SAKURA or (n < 0.2 and T.FLOWERS or g)
        elseif r == "bamboo" then
          t = n > 0.45 and T.BAMBOO or (n < 0.25 and T.FOREST or g)
        elseif r == "plains" then
          t = n > 0.7 and T.FLOWERS or g
        elseif r == "snow" then
          if h >= 40 or y < 20 then t = (v < 0.5) and T.SNOW1 or T.SNOW2
          elseif h >= 24 then t = n > 0.5 and T.ROCK or T.SNOW1
          else t = n > 0.55 and T.FOREST or g end
        elseif r == "haunted" then
          t = n > 0.55 and T.HAUNT or (n < 0.3 and T.MAPLE or T.FOREST)
        elseif r == "coast" then
          t = n > 0.65 and T.FOREST or g
        elseif r == "marsh" then
          t = n > 0.45 and T.MARSH or (n < 0.2 and T.MOSS or g)
        elseif r == "volcano" then
          t = n > 0.5 and T.ASH or T.ROCK
        end
        WT[i] = t
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- roads: smooth heights along the path (max one 4-unit step per cell)
-- ---------------------------------------------------------------------------
W.roads = {
  { { 62, 86 }, { 78, 84 }, { 98, 80 }, { 118, 74 } },                 -- Hanamura -> Kyo south
  { { 118, 44 }, { 112, 38 }, { 100, 33 }, { 92, 29 } },                -- Kyo north -> Yukimura
  { { 139, 60 }, { 160, 56 }, { 182, 47 }, { 198, 43 } },               -- Kyo east -> Minato
  { { 97, 60 }, { 76, 62 }, { 56, 66 }, { 38, 66 } },                   -- Kyo west -> Takemura
  { { 60, 84 }, { 48, 76 }, { 38, 68 } },                               -- Hanamura -> Takemura
  { { 198, 46 }, { 192, 58 }, { 190, 70 }, { 196, 82 }, { 200, 88 } },  -- Minato -> Oni bridge
  { { 94, 27 }, { 104, 22 }, { 112, 18 }, { 118, 15 }, { 121, 13 } },   -- Yukimura -> summit
  { { 36, 64 }, { 30, 48 }, { 34, 32 }, { 38, 20 } },                   -- Takemura -> haunted temple
  { { 32, 56 }, { 22, 50 }, { 17, 45 } },                               -- forest trail -> spider lair
}

local function layRoad(pts, tile, width)
  local cells = walkPath(pts, function() end, 3, 900 + #pts)
  -- target heights: start from terrain, then limit slope both directions
  local hs = {}
  for k = 1, #cells do
    local c = cells[k]
    hs[k] = math.max(0, cellH(c[1], c[2]))
  end
  for k = 2, #cells do if hs[k] > hs[k - 1] + 4 then hs[k] = hs[k - 1] + 4 end end
  for k = #cells - 1, 1, -1 do if hs[k] > hs[k + 1] + 4 then hs[k] = hs[k + 1] + 4 end end
  for k = 1, #cells do
    local cx, cy = cells[k][1], cells[k][2]
    for dy = -width, width do
      for dx = -width, width do
        local x, y = cx + dx, cy + dy
        if inmap(x, y) then
          local i = cidx(x, y)
          local water = (WF[i] & F_WATER) ~= 0
          if water then
            WH[i] = math.max(hs[k], 4)
            WT[i] = T.WOOD
            WF[i] = (WF[i] & ~F_WATER) | F_BRIDGE | F_ROAD
          elseif (WF[i] & F_BRIDGE) == 0 then
            if (WF[i] & F_TOWN) == 0 then WH[i] = hs[k] end
            if (WF[i] & F_TOWN) == 0 or WT[i] ~= T.PLAZA then WT[i] = tile end
            WF[i] = WF[i] | F_ROAD
          end
          WO[i] = 0
        end
      end
    end
  end
end
W.layRoad = layRoad

function W.gen()
  genTerrain()
  genWater()
  genTiles()
end

function W.genRoads()
  for r = 1, #W.roads do
    local pts = W.roads[r]
    local tile = (r == 7) and T.SNOWPATH or T.DIRT
    layRoad(pts, tile, 1)
  end
end

-- push WT to the TIC map + flags derived from tiles
function W.commit()
  for y = 0, 111 do
    for x = 0, 239 do
      local i = y * 240 + x + 1
      local t = WT[i]
      mset(x, y, t)
      if t == T.WATER or t == T.OCEAN then WF[i] = WF[i] | F_WATER end
      if t == T.SHALLOW or t == T.PADDY then WF[i] = WF[i] | F_SHALLOW end
      if t == T.LAVA then WF[i] = WF[i] | F_HAZ end
    end
  end
end

-- ============================================================================
--  11 BUILDINGS & MODELS - 3D structures drawn with z-buffered ttri.
--
--  A building's footprint becomes terrain cells raised to the eave height
--  (so walls are terrain side faces using a wall material, and collision /
--  climbing just work), flagged F_ROOF so their flat tops are skipped; the
--  sloped roof, gables and decals are a model. Pagodas/torii are pure models
--  (F_MODEL cells keep collision but draw nothing).
--
--  Model polygons: {n, x1,y1,z1, ..., u1,v1, ..., src, pm}
--    n = 3 or 4 vertices, src 0 = sprite sheet, 1 = map atlas band
-- ============================================================================
WM = {}          -- per-cell side material override
WB = {}          -- per-cell building id
BLD = {}         -- building records
MODELS = {}      -- all models
MCHUNK = {}      -- chunk index -> list of models

M_EARTH, M_ROCK, M_SNOW, M_SAND, M_STONE, M_HOUSE, M_PLASTER, M_WOOD, M_RED, M_DARK,
M_HAUNT, M_ASH, M_THATCH = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
MAT = {}
local function pm(t) return Pal.mk(t) end
function Build_initMats()
  MAT[M_EARTH] = { band = BAND.EARTH }
  MAT[M_ROCK] = { band = BAND.ROCK, pm = pm { [C_CREAM] = C_WHITE } }
  MAT[M_SNOW] = { band = BAND.ROCK, pm = pm { [C_CREAM] = C_WHITE, [C_WHITE] = C_WHITE } }
  MAT[M_SAND] = { band = BAND.SAND }
  MAT[M_STONE] = { band = BAND.STONE }
  MAT[M_HOUSE] = { band = BAND.HOUSE }
  MAT[M_PLASTER] = { band = BAND.PLASTER }
  MAT[M_WOOD] = { band = BAND.WOOD }
  MAT[M_RED] = { band = BAND.RED }
  MAT[M_DARK] = { band = BAND.DARK }
  MAT[M_HAUNT] = { band = BAND.EARTH, pm = pm { [C_GREEN] = C_INDIGO, [C_LIME] = C_GRAY, [C_DKGRN] = C_NIGHT } }
  MAT[M_ASH] = { band = BAND.ROCK, pm = pm { [C_CREAM] = C_NIGHT, [C_WHITE] = C_BROWN, [C_GRAY] = C_BROWN, [C_INDIGO] = C_NIGHT } }
  MAT[M_THATCH] = { band = BAND.THATCH }
  -- default side material per ground tile
  TMAT = {}
  for _, t in pairs(T) do TMAT[t] = M_EARTH end
  TMAT[T.SAND] = M_SAND
  TMAT[T.SNOW1], TMAT[T.SNOW2], TMAT[T.SNOWPATH] = M_SNOW, M_SNOW, M_SNOW
  TMAT[T.ROCK] = M_ROCK
  TMAT[T.STONE], TMAT[T.PLAZA], TMAT[T.GRAVEL] = M_STONE, M_STONE, M_STONE
  TMAT[T.WOOD] = M_WOOD
  TMAT[T.HAUNT] = M_HAUNT
  TMAT[T.ASH], TMAT[T.LAVA] = M_ASH, M_ASH
  TMAT[T.DARKWOOD] = M_DARK
  TMAT[T.ROOF] = M_HOUSE
end

local function addModel(m)
  MODELS[#MODELS + 1] = m
  local cx, cy = flr(m.cx / 64), flr(m.cy / 64)
  local k = cy * 30 + cx
  MCHUNK[k] = MCHUNK[k] or {}
  table.insert(MCHUNK[k], m)
  return m
end

-- quad helper: corners in drawing order (tl,tr,br,bl as seen from outside)
local function Q(m, a, b, c, d, uv, src, p)
  m.polys[#m.polys + 1] = { 4, a[1], a[2], a[3], b[1], b[2], b[3], c[1], c[2], c[3], d[1], d[2], d[3],
    uv[1], uv[2], uv[3], uv[4], uv[5], uv[6], uv[7], uv[8], src, p }
end
local function TRI(m, a, b, c, uv, src, p)
  m.polys[#m.polys + 1] = { 3, a[1], a[2], a[3], b[1], b[2], b[3], c[1], c[2], c[3],
    uv[1], uv[2], uv[3], uv[4], uv[5], uv[6], src, p }
end
Build_Q, Build_TRI = Q, TRI

-- wall quad between two ground points (x1,y1)->(x2,y2), from z0 up to z1,
-- textured from a band (u along wall length, v down from the band top)
local function wallQuad(m, x1, y1, x2, y2, z0, z1, band, p, uoff)
  local L = dist(x1, y1, x2, y2)
  local u0 = (uoff or 0) + x1 + y1
  local v0 = band.v
  local v1 = band.v + math.min(z1 - z0, band.h)
  Q(m, { x1, y1, z1 }, { x2, y2, z1 }, { x2, y2, z0 }, { x1, y1, z0 },
    { u0, v0, u0 + L, v0, u0 + L, v1, u0, v1 }, 1, p)
end

-- gable roof over world rect, ridge along x or y; o = overhang
local function gableRoof(m, X0, Y0, X1, Y1, zE, zR, ridgeX, o, band, p)
  local bv, bh = band.v, band.h
  if ridgeX then
    local Ym = (Y0 + Y1) / 2
    local half = (Y1 - Y0) / 2 + o
    local drop = (zR - zE) * o / ((Y1 - Y0) / 2)
    local ze = zE - drop
    local a0, a1 = X0 - o, X1 + o
    -- north slope (faces -y): from ridge (top) to north eave (bottom)
    Q(m, { a1, Ym, zR }, { a0, Ym, zR }, { a0, Y0 - o, ze }, { a1, Y0 - o, ze },
      { a1, bv, a0, bv, a0, bv + bh, a1, bv + bh }, 1, p)
    -- south slope
    Q(m, { a0, Ym, zR }, { a1, Ym, zR }, { a1, Y1 + o, ze }, { a0, Y1 + o, ze },
      { a0, bv, a1, bv, a1, bv + bh, a0, bv + bh }, 1, p)
    -- gable triangles (plaster band)
    local pb = BAND.PLASTER
    TRI(m, { X0, Ym, zR }, { X0, Y1, zE }, { X0, Y0, zE }, { Ym, pb.v, Y1, pb.v + 8, Y0, pb.v + 8 }, 1, nil)
    TRI(m, { X1, Ym, zR }, { X1, Y0, zE }, { X1, Y1, zE }, { Ym, pb.v, Y0, pb.v + 8, Y1, pb.v + 8 }, 1, nil)
    -- underside of eaves not drawn (camera is always above)
  else
    local Xm = (X0 + X1) / 2
    local drop = (zR - zE) * o / ((X1 - X0) / 2)
    local ze = zE - drop
    local a0, a1 = Y0 - o, Y1 + o
    Q(m, { Xm, a0, zR }, { Xm, a1, zR }, { X0 - o, a1, ze }, { X0 - o, a0, ze },
      { a0, bv, a1, bv, a1, bv + bh, a0, bv + bh }, 1, p)
    Q(m, { Xm, a1, zR }, { Xm, a0, zR }, { X1 + o, a0, ze }, { X1 + o, a1, ze },
      { a1, bv, a0, bv, a0, bv + bh, a1, bv + bh }, 1, p)
    local pb = BAND.PLASTER
    TRI(m, { Xm, Y0, zR }, { X0, Y0, zE }, { X1, Y0, zE }, { Xm, pb.v, X0, pb.v + 8, X1, pb.v + 8 }, 1, nil)
    TRI(m, { Xm, Y1, zR }, { X1, Y1, zE }, { X0, Y1, zE }, { Xm, pb.v, X1, pb.v + 8, X0, pb.v + 8 }, 1, nil)
  end
end

-- hip roof (4 slopes) with overhang, used by pagodas / castle tiers.
-- u follows the eave direction in world units, v runs ridge -> eave.
local function hipRoof(m, X0, Y0, X1, Y1, zE, zR, o, band, p)
  local B, Bv = band.v, band.v + band.h
  local cx, cy = (X0 + X1) / 2, (Y0 + Y1) / 2
  local W, D = X1 - X0, Y1 - Y0
  local e0x, e0y, e1x, e1y = X0 - o, Y0 - o, X1 + o, Y1 + o
  local ze = zE - 2
  local SW, SE, NE, NW = { e0x, e1y, ze }, { e1x, e1y, ze }, { e1x, e0y, ze }, { e0x, e0y, ze }
  if W >= D then
    local rx = (W - D) / 2
    local A, Bp = { cx - rx, cy, zR }, { cx + rx, cy, zR }
    Q(m, A, Bp, SE, SW, { A[1], B, Bp[1], B, SE[1], Bv, SW[1], Bv }, 1, p)
    Q(m, Bp, A, NW, NE, { Bp[1], B, A[1], B, NW[1], Bv, NE[1], Bv }, 1, p)
    TRI(m, Bp, NE, SE, { cy, B, NE[2], Bv, SE[2], Bv }, 1, p)
    TRI(m, A, SW, NW, { cy, B, SW[2], Bv, NW[2], Bv }, 1, p)
  else
    local ry = (D - W) / 2
    local A, Bp = { cx, cy - ry, zR }, { cx, cy + ry, zR }
    Q(m, Bp, A, NE, SE, { Bp[2], B, A[2], B, NE[2], Bv, SE[2], Bv }, 1, p)
    Q(m, A, Bp, SW, NW, { A[2], B, Bp[2], B, SW[2], Bv, NW[2], Bv }, 1, p)
    TRI(m, Bp, SE, SW, { cx, B, SE[1], Bv, SW[1], Bv }, 1, p)
    TRI(m, A, NW, NE, { cx, B, NW[1], Bv, NE[1], Bv }, 1, p)
  end
end

-- box walls (4 sides) from z0 to z1 with a band
local function boxWalls(m, X0, Y0, X1, Y1, z0, z1, band, p)
  wallQuad(m, X0, Y1, X1, Y1, z0, z1, band, p)   -- south
  wallQuad(m, X1, Y0, X0, Y0, z0, z1, band, p)   -- north
  wallQuad(m, X1, Y1, X1, Y0, z0, z1, band, p)   -- east
  wallQuad(m, X0, Y0, X0, Y1, z0, z1, band, p)   -- west
end
Build_box = boxWalls

-- decal: a sprite rect placed flat against a wall plane
-- (x,y) ground point at the wall, facing dir ('s','n','e','w'), bottom z
function Build_decal(m, name, x, y, z, face, sc, pmt)
  local r = SPR[name]
  if not r then return end
  sc = sc or 1
  local w, h = r[3] * sc, r[4] * sc / Cam.cp
  local e = 0.4
  local ax, ay, bx, by
  if face == "s" then ax, ay, bx, by = x - w / 2, y + e, x + w / 2, y + e
  elseif face == "n" then ax, ay, bx, by = x + w / 2, y - e, x - w / 2, y - e
  elseif face == "e" then ax, ay, bx, by = x + e, y + w / 2, x + e, y - w / 2
  else ax, ay, bx, by = x - e, y - w / 2, x - e, y + w / 2 end
  local u, v = r[1], r[2]
  Q(m, { ax, ay, z + h }, { bx, by, z + h }, { bx, by, z }, { ax, ay, z },
    { u, v, u + r[3], v, u + r[3], v + r[4], u, v + r[4] }, 0, pmt and Pal.mk(pmt) or nil)
end

-- ---------------------------------------------------------------------------
-- placement
-- ---------------------------------------------------------------------------
-- flatten a cell rect to height h (keeps water out)
function Build_flatten(x0, y0, w, d, h, tile)
  for y = y0, y0 + d - 1 do
    for x = x0, x0 + w - 1 do
      if inmap(x, y) then
        local i = cidx(x, y)
        WH[i] = h
        WF[i] = WF[i] & ~(F_WATER | F_SHALLOW)
        if tile then WT[i] = tile end
        WO[i] = 0
      end
    end
  end
end

-- building kinds -> look
local KIND = {
  house = { wall = 24, roof = 14, band = "ROOF", mat = M_HOUSE },
  farm = { wall = 24, roof = 16, band = "THATCH", mat = M_HOUSE },
  shop = { wall = 24, roof = 14, band = "ROOF", mat = M_HOUSE, sign = "noren" },
  inn = { wall = 24, roof = 16, band = "ROOF", mat = M_HOUSE, sign = "noren", signpm = { [C_INDIGO] = C_RED, [C_WHITE] = C_CREAM } },
  dojo = { wall = 24, roof = 18, band = "ROOF", mat = M_HOUSE, sign = "dojo_sign" },
  temple = { wall = 24, roof = 20, band = "ROOF", mat = M_DARK },
  smith = { wall = 24, roof = 14, band = "ROOF", mat = M_HOUSE, sign = "noren", signpm = { [C_INDIGO] = C_NIGHT, [C_WHITE] = C_GOLD } },
  storehouse = { wall = 16, roof = 12, band = "ROOF", mat = M_PLASTER },
}

-- add a building; x,y = NW cell, w,d in cells, base height, door side
function Build_add(kind, x, y, w, d, base, door, opt)
  local K = KIND[kind]
  opt = opt or {}
  local id = #BLD + 1
  local wallH = opt.wall or K.wall
  local roofH = opt.roof or K.roof
  local b = { id = id, kind = kind, x = x, y = y, w = w, d = d, base = base, wall = wallH,
    roof = roofH, door = door or "s", name = opt.name }
  BLD[id] = b
  -- clear a 1-cell margin around at the base height
  for yy = y - 1, y + d do
    for xx = x - 1, x + w do
      if inmap(xx, yy) then
        local i = cidx(xx, yy)
        if (WF[i] & F_ROOF) == 0 then
          WH[i] = base
          WF[i] = (WF[i] | F_NOSPAWN) & ~(F_WATER | F_SHALLOW)
          WO[i] = 0
        end
      end
    end
  end
  for yy = y, y + d - 1 do
    for xx = x, x + w - 1 do
      local i = cidx(xx, yy)
      WH[i] = base + wallH
      WF[i] = WF[i] | F_ROOF | F_NOSPAWN
      WT[i] = T.ROOF
      WM[i] = K.mat
      WB[i] = id
    end
  end
  local X0, Y0, X1, Y1 = x * 8, y * 8, (x + w) * 8, (y + d) * 8
  local m = { polys = {}, cx = (X0 + X1) / 2, cy = (Y0 + Y1) / 2, r = math.max(X1 - X0, Y1 - Y0) }
  local ridgeX = w >= d
  b.ridgeX = ridgeX
  local zE, zR = base + wallH, base + wallH + roofH
  local band = BAND[K.band]
  local p = opt.pm
  gableRoof(m, X0, Y0, X1, Y1, zE, zR, ridgeX, 3, band, p)
  -- door + signage decals on the door side
  local dx, dy
  if door == "s" then dx, dy = (X0 + X1) / 2, Y1
  elseif door == "n" then dx, dy = (X0 + X1) / 2, Y0
  elseif door == "e" then dx, dy = X1, (Y0 + Y1) / 2
  else dx, dy = X0, (Y0 + Y1) / 2 end
  Build_decal(m, K.sign or "door", dx, dy, base, door, 1, K.signpm)
  b.doorX, b.doorY = dx + (door == "e" and 6 or (door == "w" and -6 or 0)),
    dy + (door == "s" and 6 or (door == "n" and -6 or 0))
  b.model = addModel(m)
  return b
end

-- roof surface height at world point (for walking on roofs)
function Build_roofH(b, x, y)
  local zE = b.base + b.wall
  local X0, Y0, X1, Y1 = b.x * 8, b.y * 8, (b.x + b.w) * 8, (b.y + b.d) * 8
  local t
  if b.ridgeX then
    local half = (Y1 - Y0) / 2
    t = 1 - math.abs(y - (Y0 + Y1) / 2) / half
  else
    local half = (X1 - X0) / 2
    t = 1 - math.abs(x - (X0 + X1) / 2) / half
  end
  if t < 0 then t = 0 end
  return zE + b.roof * t
end

-- pagoda tower: n tiers, footprint s x s cells; climbable column
function Build_pagoda(x, y, base, tiers, s, opt)
  opt = opt or {}
  local X0, Y0 = x * 8, y * 8
  local S = s * 8
  local m = { polys = {}, cx = X0 + S / 2, cy = Y0 + S / 2, r = S * 1.5 }
  local z = base
  local inset = 0
  local tierH, roofH = opt.tierH or 16, opt.roofH or 8
  local band = BAND[opt.band or "PLASTER"]
  for t = 1, tiers do
    local a0, b0 = X0 + inset, Y0 + inset
    local a1, b1 = X0 + S - inset, Y0 + S - inset
    boxWalls(m, a0, b0, a1, b1, z, z + tierH, band, opt.pm)
    local zr = z + tierH + roofH
    hipRoof(m, a0, b0, a1, b1, z + tierH, zr, 5, BAND.ROOF, opt.roofpm)
    z = z + tierH + roofH - 4
    inset = inset + (opt.shrink or 2)
  end
  -- spire
  local cx, cy = X0 + S / 2, Y0 + S / 2
  boxWalls(m, cx - 1, cy - 1, cx + 1, cy + 1, z, z + 14, BAND.WOOD, Pal.mk { [C_WOOD] = C_GOLD, [C_BROWN] = C_WOOD, [C_TAN] = C_GOLD })
  local top = z + 2
  for yy = y, y + s - 1 do
    for xx = x, x + s - 1 do
      local i = cidx(xx, yy)
      WH[i] = top
      WF[i] = WF[i] | F_MODEL | F_NOSPAWN
      WO[i] = 0
    end
  end
  m.top = top
  return addModel(m)
end

-- torii gate: two posts and two beams across x (or y if rot)
function Build_torii(cx, cy, base, rot, size)
  size = size or 1
  local m = { polys = {}, cx = cx, cy = cy, r = 32 * size }
  local hw, H = 12 * size, 30 * size
  local px1, py1, px2, py2
  if rot then px1, py1, px2, py2 = cx, cy - hw, cx, cy + hw
  else px1, py1, px2, py2 = cx - hw, cy, cx + hw, cy end
  local rb = BAND.RED
  boxWalls(m, px1 - 1.5, py1 - 1.5, px1 + 1.5, py1 + 1.5, base, base + H, rb)
  boxWalls(m, px2 - 1.5, py2 - 1.5, px2 + 1.5, py2 + 1.5, base, base + H, rb)
  local ex = rot and 0 or 6 * size
  local ey = rot and 6 * size or 0
  -- kasagi (top beam, dark) and nuki (lower beam, red)
  boxWalls(m, math.min(px1, px2) - ex - 1.5, math.min(py1, py2) - ey - 1.5,
    math.max(px1, px2) + ex + 1.5, math.max(py1, py2) + ey + 1.5, base + H, base + H + 4, BAND.DARK)
  Q(m, { math.min(px1, px2) - ex - 1.5, math.min(py1, py2) - ey - 1.5, base + H + 4 },
    { math.max(px1, px2) + ex + 1.5, math.min(py1, py2) - ey - 1.5, base + H + 4 },
    { math.max(px1, px2) + ex + 1.5, math.max(py1, py2) + ey + 1.5, base + H + 4 },
    { math.min(px1, px2) - ex - 1.5, math.max(py1, py2) + ey + 1.5, base + H + 4 },
    { 0, BAND.DARK.v, 8, BAND.DARK.v, 8, BAND.DARK.v + 2, 0, BAND.DARK.v + 2 }, 1, nil)
  local ix = rot and 0 or 2
  local iy = rot and 2 or 0
  boxWalls(m, math.min(px1, px2) - ix - 1, math.min(py1, py2) - iy - 1,
    math.max(px1, px2) + ix + 1, math.max(py1, py2) + iy + 1, base + H - 9, base + H - 6, rb)
  -- posts are solid
  for _, p in ipairs({ { px1, py1 }, { px2, py2 } }) do
    local i = cidx(flr(p[1] / 8), flr(p[2] / 8))
    WO[i] = O_POST
  end
  return addModel(m)
end

-- castle keep on an ishigaki base: tiers of plaster + hip roofs
function Build_castle(x, y, w, d, base)
  -- stone base cells (terrain)
  for yy = y, y + d - 1 do
    for xx = x, x + w - 1 do
      local i = cidx(xx, yy)
      WH[i] = base + 16
      WT[i] = T.PLAZA
      WM[i] = M_STONE
      WF[i] = WF[i] | F_NOSPAWN
      WO[i] = 0
    end
  end
  local z = base + 16
  local X0, Y0, X1, Y1 = (x + 1) * 8, (y + 1) * 8, (x + w - 1) * 8, (y + d - 1) * 8
  -- keep cells (first tier) are terrain with plaster walls
  for yy = y + 1, y + d - 2 do
    for xx = x + 1, x + w - 2 do
      local i = cidx(xx, yy)
      WH[i] = z + 16
      WM[i] = M_PLASTER
      WF[i] = WF[i] | F_ROOF
      WT[i] = T.ROOF
    end
  end
  local m = { polys = {}, cx = (X0 + X1) / 2, cy = (Y0 + Y1) / 2, r = 120 }
  local b = { id = #BLD + 1, kind = "castle", x = x + 1, y = y + 1, w = w - 2, d = d - 2, base = z, wall = 16, roof = 0, ridgeX = true }
  BLD[b.id] = b
  for yy = y + 1, y + d - 2 do for xx = x + 1, x + w - 2 do WB[cidx(xx, yy)] = b.id end end
  hipRoof(m, X0, Y0, X1, Y1, z + 16, z + 26, 5, BAND.ROOF)
  local inset = 6
  local zz = z + 22
  for t = 1, 2 do
    local a0, b0, a1, b1 = X0 + inset, Y0 + inset, X1 - inset, Y1 - inset
    boxWalls(m, a0, b0, a1, b1, zz, zz + 16, BAND.PLASTER)
    hipRoof(m, a0, b0, a1, b1, zz + 16, zz + 26, 5, BAND.ROOF)
    zz = zz + 22
    inset = inset + 6
  end
  -- golden ridge ornaments
  b.top = zz
  m.orn = { (X0 + X1) / 2, (Y0 + Y1) / 2, zz + 4 }
  b.model = addModel(m)
  return b
end

-- ============================================================================
--  12 OBJECTS - static world objects stored per cell in WO[i].
--  Each type: sprite, palette remap, collision cylinder (r, h), harvesting
--  (tool, hits, drops, what it becomes, regrow time in frames), light radius.
--  Solid objects take part in ground height: you can stand on rocks/stumps.
-- ============================================================================
OBJ = {}
O_TREE, O_SAKURA, O_MAPLE, O_PINE, O_SNOWPINE, O_BAMBOO, O_WILLOW, O_DEAD = 1, 2, 3, 4, 5, 6, 7, 8
O_ROCK, O_BOULDER, O_ORE, O_GRASS, O_FLOWER, O_BUSH, O_BUSHE, O_MUSH = 9, 10, 11, 12, 13, 14, 15, 16
O_REEDS, O_HERB, O_RICE, O_STUMP, O_GRASSCUT, O_TORO, O_JIZO, O_GRAVE = 17, 18, 19, 20, 21, 22, 23, 24
O_FENCE, O_CRATE, O_BARREL, O_SIGN, O_BANNER, O_POST, O_CHEST, O_CHESTO = 25, 26, 27, 28, 29, 30, 31, 32
O_KODAMA, O_HOKORA, O_WELL, O_FIRE, O_POT, O_BSTUMP, O_CHOCHIN, O_WEB = 33, 34, 35, 36, 37, 38, 39, 40
O_BONES, O_STATUE, O_FLOWER2, O_FLOWER3, O_LOGS, O_SAPLING = 41, 42, 43, 44, 45, 46

local DAY = 60 * 60 * 6 -- frames per in-game day (6 minutes)
OBJ_DAY = DAY

function Objects_init()
  local P = Pal.mk
  local function def(id, t) OBJ[id] = t end
  def(O_TREE, { spr = "tree", r = 3, h = 60, tool = "axe", hits = 4, drop = { { "wood", 2, 3 } }, after = O_STUMP, regrow = DAY * 3, shadow = 10, name = "Tree" })
  def(O_SAKURA, { spr = "tree", pm = P { [C_LIME] = C_WHITE, [C_GREEN] = C_PINK, [C_DKGRN] = C_RED }, r = 3, h = 60, tool = "axe", hits = 4,
    drop = { { "wood", 2, 3 }, { "petal", 0, 2 } }, after = O_STUMP, regrow = DAY * 3, shadow = 10, name = "Sakura" })
  def(O_MAPLE, { spr = "tree", pm = P { [C_LIME] = C_GOLD, [C_GREEN] = C_RED, [C_DKGRN] = C_BROWN }, r = 3, h = 60, tool = "axe", hits = 4,
    drop = { { "wood", 2, 3 } }, after = O_STUMP, regrow = DAY * 3, shadow = 10, name = "Maple" })
  def(O_PINE, { spr = "pine", r = 3, h = 60, tool = "axe", hits = 4, drop = { { "wood", 2, 3 }, { "pinecone", 0, 1 } }, after = O_STUMP, regrow = DAY * 3, shadow = 7, name = "Pine" })
  def(O_SNOWPINE, { spr = "pine", pm = P { [C_GREEN] = C_WHITE, [C_DKGRN] = C_DKGRN }, r = 3, h = 60, tool = "axe", hits = 4, drop = { { "wood", 2, 3 } }, after = O_STUMP, regrow = DAY * 4, shadow = 7, name = "Pine" })
  def(O_BAMBOO, { spr = "bamboo", r = 3, h = 60, tool = "cut", hits = 2, drop = { { "bamboo", 2, 3 }, { "shoot", 0, 1 } }, after = O_BSTUMP, regrow = DAY * 2, shadow = 6, name = "Bamboo" })
  def(O_WILLOW, { spr = "willow", r = 3, h = 60, tool = "axe", hits = 4, drop = { { "wood", 2, 3 } }, after = O_STUMP, regrow = DAY * 3, shadow = 9, name = "Willow" })
  def(O_DEAD, { spr = "deadtree", r = 3, h = 40, tool = "axe", hits = 2, drop = { { "wood", 1, 2 } }, after = O_STUMP, regrow = DAY * 5, shadow = 6, name = "Dead tree" })
  def(O_ROCK, { spr = "rock", r = 4, h = 5, tool = "pick", hits = 2, drop = { { "stone", 1, 2 }, { "flint", 0, 1 } }, after = 0, regrow = DAY * 4, shadow = 5, name = "Rock" })
  def(O_BOULDER, { spr = "boulder", r = 7, h = 12, tool = "pick", hits = 4, drop = { { "stone", 2, 4 }, { "flint", 1, 2 } }, after = O_ROCK, regrow = DAY * 5, shadow = 8, name = "Boulder" })
  def(O_ORE, { spr = "ore", r = 7, h = 12, tool = "pick", hits = 5, drop = { { "stone", 1, 2 }, { "iron", 1, 2 }, { "gold", 0, 1 } }, after = O_ROCK, regrow = DAY * 6, shadow = 8, name = "Iron ore" })
  def(O_GRASS, { spr = "grass", tool = "cut", hits = 1, drop = { { "grass", 1, 2 } }, after = O_GRASSCUT, regrow = DAY, name = "Tall grass", hand = true })
  def(O_GRASSCUT, { spr = "grasscut", regrow = DAY, after = O_GRASS, grow = true })
  def(O_FLOWER, { spr = "flower", hand = true, drop = { { "flower", 1, 1 } }, after = 0, regrow = DAY * 2, name = "Flower" })
  def(O_FLOWER2, { spr = "flower", pm = P { [C_PINK] = C_WHITE, [C_RED] = C_GOLD }, hand = true, drop = { { "flower", 1, 1 } }, after = 0, name = "Flower" })
  def(O_FLOWER3, { spr = "flower", pm = P { [C_PINK] = C_GOLD, [C_RED] = C_BLUE, [C_GOLD] = C_WHITE }, hand = true, drop = { { "flower", 1, 1 } }, after = 0, name = "Flower" })
  def(O_BUSH, { spr = "bush", hand = true, drop = { { "berries", 2, 3 } }, after = O_BUSHE, regrow = DAY * 2, shadow = 6, name = "Berry bush" })
  def(O_BUSHE, { spr = "bush_empty", after = O_BUSH, regrow = DAY * 2, grow = true, shadow = 6 })
  def(O_MUSH, { spr = "mushroom", hand = true, drop = { { "mushroom", 1, 1 } }, after = 0, name = "Mushroom" })
  def(O_REEDS, { spr = "reeds", tool = "cut", hits = 1, drop = { { "reed", 1, 2 } }, after = O_GRASSCUT, regrow = DAY * 2, name = "Reeds" })
  def(O_HERB, { spr = "herb", hand = true, drop = { { "herb", 1, 1 } }, after = 0, name = "Wild herb" })
  def(O_RICE, { spr = "rice", hand = true, drop = { { "rice", 1, 2 } }, after = O_GRASSCUT, regrow = DAY * 2, name = "Rice" })
  def(O_STUMP, { spr = "stump", r = 4, h = 4, tool = "axe", hits = 1, drop = { { "wood", 1, 1 } }, after = 0, shadow = 5, name = "Stump" })
  def(O_BSTUMP, { spr = "bamboostump" })
  def(O_SAPLING, { spr = "herb", pm = P { [C_LIME] = C_GREEN }, grow = true })
  def(O_TORO, { spr = "toro", r = 4, h = 14, light = 34, shadow = 5, name = "Stone lantern" })
  def(O_JIZO, { spr = "jizo", r = 3, h = 10, shadow = 4, name = "Jizo statue", talk = "jizo" })
  def(O_GRAVE, { spr = "grave", r = 3, h = 10, shadow = 4, name = "Grave" })
  def(O_FENCE, { spr = "fence", r = 4, h = 8, name = "Fence" })
  def(O_CRATE, { spr = "crate", r = 4, h = 9, tool = "any", hits = 1, drop = { { "ryo", 1, 3 } }, after = 0, shadow = 5, name = "Crate" })
  def(O_BARREL, { spr = "barrel", r = 3, h = 9, tool = "any", hits = 1, drop = { { "ryo", 0, 2 }, { "rice", 0, 1 } }, after = 0, shadow = 4, name = "Barrel" })
  def(O_SIGN, { spr = "sign", r = 2, h = 10, talk = "sign", name = "Signpost" })
  def(O_BANNER, { spr = "banner", r = 1, h = 20 })
  def(O_POST, { r = 2, h = 30 })
  def(O_CHEST, { spr = "chest", r = 5, h = 8, talk = "chest", shadow = 6, name = "Chest" })
  def(O_CHESTO, { spr = "chest_open", r = 5, h = 8, shadow = 6 })
  def(O_KODAMA, { anim = { "kodama1", "kodama2" }, talk = "kodama", name = "Kodama", bob = true })
  def(O_HOKORA, { spr = "hokora", r = 6, h = 14, talk = "shrine", shadow = 8, name = "Spirit shrine" })
  def(O_WELL, { spr = "well", r = 6, h = 10, shadow = 7, name = "Well" })
  def(O_FIRE, { anim = { "fire1", "fire2" }, r = 4, h = 4, light = 52, talk = "fire", shadow = 6, name = "Campfire" })
  def(O_LOGS, { spr = "logs", r = 4, h = 4, talk = "logs", shadow = 6, name = "Burnt campfire" })
  def(O_POT, { spr = "pot", r = 4, h = 8, talk = "pot", shadow = 5, name = "Cooking pot" })
  def(O_CHOCHIN, { spr = "chochin", r = 1, h = 16, light = 30, name = "Lantern" })
  def(O_WEB, { spr = "web", name = "Spider web" })
  def(O_BONES, { spr = "bones" })
  def(O_STATUE, { spr = "statue", r = 5, h = 18, talk = "statue", shadow = 7, name = "Kannon statue" })
end

-- world position of a cell's object (jittered, deterministic)
function objPos(i)
  local x = OX[i]
  if x then return x, OY[i] end
  local cx, cy = (i - 1) % 240, (i - 1) // 240
  return cx * 8 + 4, cy * 8 + 4
end

function setObj(x, y, o, jitter)
  local i = cidx(x, y)
  WO[i] = o
  if jitter then
    OX[i] = x * 8 + 4 + (hash2(x, y, 5) - 0.5) * jitter
    OY[i] = y * 8 + 4 + (hash2(x, y, 6) - 0.5) * jitter
  else
    OX[i], OY[i] = nil, nil
  end
  local k = (y // 8) * 30 + (x // 8)
  local l = OLIST[k]
  if not l then l = {} OLIST[k] = l end
  if not l[i] then l[i] = true end
end

-- ---------------------------------------------------------------------------
-- scatter by biome
-- ---------------------------------------------------------------------------
local SCATTER = {
  sakura = { { O_SAKURA, 0.035, 0.55 }, { O_TREE, 0.015, 0.5 }, { O_GRASS, 0.07 }, { O_FLOWER, 0.025 }, { O_FLOWER2, 0.015 },
    { O_BUSH, 0.01 }, { O_ROCK, 0.008 }, { O_HERB, 0.006 }, { O_BOULDER, 0.003 } },
  bamboo = { { O_BAMBOO, 0.16, 0.45 }, { O_TREE, 0.01 }, { O_GRASS, 0.05 }, { O_MUSH, 0.008 }, { O_ROCK, 0.01 }, { O_BUSH, 0.008 }, { O_HERB, 0.006 } },
  plains = { { O_TREE, 0.02, 0.55 }, { O_SAKURA, 0.005 }, { O_GRASS, 0.08 }, { O_FLOWER, 0.015 }, { O_FLOWER3, 0.01 }, { O_BUSH, 0.01 }, { O_ROCK, 0.008 }, { O_BOULDER, 0.004 }, { O_HERB, 0.005 } },
  snow = { { O_SNOWPINE, 0.05, 0.5 }, { O_ROCK, 0.02 }, { O_BOULDER, 0.012 }, { O_ORE, 0.008 } },
  haunted = { { O_MAPLE, 0.05, 0.5 }, { O_DEAD, 0.03 }, { O_GRAVE, 0.006 }, { O_MUSH, 0.02 }, { O_GRASS, 0.04 }, { O_BONES, 0.004 }, { O_ROCK, 0.01 } },
  coast = { { O_PINE, 0.04, 0.55 }, { O_GRASS, 0.06 }, { O_ROCK, 0.015 }, { O_BOULDER, 0.006 }, { O_BUSH, 0.01 }, { O_FLOWER2, 0.01 } },
  marsh = { { O_WILLOW, 0.035, 0.5 }, { O_REEDS, 0.09 }, { O_MUSH, 0.015 }, { O_GRASS, 0.04 }, { O_HERB, 0.008 } },
  volcano = { { O_DEAD, 0.04 }, { O_ROCK, 0.03 }, { O_ORE, 0.012 }, { O_BOULDER, 0.015 } },
}

function Objects_scatter()
  for y = 1, 110 do
    for x = 1, 238 do
      local i = y * 240 + x + 1
      local f = WF[i]
      if WO[i] == 0 and (f & (F_WATER | F_ROAD | F_TOWN | F_ROOF | F_MODEL | F_NOSPAWN | F_BRIDGE)) == 0 and WH[i] >= 0 then
        local t = WT[i]
        if t ~= T.SAND and t ~= T.SHALLOW then
          local list = SCATTER[REG[WR[i]].biome]
          local r = hash2(x, y, 101)
          local forest = vnoise(x / 7, y / 7, 55)
          local acc = 0
          for k = 1, #list do
            local e = list[k]
            local p = e[2]
            if e[3] then p = p * (forest > e[3] and 2.6 or 0.25) end
            acc = acc + p
            if r < acc then
              local o = e[1]
              if t == T.PADDY then o = O_RICE end
              setObj(x, y, o, 4)
              break
            end
          end
          if WT[i] == T.PADDY and WO[i] == 0 and hash2(x, y, 7) < 0.6 then setObj(x, y, O_RICE, 3) end
        elseif t == T.SAND and hash2(x, y, 102) < 0.01 then
          setObj(x, y, O_ROCK, 4)
        elseif t == T.SHALLOW and hash2(x, y, 103) < 0.12 then
          setObj(x, y, O_REEDS, 4)
        end
      end
    end
  end
end

-- ============================================================================
--  13 TOWNS & LANDMARKS - hand-designed settlements and points of interest
--  stamped onto the generated terrain. Registers POIs, NPC spawns, towers,
--  shrines, chests, kodama and enemy camps used by quests and the map.
-- ============================================================================
TOWNS = {}
POI = {}         -- POI.name = {x, y, name} in world units
NPCSPAWN = {}    -- {kind, x, y, data}
TOWERS = {}      -- pagodas: climb + interact on top to reveal map / fast travel
SHRINES = {}     -- spirit shrines (trials -> spirit orbs)
KODAMA = {}      -- cell indices of hidden kodama
CHESTS = {}      -- cell indices of chests

local function poi(name, cx, cy, extra)
  local p = { x = cx * 8 + 4, y = cy * 8 + 4, name = name, cx = cx, cy = cy }
  if extra then for k, v in pairs(extra) do p[k] = v end end
  POI[name] = p
  return p
end

local function area(x0, y0, w, d, h, tile, flag)
  for y = y0, y0 + d - 1 do
    for x = x0, x0 + w - 1 do
      if inmap(x, y) then
        local i = cidx(x, y)
        if (WF[i] & (F_ROOF | F_MODEL)) == 0 then
          WH[i] = h
          WF[i] = (WF[i] | (flag or 0)) & ~(F_WATER | F_SHALLOW)
          if tile then WT[i] = tile end
          WO[i] = 0
        end
      end
    end
  end
end
Town_area = area

local function tiles(x0, y0, w, d, tile)
  for y = y0, y0 + d - 1 do
    for x = x0, x0 + w - 1 do
      if inmap(x, y) and (WF[cidx(x, y)] & (F_ROOF | F_MODEL)) == 0 then WT[cidx(x, y)] = tile end
    end
  end
end

local function obj(x, y, o, j) setObj(x, y, o, j) end
local function npc(kind, x, y, data)
  NPCSPAWN[#NPCSPAWN + 1] = { kind = kind, x = x * 8 + 4, y = y * 8 + 4, data = data or {} }
end
local function chest(x, y, item, n)
  obj(x, y, O_CHEST)
  local i = cidx(x, y)
  World.chests[i] = { item, n }
  CHESTS[#CHESTS + 1] = i
end
local function kodama(x, y)
  obj(x, y, O_KODAMA)
  KODAMA[#KODAMA + 1] = cidx(x, y)
end
local function sign(x, y, text)
  obj(x, y, O_SIGN)
  World.signs[cidx(x, y)] = text
end

local function baseHeight(x0, y0, w, d)
  local s = {}
  for y = y0, y0 + d - 1 do
    for x = x0, x0 + w - 1 do
      local h = cellH(x, y)
      if h >= 0 then s[#s + 1] = h end
    end
  end
  table.sort(s)
  return s[math.max(1, #s // 2)] or 8
end
Town_baseHeight = baseHeight

local function tower(name, x, y, tiers)
  local h = baseHeight(x - 1, y - 1, 5, 5)
  area(x - 1, y - 1, 5, 5, h, T.GRAVEL, F_NOSPAWN)
  local m = Build_pagoda(x, y, h, tiers or 4, 3, { band = "PLASTER" })
  local t = { name = name, x = x * 8 + 12, y = y * 8 + 12, top = m.top, id = #TOWERS + 1, cx = x + 1, cy = y + 1 }
  TOWERS[#TOWERS + 1] = t
  return t
end

-- rock spire (terrain column) - platforming
local function spire(x, y, h, w)
  w = w or 1
  local base = math.max(0, baseHeight(x, y, w, w))
  for yy = y, y + w - 1 do
    for xx = x, x + w - 1 do
      local i = cidx(xx, yy)
      WH[i] = base + h
      WT[i] = T.ROCK
      WF[i] = (WF[i] | F_NOSPAWN) & ~(F_WATER | F_SHALLOW)
      WO[i] = 0
    end
  end
  return base + h
end
Town_spire = spire

local function shrine(x, y, name, trial)
  local h = baseHeight(x - 2, y - 2, 5, 5)
  area(x - 3, y - 3, 7, 7, h, T.GRAVEL, F_NOSPAWN)
  obj(x, y - 1, O_HOKORA)
  obj(x - 2, y + 1, O_TORO)
  obj(x + 2, y + 1, O_TORO)
  Build_torii(x * 8 + 4, (y + 3) * 8 + 4, h, false, 0.8)
  local s = { name = name, x = x * 8 + 4, y = (y - 1) * 8 + 4, id = #SHRINES + 1, cx = x, cy = y - 1, trial = trial or "combat", h = h }
  SHRINES[#SHRINES + 1] = s
  if trial == "spires" then
    -- a ring of rising pillars with the orb pedestal on the last one
    local hs = { 8, 16, 24, 30, 38 }
    for k = 1, #hs do
      local a = k / #hs * TAU * 0.8 + 0.6
      local px, py = x + flr(math.cos(a) * 6), y + flr(math.sin(a) * 5) - 1
      local top = spire(px, py, hs[k], 1)
      if k == #hs then s.top = { px, py, top } end
    end
  end
  return s
end

local function house(kind, x, y, w, d, h, door, opt) return Build_add(kind, x, y, w, d, h, door, opt) end

-- snow-covered thatch / dark roofs via palette maps
local PM_SNOWROOF = { [C_INDIGO] = C_WHITE, [C_GRAY] = C_CREAM, [C_NIGHT] = C_GRAY }
local PM_SNOWTHATCH = { [C_TAN] = C_WHITE, [C_WOOD] = C_CREAM, [C_CREAM] = C_WHITE, [C_BROWN] = C_GRAY }
local PM_REDROOF = { [C_INDIGO] = C_RED, [C_GRAY] = C_PINK }

-- ---------------------------------------------------------------------------
-- Hanamura - starting village (Sakura Vale)
-- ---------------------------------------------------------------------------
local function hanamura()
  local x0, y0, w, d = 50, 78, 26, 18
  local h = 8
  area(x0, y0, w, d, h, T.GRASS1, F_TOWN | F_NOSPAWN)
  for y = y0, y0 + d - 1 do
    for x = x0, x0 + w - 1 do
      local v = hash2(x, y, 4)
      WT[cidx(x, y)] = v < 0.5 and T.GRASS1 or (v < 0.8 and T.GRASS2 or T.SAKURA)
    end
  end
  tiles(58, 84, 10, 5, T.DIRT)
  tiles(62, 79, 2, 6, T.DIRT)
  tiles(50, 86, 26, 2, T.DIRT)
  tiles(57, 81, 2, 10, T.DIRT)
  house("dojo", 59, 78, 7, 4, h, "s", { name = "Dojo" })
  house("farm", 51, 80, 4, 3, h, "e")
  house("farm", 51, 89, 4, 3, h, "e")
  house("shop", 67, 82, 4, 3, h, "w", { name = "General Store" })
  house("inn", 67, 89, 5, 4, h, "w", { name = "Sakura Inn" })
  house("farm", 59, 91, 4, 3, h, "n")
  obj(63, 86, O_WELL)
  obj(58, 84, O_TORO) obj(67, 84, O_TORO) obj(58, 88, O_TORO) obj(66, 88, O_TORO)
  sign(55, 85, "Hanamura. East: Kyo, the capital. West: Takemura and the bamboo forest.")
  obj(65, 81, O_BANNER) obj(60, 81, O_BANNER)
  for x = 51, 55 do obj(x, 93, O_FENCE) end
  obj(56, 83, O_CRATE) obj(56, 82, O_BARREL) obj(71, 86, O_CRATE)
  obj(53, 79, O_SAKURA, 2) obj(73, 80, O_SAKURA, 2) obj(74, 93, O_SAKURA, 2) obj(50, 94, O_SAKURA, 2)
  obj(66, 92, O_CHOCHIN) obj(66, 85, O_CHOCHIN) obj(61, 82, O_CHOCHIN)
  obj(70, 94, O_JIZO)
  -- rice paddies on a lower terrace east of the village
  area(76, 84, 10, 11, h - 4, T.PADDY, F_NOSPAWN)
  for y = 84, 94 do
    for x = 76, 85 do
      if (x + y) % 2 == 0 then obj(x, y, O_RICE, 2) end
      if x == 80 then WT[cidx(x, y)] = T.DIRT WO[cidx(x, y)] = 0 end
    end
  end
  poi("hanamura", 63, 87)
  poi("dojo", 62, 83)
  poi("start", 62, 84)
  poi("paddies", 80, 89)
  npc("sensei", 62, 83)
  npc("shopkeep", 66, 83, { shop = "hanamura", name = "Ume" })
  npc("innkeep", 66, 90, { inn = 15, name = "Okami Fuji" })
  npc("farmer", 79, 88, { name = "Farmer Goro" })
  npc("villager", 60, 86)
  npc("woman", 54, 87)
  npc("child", 64, 89, { name = "Little Mei", id = "mei" })
  TOWNS[#TOWNS + 1] = { name = "Hanamura", x = 63 * 8, y = 87 * 8, r = 110 }
  tower("Hanamura Pagoda", 72, 76, 4)
  kodama(60, 79) -- on the dojo roof
  chest(52, 95, "torch", 2)
end

-- ---------------------------------------------------------------------------
-- Kyo - walled capital with the castle
-- ---------------------------------------------------------------------------
local function kyo()
  local x0, y0, w, d = 98, 45, 40, 28
  local h = 12
  area(x0, y0, w, d, h, T.STONE, F_TOWN | F_NOSPAWN)
  -- walls: ishigaki stone, 3 steps tall, with four gates
  for x = x0, x0 + w - 1 do
    for _, y in ipairs({ y0, y0 + d - 1 }) do
      if math.abs(x - 118) > 1 then
        local i = cidx(x, y)
        WH[i] = h + 14 WT[i] = T.PLAZA WM[i] = M_STONE
      end
    end
  end
  for y = y0, y0 + d - 1 do
    for _, x in ipairs({ x0, x0 + w - 1 }) do
      if math.abs(y - 58) > 1 then
        local i = cidx(x, y)
        WH[i] = h + 14 WT[i] = T.PLAZA WM[i] = M_STONE
      end
    end
  end
  -- streets and plaza
  tiles(x0 + 1, 57, w - 2, 3, T.PLAZA)
  tiles(117, y0 + 1, 3, d - 2, T.PLAZA)
  tiles(110, 60, 16, 6, T.GRAVEL)
  -- castle on its stone base (north-centre)
  Build_castle(111, 47, 12, 8, h)
  Build_torii(118 * 8 + 4, 57 * 8 + 4, h, true, 1.1)
  -- houses / shops
  house("smith", 100, 47, 5, 4, h, "s", { name = "Smithy" })
  house("shop", 100, 53, 5, 3, h, "e", { name = "Kyo Market" })
  house("house", 100, 61, 4, 3, h, "e")
  house("house", 100, 66, 5, 4, h, "e", { pm = Pal.mk(PM_REDROOF) })
  house("inn", 129, 47, 6, 4, h, "s", { name = "Crane Inn" })
  house("shop", 130, 53, 5, 3, h, "w", { name = "Tea House" })
  house("house", 130, 61, 5, 3, h, "w")
  house("storehouse", 125, 63, 3, 3, h, "w")
  house("house", 106, 66, 4, 4, h, "n", { pm = Pal.mk(PM_REDROOF) })
  house("house", 122, 67, 4, 4, h, "n")
  -- decorations
  for _, p in ipairs({ { 110, 58 }, { 126, 58 }, { 116, 62 }, { 120, 62 }, { 116, 52 }, { 120, 52 } }) do obj(p[1], p[2], O_TORO) end
  for _, p in ipairs({ { 109, 61 }, { 127, 61 }, { 113, 66 }, { 123, 66 } }) do obj(p[1], p[2], O_SAKURA, 2) end
  obj(118, 63, O_STATUE)
  for _, p in ipairs({ { 104, 58 }, { 132, 58 }, { 117, 70 }, { 119, 70 }, { 117, 46 }, { 119, 46 } }) do obj(p[1], p[2], O_BANNER) end
  obj(106, 52, O_BARREL) obj(106, 53, O_CRATE) obj(128, 52, O_BARREL) obj(108, 63, O_WELL)
  for _, p in ipairs({ { 112, 60 }, { 124, 60 }, { 104, 56 }, { 132, 56 } }) do obj(p[1], p[2], O_CHOCHIN) end
  sign(117, 72, "Kyo, seat of the Shogun. Visitors must keep the peace.")
  poi("kyo", 118, 59)
  poi("castle", 118, 56)
  npc("lady", 118, 56, { name = "Lady Sayo" })
  npc("captain", 116, 60, { name = "Captain Ishida" })
  npc("smith", 102, 51, { shop = "kyo_smith", name = "Smith Masamune" })
  npc("teamaster", 129, 55, { shop = "kyo_tea", name = "Tea Master Rikyu" })
  npc("shopkeep", 105, 55, { shop = "hanamura", name = "Merchant Daisuke" })
  npc("innkeep", 131, 51, { inn = 25, name = "Innkeeper Tsuru" })
  npc("guard", 117, 71) npc("guard", 119, 71) npc("guard", 99, 58) npc("guard", 136, 58) npc("guard", 117, 46)
  npc("villager", 112, 63) npc("woman", 124, 64) npc("villager", 108, 58) npc("child", 122, 60)
  npc("monk", 118, 65, { name = "Monk Kuya" })
  TOWNS[#TOWNS + 1] = { name = "Kyo", x = 118 * 8, y = 59 * 8, r = 180 }
  tower("Kyo Pagoda", 133, 66, 5)
  kodama(103, 68) -- on a red roof
  chest(126, 46 + 1, "katana", 1)
end

-- ---------------------------------------------------------------------------
-- Yukimura - snowy mountain village with a hot spring
-- ---------------------------------------------------------------------------
local function yukimura()
  local x0, y0, w, d = 84, 22, 18, 13
  local h = baseHeight(x0, y0, w, d)
  h = math.max(16, math.min(h, 32))
  area(x0, y0, w, d, h, T.SNOW1, F_TOWN | F_NOSPAWN)
  tiles(x0, 28, w, 2, T.SNOWPATH)
  tiles(92, y0, 2, d, T.SNOWPATH)
  local snow = Pal.mk(PM_SNOWTHATCH)
  house("farm", 85, 23, 4, 3, h, "s", { pm = snow })
  house("farm", 95, 23, 4, 3, h, "s", { pm = snow })
  house("inn", 85, 31, 5, 3, h, "n", { name = "Snowdrop Inn", pm = Pal.mk(PM_SNOWROOF) })
  house("shop", 95, 31, 4, 3, h, "n", { name = "Mountain Goods", pm = snow })
  -- onsen: shallow steaming pool
  area(99, 26, 3, 3, h - 4, T.SHALLOW, F_NOSPAWN)
  for x = 99, 101 do for y = 26, 28 do WF[cidx(x, y)] = WF[cidx(x, y)] | F_SHALLOW end end
  obj(98, 25, O_TORO) obj(98, 29, O_TORO) obj(89, 27, O_CHOCHIN) obj(95, 27, O_CHOCHIN)
  sign(91, 29, "Yukimura. The summit trail of Mount Fuyu begins north-east. Dress warmly!")
  poi("yukimura", 92, 29)
  poi("onsen", 100, 27)
  npc("tailor", 90, 27, { name = "Tailor Kiku" })
  npc("innkeep", 87, 30, { inn = 20, name = "Innkeeper Bunta", id = "inn_yuki" })
  npc("shopkeep", 96, 30, { shop = "yukimura", name = "Old Haru" })
  npc("villager", 93, 25) npc("woman", 88, 26)
  TOWNS[#TOWNS + 1] = { name = "Yukimura", x = 92 * 8, y = 29 * 8, r = 90, cold = false }
  tower("Fuyu Watch Pagoda", 104, 33, 4)
end

-- ---------------------------------------------------------------------------
-- Takemura - bamboo cutters' village
-- ---------------------------------------------------------------------------
local function takemura()
  local x0, y0, w, d = 30, 61, 15, 11
  local h = baseHeight(x0, y0, w, d)
  area(x0, y0, w, d, h, T.BAMBOO, F_TOWN | F_NOSPAWN)
  tiles(x0, 66, w, 2, T.DIRT)
  tiles(37, y0, 2, d, T.DIRT)
  house("farm", 31, 62, 4, 3, h, "s")
  house("farm", 40, 62, 4, 3, h, "s", { name = "Woodcutter's Lodge" })
  house("shop", 31, 68, 4, 3, h, "n", { name = "Bamboo Crafts" })
  house("farm", 40, 69, 4, 3, h, "n")
  for x = 30, 44, 2 do obj(x, 60, O_FENCE) end
  obj(36, 65, O_TORO) obj(39, 65, O_TORO) obj(36, 69, O_CRATE) obj(44, 66, O_BARREL)
  sign(38, 72, "Takemura. Beware the deep bamboo to the north-west: the spider-woman's lair.")
  poi("takemura", 37, 67)
  npc("woodcutter", 41, 66, { name = "Woodcutter Taro" })
  npc("shopkeep", 34, 67, { shop = "takemura", name = "Weaver Aya" })
  npc("villager", 38, 64) npc("child", 35, 66, { name = "Kenta" })
  npc("tanuki", 33, 65, { name = "Ponta the Tanuki" })
  TOWNS[#TOWNS + 1] = { name = "Takemura", x = 37 * 8, y = 67 * 8, r = 80 }
  tower("Bamboo Pagoda", 46, 56, 4)
end

-- ---------------------------------------------------------------------------
-- Minato - fishing port with docks
-- ---------------------------------------------------------------------------
local function minato()
  local x0, y0, w, d = 190, 36, 18, 14
  local h = 4
  area(x0, y0, w, d, h, T.SAND, F_TOWN | F_NOSPAWN)
  tiles(x0, 42, w, 2, T.WOOD)
  tiles(198, y0, 2, d, T.DIRT)
  house("house", 191, 37, 4, 3, h, "s")
  house("inn", 201, 37, 5, 3, h, "s", { name = "Seagull Inn" })
  house("shop", 191, 45, 4, 3, h, "n", { name = "Fish Market" })
  house("house", 201, 45, 4, 3, h, "n", { pm = Pal.mk(PM_REDROOF) })
  -- docks over the sea to the east
  for x = 208, 222 do
    for y = 41, 44 do
      if inmap(x, y) then
        local i = cidx(x, y)
        if y == 42 or y == 43 or x > 218 then
          WH[i] = 4 WT[i] = T.WOOD WF[i] = (WF[i] & ~F_WATER) | F_BRIDGE | F_NOSPAWN WO[i] = 0
        end
      end
    end
  end
  obj(196, 41, O_BARREL) obj(197, 41, O_CRATE) obj(206, 44, O_CRATE) obj(207, 41, O_TORO) obj(207, 44, O_TORO)
  obj(196, 44, O_CHOCHIN) obj(201, 41, O_CHOCHIN)
  sign(198, 50, "Minato Port. South along the coast lie the Kappa Marsh and the sealed bridge to Onigashima.")
  poi("minato", 199, 43)
  poi("docks", 216, 42)
  npc("fisher", 212, 42, { name = "Fisher Isamu" })
  npc("merchant", 199, 40, { name = "Merchant Kaito" })
  npc("shopkeep", 195, 44, { shop = "minato", name = "Fishwife Nami" })
  npc("innkeep", 203, 40, { inn = 20, name = "Innkeeper Sora" })
  npc("villager", 194, 42) npc("woman", 204, 43)
  TOWNS[#TOWNS + 1] = { name = "Minato", x = 199 * 8, y = 43 * 8, r = 100 }
  tower("Lighthouse Pagoda", 186, 50, 4)
  kodama(193, 38) -- on a roof
end

-- ---------------------------------------------------------------------------
-- Haunted temple
-- ---------------------------------------------------------------------------
local function temple()
  local x0, y0, w, d = 30, 10, 16, 12
  local h = baseHeight(x0, y0, w, d)
  area(x0, y0, w, d, h, T.HAUNT, F_NOSPAWN)
  tiles(37, y0, 2, d, T.GRAVEL)
  house("temple", 33, 11, 10, 5, h, "s", { name = "Kurodera Temple" })
  for _, p in ipairs({ { 31, 18 }, { 32, 20 }, { 34, 19 }, { 42, 19 }, { 44, 18 }, { 43, 20 }, { 31, 16 }, { 45, 16 } }) do obj(p[1], p[2], O_GRAVE) end
  obj(36, 17, O_TORO) obj(40, 17, O_TORO) obj(38, 21, O_JIZO)
  Build_torii(38 * 8, 23 * 8, h, false, 1.0)
  poi("temple", 38, 18)
  npc("monk", 38, 17, { name = "Abbot Genshin", id = "abbot" })
  tower("Kurodera Pagoda", 26, 12, 5)
  chest(44, 12, "lantern", 1)
end

-- ---------------------------------------------------------------------------
-- boss arenas
-- ---------------------------------------------------------------------------
local function lairs()
  -- Jorogumo: clearing in the deep bamboo, ringed by cliffs
  local cx, cy = 16, 44
  local h = baseHeight(cx - 6, cy - 5, 13, 11)
  area(cx - 6, cy - 5, 13, 11, h, T.FOREST, F_NOSPAWN)
  for _, p in ipairs({ { cx - 5, cy - 4 }, { cx + 5, cy - 4 }, { cx - 5, cy + 4 }, { cx + 5, cy + 4 }, { cx, cy - 5 }, { cx - 6, cy } }) do obj(p[1], p[2], O_WEB) end
  obj(cx + 3, cy + 3, O_BONES) obj(cx - 3, cy + 2, O_BONES)
  poi("lair", cx, cy, { boss = "jorogumo" })
  -- Tengu Lord: the frozen summit of Mount Fuyu
  local sx, sy = 121, 12
  local sh = 0
  for y = sy - 4, sy + 4 do for x = sx - 5, sx + 5 do sh = math.max(sh, cellH(x, y)) end end
  area(sx - 5, sy - 4, 11, 9, sh, T.SNOW2, F_NOSPAWN)
  Build_torii(sx * 8 + 4, (sy + 4) * 8 + 4, sh, false, 1.0)
  obj(sx, sy - 3, O_HOKORA)
  poi("summit", sx, sy, { boss = "tengulord" })
  -- Orochi: island in the Great Lake + stepping stones from the west shore
  poi("lake", 177, 73, { boss = "orochi" })
  local stones = { { 163, 73, 6 }, { 166, 72, 8 }, { 169, 73, 10 }, { 172, 72, 8 } }
  for _, s in ipairs(stones) do
    local i = cidx(s[1], s[2])
    WH[i] = s[3] WT[i] = T.ROCK WF[i] = (WF[i] & ~F_WATER) | F_NOSPAWN WO[i] = 0
  end
  -- Onigashima fortress
  local ox, oy = 216, 98
  local oh = baseHeight(ox - 5, oy - 4, 11, 9)
  area(ox - 6, oy - 4, 13, 9, oh, T.ASH, F_NOSPAWN)
  for x = ox - 6, ox + 6 do
    for _, y in ipairs({ oy - 5, oy + 5 }) do
      if inmap(x, y) and math.abs(x - ox) > 1 then
        local i = cidx(x, y)
        WH[i] = oh + 16 WT[i] = T.ASH WM[i] = M_STONE WF[i] = WF[i] & ~F_WATER
      end
    end
  end
  Build_torii(ox * 8 + 4, (oy + 5) * 8 + 4, oh, false, 1.3)
  poi("onigashima", ox, oy, { boss = "shuten" })
  -- the sealed bridge from the mainland
  local path = { { 200, 88 }, { 204, 91 }, { 208, 94 }, { 212, 97 } }
  W.walkPath(path, function(x, y)
    for dy = 0, 1 do
      local xx, yy = x, y + dy
      if inmap(xx, yy) then
        local i = cidx(xx, yy)
        if (WF[i] & F_WATER) ~= 0 then
          WH[i] = 4 WT[i] = T.WOOD WF[i] = (WF[i] & ~F_WATER) | F_BRIDGE | F_NOSPAWN WM[i] = M_RED
        end
      end
    end
  end)
  poi("bridge", 200, 88)
  Build_torii(201 * 8, 89 * 8, math.max(0, cellH(201, 89)), true, 1.0)
end

-- ---------------------------------------------------------------------------
-- the wider world: shrines, kodama, chests, camps, extra towers
-- ---------------------------------------------------------------------------
local function wilds()
  shrine(46, 82, "Shrine of First Steps", "combat")
  shrine(24, 76, "Shrine of Bamboo Wind", "spires")
  shrine(80, 46, "Shrine of Quiet Fields", "combat")
  shrine(146, 40, "Shrine of the Climb", "spires")
  shrine(148, 86, "Shrine of Reeds", "combat")
  shrine(60, 30, "Shrine of Lanterns", "spires")
  shrine(168, 26, "Shrine of Snowfall", "combat")
  shrine(214, 62, "Shrine of the Tide", "spires")
  -- kodama on spires and in remote places
  local spots = { { 70, 102, 20 }, { 12, 66, 24 }, { 90, 58, 28 }, { 132, 76, 20 }, { 156, 50, 32 }, { 178, 60, 24 },
    { 104, 88, 18 }, { 52, 40, 30 }, { 140, 22, 36 }, { 196, 74, 18 }, { 24, 28, 26 }, { 160, 100, 16 } }
  for _, s in ipairs(spots) do
    if cellH(s[1], s[2]) >= 0 then
      spire(s[1], s[2], s[3], 1)
      spire(s[1] + 1, s[2] + 1, flr(s[3] * 0.6), 1)
      spire(s[1] - 1, s[2] + 1, flr(s[3] * 0.3), 1)
      kodama(s[1], s[2])
    end
  end
  -- forest kodama hidden among trees
  for _, s in ipairs({ { 20, 56 }, { 58, 20 }, { 126, 36 }, { 186, 30 }, { 170, 90 }, { 84, 100 } }) do
    if cellH(s[1], s[2]) >= 0 and (WF[cidx(s[1], s[2])] & F_WATER) == 0 then kodama(s[1], s[2]) end
  end
  -- chests
  local loot = { { 88, 70, "katana", 1 }, { 150, 64, "ryo", 60 }, { 176, 40, "shuriken", 10 }, { 22, 40, "mochi", 3 },
    { 124, 20, "stew", 2 }, { 70, 50, "barmor", 1 }, { 160, 78, "sushi", 3 }, { 30, 26, "essence", 3 },
    { 210, 54, "lantern", 1 }, { 100, 100, "ryo", 40 }, { 136, 92, "bedroll", 1 }, { 6, 70, "gold", 3 } }
  for _, c in ipairs(loot) do
    local x, y = c[1], c[2]
    if inmap(x, y) and cellH(x, y) >= 0 then
      local i = cidx(x, y)
      WF[i] = WF[i] & ~F_WATER
      chest(x, y, c[3], c[4])
    end
  end
  -- enemy camps
  Enemy.camp("bandit", 88, 71, 3)
  Enemy.camp("bandit", 150, 64, 3)
  Enemy.camp("ronin", 176, 41, 2)
  Enemy.camp("wolf", 40, 46, 3)
  Enemy.camp("snowwolf", 98, 18, 3)
  Enemy.camp("tengu", 110, 22, 2)
  Enemy.camp("tengu", 134, 18, 2)
  Enemy.camp("kappa", 168, 80, 3)
  Enemy.camp("kappa", 186, 66, 2)
  Enemy.camp("spider", 22, 50, 3)
  Enemy.camp("oni", 212, 101, 2)
  Enemy.camp("oni", 220, 94, 2)
  Enemy.camp("ronin", 70, 22, 2)
  Enemy.camp("boar", 74, 64, 2)
  for _, c in ipairs({ { 86, 69 }, { 90, 72 }, { 148, 62 }, { 152, 66 } }) do obj(c[1], c[2], O_LOGS) end
  -- the lost cat
  poi("cat", 46, 72)
  -- signposts at crossroads
  sign(98, 79, "East: Kyo. West: Hanamura.")
  sign(158, 57, "East: Minato Port. West: Kyo.")
  sign(112, 39, "North: Yukimura and Mount Fuyu.")
  sign(31, 48, "North: Kurodera Temple. West: the Spider Lair. Turn back, traveller.")
end

function Towns_gen()
  hanamura()
  kyo()
  yukimura()
  takemura()
  minato()
  temple()
  lairs()
  wilds()
end

-- ============================================================================
--  20 RENDER - orthographic, rotatable isometric camera over a z-buffered
--  ttri pipeline.
--
--  Projection (yaw a, pitch p, ortho scale 1):
--    lx = dx*cos a + dy*sin a        (screen right)
--    lf = dx*sin a - dy*cos a        (into the screen, along the ground)
--    sx = SCX + lx
--    sy = SCY - (lf*sin p + dz*cos p)
--    depth = DOFF + lf*cos p - dz*sin p    (smaller = closer; ttri z-test is <)
--  DOFF is large so ttri's perspective correction is effectively affine.
--  Terrain is meshed per 8x8-cell chunk (greedy top rectangles + merged cliff
--  runs) and cached; walls sample texture bands in map rows 112+.
-- ============================================================================
Cam = { x = 960, y = 700, z = 0, a = math.pi / 4, ta = math.pi / 4, sx = 0, sy = 0,
  SCX = 120, SCY = 76, shake = 0 }
function Cam.setPitch(p) Cam.pitch, Cam.sp, Cam.cp = p, math.sin(p), math.cos(p) end
Cam.setPitch(0.66)

Render = { stats = {} }
MESH = {}
CHMIN, CHMAX = {}, {}
OLIST = {}       -- chunk -> list of cell indices that hold objects
OX, OY = {}, {}  -- object world positions (jittered)

local DOFF = 100000
local CA, SA, SP, CP, CX, CY, CZ, SCX, SCY = 1, 0, 0.6, 0.8, 0, 0, 0, 120, 76
local ttri = ttri
local curPM = nil

local function setPM(p)
  if p == curPM then return end
  if p then Pal.remap(p) else Pal.reset() end
  curPM = p
end
Render.setPM = setPM

function proj(x, y, z)
  local dx, dy = x - CX, y - CY
  local lf = dx * SA - dy * CA
  local dz = z - CZ
  return SCX + dx * CA + dy * SA, SCY - (lf * SP + dz * CP), DOFF + lf * CP - dz * SP
end
local PRJ = proj

function Render.begin()
  CA, SA = math.cos(Cam.a), math.sin(Cam.a)
  SP, CP = Cam.sp, Cam.cp
  CX, CY, CZ = Cam.x + Cam.sx, Cam.y + Cam.sy, Cam.z
  SCX, SCY = Cam.SCX, Cam.SCY
  curPM = nil
  Pal.reset()
end

-- world forward/right vectors for input mapping
function Cam.fwd() return math.sin(Cam.a), -math.cos(Cam.a) end
function Cam.right() return math.cos(Cam.a), math.sin(Cam.a) end

-- ---------------------------------------------------------------------------
-- chunk meshing
-- ---------------------------------------------------------------------------
function Render.chunkBounds()
  for cy = 0, 13 do
    for cx = 0, 29 do
      local lo, hi = 999, -999
      for y = cy * 8, cy * 8 + 7 do
        for x = cx * 8, cx * 8 + 7 do
          local h = WH[y * 240 + x + 1]
          if h < lo then lo = h end
          if h > hi then hi = h end
        end
      end
      local k = cy * 30 + cx
      CHMIN[k], CHMAX[k] = lo, hi
    end
  end
end

local function cellMat(i)
  return WM[i] or TMAT[WT[i]] or M_EARTH
end

local function buildMesh(k)
  local cx, cy = k % 30, k // 30
  local x0, y0 = cx * 8, cy * 8
  local tops, sides = {}, {}
  local used = {}
  -- greedy top rectangles
  for ly = 0, 7 do
    for lx = 0, 7 do
      local li = ly * 8 + lx
      if not used[li] then
        local i = (y0 + ly) * 240 + x0 + lx + 1
        local h = WH[i]
        local skip = (WF[i] & (F_ROOF | F_MODEL)) ~= 0
        local w = 1
        while lx + w < 8 do
          local j = i + w
          if used[li + w] or WH[j] ~= h or ((WF[j] & (F_ROOF | F_MODEL)) ~= 0) ~= skip then break end
          w = w + 1
        end
        local d = 1
        while ly + d < 8 do
          local ok = true
          for q = 0, w - 1 do
            local j = i + d * 240 + q
            if used[li + d * 8 + q] or WH[j] ~= h or ((WF[j] & (F_ROOF | F_MODEL)) ~= 0) ~= skip then ok = false break end
          end
          if not ok then break end
          d = d + 1
        end
        for yy = 0, d - 1 do for xx = 0, w - 1 do used[li + yy * 8 + xx] = true end end
        if not skip then
          local z = h < 0 and h + 1 or h
          tops[#tops + 1] = { (x0 + lx) * 8, (y0 + ly) * 8, (x0 + lx + w) * 8, (y0 + ly + d) * 8, z }
        end
      end
    end
  end
  -- side faces, merged along the edge direction
  -- dir: 1=S(+y) 2=N(-y) 3=E(+x) 4=W(-x)
  local function emit(dir, ax, ay, bx, by, lo, hi, mat)
    local last = sides[#sides]
    if last and last[1] == dir and last[6] == lo and last[7] == hi and last[8] == mat and last[4] == ax and last[5] == ay then
      last[4], last[5] = bx, by
    else
      sides[#sides + 1] = { dir, ax, ay, bx, by, lo, hi, mat }
    end
  end
  local function top(i, h) return h < 0 and h + 1 or h end
  for pass = 1, 4 do
    for a = 0, 7 do
      for b = 0, 7 do
        local lx, ly
        if pass <= 2 then lx, ly = b, a else lx, ly = a, b end
        local x, y = x0 + lx, y0 + ly
        local i = y * 240 + x + 1
        if (WF[i] & F_MODEL) == 0 then
          local h = top(i, WH[i])
          local nx, ny = x, y
          if pass == 1 then ny = y + 1 elseif pass == 2 then ny = y - 1 elseif pass == 3 then nx = x + 1 else nx = x - 1 end
          local hn = cellH(nx, ny)
          hn = hn < 0 and hn + 1 or hn
          if inmap(nx, ny) and (WF[ny * 240 + nx + 1] & F_MODEL) ~= 0 then hn = h end
          if h > hn then
            local m = cellMat(i)
            if pass == 1 then emit(1, x * 8, (y + 1) * 8, (x + 1) * 8, (y + 1) * 8, hn, h, m)
            elseif pass == 2 then emit(2, x * 8, y * 8, (x + 1) * 8, y * 8, hn, h, m)
            elseif pass == 3 then emit(3, (x + 1) * 8, y * 8, (x + 1) * 8, (y + 1) * 8, hn, h, m)
            else emit(4, x * 8, y * 8, x * 8, (y + 1) * 8, hn, h, m) end
          end
        end
      end
    end
  end
  local m = { tops = tops, sides = sides }
  MESH[k] = m
  return m
end

function Render.invalidate(x, y)
  local k = (y // 8) * 30 + (x // 8)
  MESH[k] = nil
  -- neighbours may expose new faces
  if x % 8 == 0 and x > 0 then MESH[k - 1] = nil end
  if x % 8 == 7 and x < 239 then MESH[k + 1] = nil end
  if y % 8 == 0 and y > 0 then MESH[k - 30] = nil end
  if y % 8 == 7 and y < 111 then MESH[k + 30] = nil end
end

-- ---------------------------------------------------------------------------
-- drawing primitives
-- ---------------------------------------------------------------------------
local function onScreen(a, b, c, d, e, f, g, h)
  local mnx = math.min(a, c, e, g)
  if mnx > 240 then return false end
  local mxx = math.max(a, c, e, g)
  if mxx < 0 then return false end
  local mny = math.min(b, d, f, h)
  if mny > 136 then return false end
  local mxy = math.max(b, d, f, h)
  return mxy >= 0
end

local function drawTop(t)
  local x0, y0, x1, y1, z = t[1], t[2], t[3], t[4], t[5]
  local ax, ay, ad = PRJ(x0, y0, z)
  local bx, by, bd = PRJ(x1, y0, z)
  local cx, cy, cd = PRJ(x1, y1, z)
  local dx, dy, dd = PRJ(x0, y1, z)
  if not onScreen(ax, ay, bx, by, cx, cy, dx, dy) then return end
  ttri(ax, ay, bx, by, dx, dy, x0, y0, x1, y0, x0, y1, 1, -1, ad, bd, dd)
  ttri(bx, by, cx, cy, dx, dy, x1, y0, x1, y1, x0, y1, 1, -1, bd, cd, dd)
  Render.stats.tris = Render.stats.tris + 2
end

local VIS = { false, false, false, false }
local function drawSide(s)
  local dir = s[1]
  if not VIS[dir] then return end
  local ax, ay, bx, by, lo, hi = s[2], s[3], s[4], s[5], s[6], s[7]
  -- orient so the quad's left edge is on the viewer's left
  local ua, ub
  if dir == 1 then ua, ub = ax, bx
  elseif dir == 2 then ax, ay, bx, by = bx, by, ax, ay ua, ub = ax, bx
  elseif dir == 3 then ax, ay, bx, by = bx, by, ax, ay ua, ub = ay, by
  else ua, ub = ay, by end
  local mat = MAT[s[8]]
  local band = mat.band
  local topz = hi
  local first = true
  local p1x, p1y, p1d = PRJ(ax, ay, topz)
  local p2x, p2y, p2d = PRJ(bx, by, topz)
  local p3x, p3y, p3d = PRJ(bx, by, lo)
  local p4x, p4y, p4d = PRJ(ax, ay, lo)
  if not onScreen(p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y) then return end
  setPM(mat.pm)
  while topz > lo do
    local vs, avail
    if first or band.h <= 8 then vs, avail = band.v, band.h
    else vs, avail = band.v + 8, band.h - 8 end
    local seg = math.min(avail, topz - lo)
    local bz = topz - seg
    local ax1, ay1, ad1 = PRJ(ax, ay, topz)
    local bx1, by1, bd1 = PRJ(bx, by, topz)
    local bx2, by2, bd2 = PRJ(bx, by, bz)
    local ax2, ay2, ad2 = PRJ(ax, ay, bz)
    ttri(ax1, ay1, bx1, by1, ax2, ay2, ua, vs, ub, vs, ua, vs + seg, 1, -1, ad1, bd1, ad2)
    ttri(bx1, by1, bx2, by2, ax2, ay2, ub, vs, ub, vs + seg, ua, vs + seg, 1, -1, bd1, bd2, ad2)
    Render.stats.tris = Render.stats.tris + 2
    topz = bz
    first = false
  end
end

-- draw a model polygon list
local function drawModel(m)
  local ps = m.polys
  for i = 1, #ps do
    local q = ps[i]
    if q[1] == 4 then
      local ax, ay, ad = PRJ(q[2], q[3], q[4])
      local bx, by, bd = PRJ(q[5], q[6], q[7])
      local cx, cy, cd = PRJ(q[8], q[9], q[10])
      local dx, dy, dd = PRJ(q[11], q[12], q[13])
      -- winding cull (clockwise on screen = front); test both tris for degenerate quads
      local area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay) + (cx - ax) * (dy - ay) - (dx - ax) * (cy - ay)
      if area > 0 and onScreen(ax, ay, bx, by, cx, cy, dx, dy) then
        setPM(q[23])
        local src = q[22]
        local ck = src == 0 and 0 or -1
        ttri(ax, ay, bx, by, dx, dy, q[14], q[15], q[16], q[17], q[20], q[21], src, ck, ad, bd, dd)
        ttri(bx, by, cx, cy, dx, dy, q[16], q[17], q[18], q[19], q[20], q[21], src, ck, bd, cd, dd)
        Render.stats.tris = Render.stats.tris + 2
      end
    else
      local ax, ay, ad = PRJ(q[2], q[3], q[4])
      local bx, by, bd = PRJ(q[5], q[6], q[7])
      local cx, cy, cd = PRJ(q[8], q[9], q[10])
      local area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
      if area > 0 then
        setPM(q[18])
        local src = q[17]
        ttri(ax, ay, bx, by, cx, cy, q[11], q[12], q[13], q[14], q[15], q[16], src, src == 0 and 0 or -1, ad, bd, cd)
        Render.stats.tris = Render.stats.tris + 1
      end
    end
  end
end
Render.drawModel = drawModel

-- billboard: rect drawn upright, feet at world (x,y,z); bias pulls it forward
function Render.bill(r, x, y, z, flip, pm, sc, bias)
  sc = sc or 1
  local sx, sy, d = PRJ(x, y, z)
  local w, h = r[3] * sc, r[4] * sc
  local x0 = flr(sx - w / 2 + 0.5)
  local y1 = flr(sy + 0.5)
  local y0 = y1 - h
  if x0 > 240 or x0 + w < 0 or y0 > 136 or y1 < 0 then return false end
  d = d - (bias or 1.5)
  local dt = d - (h / CP) * SP
  local u, v = r[1], r[2]
  local u0, u1 = u, u + r[3]
  if flip then u0, u1 = u1, u0 end
  if pm ~= curPM then setPM(pm) end
  local x1 = x0 + w
  ttri(x0, y0, x1, y0, x0, y1, u0, v, u1, v, u0, v + r[4], 0, 0, dt, dt, d)
  ttri(x1, y0, x1, y1, x0, y1, u1, v, u1, v + r[4], u0, v + r[4], 0, 0, dt, d, d)
  Render.stats.bills = Render.stats.bills + 1
  return true, x0, y0
end

-- billboard rotated about its base centre by ang (screen space, + = clockwise):
-- chopped trees lean and fall with it. The top keeps the depth of the height
-- it still reaches.
function Render.billRot(r, x, y, z, flip, pm, sc, ang, bias)
  sc = sc or 1
  local sx, sy, d = PRJ(x, y, z)
  local w, h = r[3] * sc, r[4] * sc
  if sx + w + h < 0 or sx - w - h > 240 or sy - h > 136 or sy + h < 0 then return false end
  d = d - (bias or 1.5)
  local c, s = math.cos(ang), math.sin(ang)
  local dt = d - (h * math.max(c, 0) / CP) * SP
  local hw = w / 2
  local tlx, tly = sx - hw * c + h * s, sy - hw * s - h * c
  local trx, try = sx + hw * c + h * s, sy + hw * s - h * c
  local blx, bly = sx - hw * c, sy - hw * s
  local brx, bry = sx + hw * c, sy + hw * s
  local u, v = r[1], r[2]
  local u0, u1 = u, u + r[3]
  if flip then u0, u1 = u1, u0 end
  if pm ~= curPM then setPM(pm) end
  ttri(tlx, tly, trx, try, blx, bly, u0, v, u1, v, u0, v + r[4], 0, 0, dt, dt, d)
  ttri(trx, try, brx, bry, blx, bly, u1, v, u1, v + r[4], u0, v + r[4], 0, 0, dt, d, d)
  Render.stats.bills = Render.stats.bills + 1
  return true
end

-- billboard without depth test (always on top) - used for the x-ray silhouette
function Render.billFlat(r, x, y, z, flip, sc)
  sc = sc or 1
  local sx, sy = PRJ(x, y, z)
  local w, h = r[3] * sc, r[4] * sc
  local x0 = flr(sx - w / 2 + 0.5)
  local y1 = flr(sy + 0.5)
  local y0 = y1 - h
  local u, v = r[1], r[2]
  local u0, u1 = u, u + r[3]
  if flip then u0, u1 = u1, u0 end
  local x1 = x0 + w
  ttri(x0, y0, x1, y0, x0, y1, u0, v, u1, v, u0, v + r[4], 0, 0)
  ttri(x1, y0, x1, y1, x0, y1, u1, v, u1, v + r[4], u0, v + r[4], 0, 0)
end

-- flat ground decal (shadow etc): rect mapped onto a square of radius rad
function Render.ground(r, x, y, z, rad, pm)
  local ax, ay, ad = PRJ(x - rad, y - rad, z)
  local bx, by, bd = PRJ(x + rad, y - rad, z)
  local cx, cy, cd = PRJ(x + rad, y + rad, z)
  local dx, dy, dd = PRJ(x - rad, y + rad, z)
  if not onScreen(ax, ay, bx, by, cx, cy, dx, dy) then return end
  if pm ~= curPM then setPM(pm) end
  local u, v, w, h = r[1], r[2], r[3], r[4]
  ttri(ax, ay, bx, by, dx, dy, u, v, u + w, v, u, v + h, 0, 0, ad, bd, dd)
  ttri(bx, by, cx, cy, dx, dy, u + w, v, u + w, v + h, u, v + h, 0, 0, bd, cd, dd)
end

-- ---------------------------------------------------------------------------
-- world pass
-- ---------------------------------------------------------------------------
-- world-space chunk range covering the screen
function Render.range()
  local m = 40
  local lxa, lxb = -SCX - m, 240 - SCX + m
  local zlo, zhi = -4 - CZ, 140 - CZ
  local lfa = (SCY - 136 - zhi * CP) / SP - m
  local lfb = (SCY - zlo * CP) / SP + 60 / SP
  local xs, ys = {}, {}
  for _, lx in ipairs({ lxa, lxb }) do
    for _, lf in ipairs({ lfa, lfb }) do
      xs[#xs + 1] = CX + lx * CA + lf * SA
      ys[#ys + 1] = CY + lx * SA - lf * CA
    end
  end
  local x0, x1 = math.min(table.unpack(xs)), math.max(table.unpack(xs))
  local y0, y1 = math.min(table.unpack(ys)), math.max(table.unpack(ys))
  return flr(x0 / 64), flr(y0 / 64), flr(x1 / 64), flr(y1 / 64)
end

local function chunkVisible(k, cx, cy)
  local lo, hi = CHMIN[k], CHMAX[k]
  local x0, y0, x1, y1 = cx * 64, cy * 64, cx * 64 + 64, cy * 64 + 64
  local mnx, mny, mxx, mxy = 1e9, 1e9, -1e9, -1e9
  for _, z in ipairs({ lo, hi }) do
    for _, p in ipairs({ { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }) do
      local sx, sy = PRJ(p[1], p[2], z)
      if sx < mnx then mnx = sx end
      if sx > mxx then mxx = sx end
      if sy < mny then mny = sy end
      if sy > mxy then mxy = sy end
    end
  end
  return mxx >= 0 and mnx <= 240 and mxy >= -50 and mny <= 136
end

local OCEAN_T = { 0, 0, 64, 64, -3 }
function Render.world(drawObjects)
  local st = Render.stats
  st.tris, st.bills, st.chunks = 0, 0, 0
  VIS[1] = CA > 0.01
  VIS[2] = CA < -0.01
  VIS[3] = SA < -0.01
  VIS[4] = SA > 0.01
  local cx0, cy0, cx1, cy1 = Render.range()
  local vis = {}
  for cy = cy0, cy1 do
    for cx = cx0, cx1 do
      if cx < 0 or cy < 0 or cx >= 30 or cy >= 14 then
        -- open ocean beyond the map edge
        local x0, y0 = cx * 64, cy * 64
        local ax, ay, ad = PRJ(x0, y0, -3)
        local bx, by, bd = PRJ(x0 + 64, y0, -3)
        local qx, qy, qd = PRJ(x0 + 64, y0 + 64, -3)
        local dx, dy, dd = PRJ(x0, y0 + 64, -3)
        if onScreen(ax, ay, bx, by, qx, qy, dx, dy) then
          setPM(nil)
          ttri(ax, ay, bx, by, dx, dy, 0, 0, 64, 0, 0, 64, 1, -1, ad, bd, dd)
          ttri(bx, by, qx, qy, dx, dy, 64, 0, 64, 64, 0, 64, 1, -1, bd, qd, dd)
        end
      else
        local k = cy * 30 + cx
        if chunkVisible(k, cx, cy) then
          st.chunks = st.chunks + 1
          vis[#vis + 1] = k
          local m = MESH[k] or buildMesh(k)
          setPM(nil)
          local tops = m.tops
          for i = 1, #tops do drawTop(tops[i]) end
          local sides = m.sides
          for i = 1, #sides do drawSide(sides[i]) end
        end
      end
    end
  end
  -- models (registered by centre chunk; scan one chunk wider)
  for cy = cy0 - 1, cy1 + 1 do
    for cx = cx0 - 1, cx1 + 1 do
      local list = MCHUNK[cy * 30 + cx]
      if list and cx >= 0 and cx < 30 then
        for i = 1, #list do drawModel(list[i]) end
      end
    end
  end
  setPM(nil)
  Render.visChunks = vis
  return vis
end

-- ============================================================================
--  30 BOOT - one-time initialisation: palette, textures, sprites, sound
--  RAM (Audio.init), world.
-- ============================================================================
Boot = { done = false }

function Boot.graphics()
  Pal.apply()
  Gfx.paintTiles()
  Gfx.fillBands()
  Art.chars()
  Art.world()
  Art.mobs()
  Art.items()
  Gfx.flush()
end

function Boot.world()
  Build_initMats()
  Objects_init()
  W.gen()
  Towns_gen()
  W.genRoads()
  Objects_scatter()
  if Towns_post then Towns_post() end
  W.commit()
  Render.chunkBounds()
end

function Boot.all()
  if Boot.done then return end
  local t0 = time()
  Boot.graphics()
  Audio.init()
  local t1 = time()
  Boot.world()
  local t2 = time()
  Boot.ms = { gfx = t1 - t0, world = t2 - t1 }
  Boot.done = true
end

-- ============================================================================
--  35 ITEMS - item table, inventory, crafting recipes, cooking, shops.
--  hp values are quarter hearts (4 = one heart); hun is 0..100 hunger.
-- ============================================================================
ITEM = {
  wood = { n = "Wood", s = 20, k = "res", sell = 1, d = "Logs for fires and tools." },
  bamboo = { n = "Bamboo", s = 20, k = "res", sell = 1, d = "Light, strong and everywhere." },
  stone = { n = "Stone", s = 20, k = "res", sell = 1, d = "A handful of rock." },
  flint = { n = "Flint", s = 20, k = "res", sell = 2, d = "Sharp edge for tools." },
  grass = { n = "Grass", s = 20, k = "res", sell = 1, d = "Dry fibres. Burns well." },
  reed = { n = "Reeds", s = 20, k = "res", sell = 1, d = "Woven into hats and mats." },
  iron = { n = "Iron Ore", s = 20, k = "res", sell = 6, d = "Smiths pay for this." },
  gold = { n = "Gold Nugget", s = 10, k = "res", sell = 25, d = "Sell it for a fortune." },
  silk = { n = "Spider Silk", s = 20, k = "res", sell = 5, d = "Sticky, shiny thread." },
  pelt = { n = "Wolf Pelt", s = 10, k = "res", sell = 8, d = "Warm fur." },
  feather = { n = "Tengu Feather", s = 20, k = "res", sell = 6, d = "Black, light as wind." },
  petal = { n = "Sakura Petal", s = 20, k = "res", sell = 2, d = "Sweet blossom." },
  pinecone = { n = "Pinecone", s = 20, k = "res", sell = 1, d = "Good kindling." },
  essence = { n = "Spirit Essence", s = 20, k = "res", sell = 10, d = "Cold mist from a yurei." },
  ember = { n = "Onibi Ember", s = 20, k = "res", sell = 8, d = "A flame that never dies." },
  rope = { n = "Rope", s = 20, k = "res", sell = 3, d = "Twisted grass." },
  paper = { n = "Washi Paper", s = 20, k = "res", sell = 3, d = "For lanterns and charms." },
  flower = { n = "Flower", s = 10, k = "res", sell = 1, d = "Pretty. Calms the mind." },
  berries = { n = "Berries", s = 10, k = "food", hun = 8, hp = 1, sell = 1, d = "Tart wild berries." },
  mushroom = { n = "Mushroom", s = 10, k = "food", hun = 6, hp = -2, sell = 1, cook = "gmush", d = "Risky raw. Cook it." },
  gmush = { n = "Grilled Mushroom", s = 10, k = "food", hun = 12, hp = 3, sell = 3, d = "Smoky and safe." },
  herb = { n = "Wild Herb", s = 10, k = "food", hun = 2, hp = 3, sell = 3, d = "Bitter, but it heals." },
  rice = { n = "Rice", s = 10, k = "food", hun = 4, sell = 2, cook = "onigiri", d = "Cook it into onigiri." },
  onigiri = { n = "Onigiri", s = 10, k = "food", hun = 30, hp = 4, sell = 6, d = "A ninja's best friend." },
  meat = { n = "Raw Meat", s = 10, k = "food", hun = 8, hp = -2, sell = 3, cook = "cmeat", d = "Cook before eating." },
  cmeat = { n = "Grilled Meat", s = 10, k = "food", hun = 25, hp = 6, sell = 8, d = "Hearty." },
  fish = { n = "Fish", s = 10, k = "food", hun = 8, sell = 4, cook = "gfish", d = "Fresh from the water." },
  gfish = { n = "Grilled Fish", s = 10, k = "food", hun = 22, hp = 8, sell = 9, d = "Salt-grilled." },
  shoot = { n = "Bamboo Shoot", s = 10, k = "food", hun = 5, sell = 2, cook = "cshoot", d = "Tender shoot." },
  cshoot = { n = "Boiled Shoot", s = 10, k = "food", hun = 14, hp = 1, stam = 30, sell = 5, d = "Restores stamina." },
  cucumber = { n = "Cucumber", s = 10, k = "food", hun = 6, hp = 1, sell = 3, d = "Kappa love these." },
  sushi = { n = "Sushi", s = 10, k = "food", hun = 40, hp = 12, sell = 20, d = "Fish on rice. Superb." },
  mochi = { n = "Mochi", s = 10, k = "food", hun = 20, hp = 2, stam = 999, sell = 12, d = "Fully restores stamina." },
  stew = { n = "Nabe Stew", s = 10, k = "food", hun = 50, hp = 16, warm = 7200, sell = 25, d = "Heals and keeps you warm." },
  tea = { n = "Green Tea", s = 10, k = "food", hun = 2, stam = 60, warm = 3600, sell = 10, d = "Stamina and warmth." },
  dango = { n = "Sakura Dango", s = 10, k = "food", hun = 25, hp = 6, sell = 10, d = "Three sweet dumplings." },
  bandage = { n = "Bandage", s = 10, k = "food", hp = 8, sell = 6, d = "Heals two hearts." },
  axe = { n = "Hatchet", s = 1, k = "tool", sell = 10, d = "Chops trees (Z facing a tree)." },
  pick = { n = "Pickaxe", s = 1, k = "tool", sell = 12, d = "Breaks rocks and ore." },
  torch = { n = "Torch", s = 5, k = "light", light = 46, fuel = 4800, sell = 2, d = "Equip to light the night." },
  lantern = { n = "Paper Lantern", s = 1, k = "light", light = 62, fuel = 99999, sell = 30, d = "A light that lasts." },
  campfire = { n = "Campfire Kit", s = 5, k = "place", obj = "fire", sell = 4, d = "Place a fire. Cook raw food." },
  potkit = { n = "Cooking Pot", s = 1, k = "place", obj = "pot", sell = 20, d = "Place it. Combine ingredients." },
  bedroll = { n = "Straw Bedroll", s = 1, k = "bed", sell = 10, d = "Sleep through the night." },
  bokken = { n = "Bokken", s = 1, k = "weapon", dmg = 1, sell = 2, d = "Wooden practice sword." },
  katana = { n = "Katana", s = 1, k = "weapon", dmg = 2, sell = 60, d = "A true blade." },
  steel = { n = "Tamahagane", s = 1, k = "weapon", dmg = 3, sell = 150, d = "Folded steel masterwork." },
  kusanagi = { n = "Kusanagi", s = 1, k = "weapon", dmg = 5, key = true, d = "The grass-cutting sword." },
  shuriken = { n = "Shuriken", s = 30, k = "ammo", sell = 2, d = "Throw with S." },
  barmor = { n = "Bamboo Armor", s = 1, k = "armor", def = 1, sell = 20, d = "Blocks a quarter heart per hit." },
  sarmor = { n = "Samurai Armor", s = 1, k = "armor", def = 2, sell = 120, d = "Blocks half a heart per hit." },
  cloak = { n = "Fur Cloak", s = 1, k = "armor", def = 0, cold = true, sell = 40, d = "Immune to mountain cold." },
  hat = { n = "Straw Kasa", s = 1, k = "armor", def = 0, rain = true, sell = 5, d = "Shade from rain and sun." },
  package = { n = "Sealed Package", s = 1, k = "quest", key = true, d = "For the innkeeper of Yukimura." },
  magatama = { n = "Magatama Jewel", s = 1, k = "quest", key = true, d = "Sacred jewel. Grants a double jump." },
  mirror = { n = "Yata Mirror", s = 1, k = "quest", key = true, d = "Sacred mirror. Its light wards the dark." },
  charm = { n = "Maneki Charm", s = 1, k = "quest", key = true, d = "Lucky cat. More ryo from foes." },
  cat = { n = "Tama the Cat", s = 1, k = "quest", key = true, d = "Bring her home to Hanamura." },
}
for id, it in pairs(ITEM) do it.id = id it.icon = "i_" .. id end

-- ---------------------------------------------------------------------------
-- inventory
-- ---------------------------------------------------------------------------
Inv = { size = 10, slots = {}, sel = 1 }
function Inv.reset()
  Inv.size = 10
  Inv.slots = {}
  Inv.sel = 1
end
function Inv.count(id)
  local n = 0
  for i = 1, Inv.size do
    local s = Inv.slots[i]
    if s and s.id == id then n = n + s.n end
  end
  return n
end
function Inv.has(id, n) return Inv.count(id) >= (n or 1) end
-- add items; returns how many did not fit
function Inv.add(id, n)
  local it = ITEM[id]
  if not it then return n end
  for i = 1, Inv.size do
    local s = Inv.slots[i]
    if s and s.id == id and s.n < it.s then
      local k = math.min(n, it.s - s.n)
      s.n = s.n + k
      n = n - k
      if n == 0 then return 0 end
    end
  end
  for i = 1, Inv.size do
    if not Inv.slots[i] then
      local k = math.min(n, it.s)
      Inv.slots[i] = { id = id, n = k }
      n = n - k
      if n == 0 then return 0 end
    end
  end
  return n
end
function Inv.take(id, n)
  for i = Inv.size, 1, -1 do
    local s = Inv.slots[i]
    if s and s.id == id then
      local k = math.min(n, s.n)
      s.n = s.n - k
      n = n - k
      if s.n <= 0 then Inv.slots[i] = nil end
      if n == 0 then return true end
    end
  end
  return n == 0
end
function Inv.free()
  local f = 0
  for i = 1, Inv.size do if not Inv.slots[i] then f = f + 1 end end
  return f
end

-- ---------------------------------------------------------------------------
-- crafting (DS-style tabs)
-- ---------------------------------------------------------------------------
Craft = {}
TABS = { "Tools", "Light", "Survival", "Combat", "Dress" }
RECIPES = {
  { tab = "Tools", out = "axe", n = 1, need = { { "bamboo", 2 }, { "flint", 2 } } },
  { tab = "Tools", out = "pick", n = 1, need = { { "wood", 2 }, { "flint", 3 } } },
  { tab = "Tools", out = "rope", n = 1, need = { { "grass", 3 } } },
  { tab = "Tools", out = "paper", n = 2, need = { { "bamboo", 3 } } },
  { tab = "Light", out = "torch", n = 1, need = { { "bamboo", 1 }, { "grass", 2 } } },
  { tab = "Light", out = "campfire", n = 1, need = { { "wood", 3 }, { "grass", 2 } } },
  { tab = "Light", out = "lantern", n = 1, need = { { "bamboo", 2 }, { "paper", 2 }, { "rope", 1 } } },
  { tab = "Survival", out = "bandage", n = 1, need = { { "herb", 1 }, { "grass", 1 } } },
  { tab = "Survival", out = "bedroll", n = 1, need = { { "grass", 6 }, { "rope", 1 } } },
  { tab = "Survival", out = "potkit", n = 1, need = { { "stone", 4 }, { "iron", 1 } } },
  { tab = "Combat", out = "shuriken", n = 5, need = { { "iron", 1 } } },
  { tab = "Combat", out = "barmor", n = 1, need = { { "bamboo", 6 }, { "rope", 2 } } },
  { tab = "Dress", out = "hat", n = 1, need = { { "reed", 4 } } },
  { tab = "Dress", out = "cloak", n = 1, need = { { "pelt", 3 }, { "rope", 1 } } },
}
function Craft.can(r)
  for _, nd in ipairs(r.need) do
    if Inv.count(nd[1]) < nd[2] then return false end
  end
  return true
end
function Craft.make(r)
  if not Craft.can(r) then return false end
  for _, nd in ipairs(r.need) do Inv.take(nd[1], nd[2]) end
  local left = Inv.add(r.out, r.n)
  if left > 0 then Drops.spawn(P.x, P.y, P.z + 4, r.out, left) end
  return true
end

-- cooking pot recipes (order-free)
POT = {
  { out = "sushi", need = { { "fish", 1 }, { "rice", 1 } } },
  { out = "stew", need = { { "meat", 1 }, { "mushroom", 1 } } },
  { out = "dango", need = { { "rice", 2 }, { "petal", 1 } } },
  { out = "mochi", need = { { "rice", 1 }, { "berries", 2 } } },
  { out = "tea", need = { { "herb", 2 } } },
}

SHOPS = {
  hanamura = { "onigiri", 8, "rice", 3, "torch", 6, "rope", 5, "axe", 20, "pick", 25, "bandage", 10, "campfire", 12 },
  kyo_smith = { "katana", 120, "steel", 320, "shuriken", 4, "barmor", 40, "sarmor", 200, "pick", 25 },
  kyo_tea = { "tea", 12, "dango", 15, "mochi", 18, "sushi", 30, "onigiri", 8 },
  minato = { "fish", 6, "sushi", 28, "paper", 6, "lantern", 70, "rope", 5, "potkit", 45 },
  yukimura = { "tea", 12, "stew", 40, "cloak", 90, "pick", 25, "torch", 6, "bedroll", 30 },
  takemura = { "bamboo", 2, "axe", 18, "shoot", 3, "campfire", 12, "paper", 6 },
}

-- ============================================================================
--  36 WORLD INTERACTION - harvesting (Z), picking/using (A), regrowth,
--  campfires that burn out, chests, signs, kodama, jizo blessings.
-- ============================================================================
World = { hits = {}, regrow = {}, fires = {}, chests = {}, signs = {}, kodama = {}, opened = {}, found = {}, blessed = {} }

local function cellOf(i) return (i - 1) % 240, (i - 1) // 240 end

-- change an object keeping its jittered position
function World.setObj(i, o)
  WO[i] = o
  if o > 0 then
    local x, y = cellOf(i)
    local k = (y // 8) * 30 + (x // 8)
    OLIST[k] = OLIST[k] or {}
    OLIST[k][i] = true
  end
end

local TOOLNAME = { axe = "a hatchet", pick = "a pickaxe" }

-- leaves shed by tall plants when chopped and when they fall
World.chop = {}
World.LEAVES = {
  default = { C_GREEN, C_LIME, C_DKGRN },
  [O_SAKURA] = { C_PINK, C_WHITE, C_PINK }, [O_MAPLE] = { C_RED, C_GOLD, C_WOOD }, [O_DEAD] = { C_GRAY, C_BROWN },
  [O_SNOWPINE] = { C_WHITE, C_DKGRN }, [O_BAMBOO] = { C_LIME, C_GREEN },
}

-- screen side (+1 right, -1 left) a chopped plant leans and falls towards
function World.chopSide(c)
  return (c.ux * math.cos(Cam.a) + c.uy * math.sin(Cam.a)) < 0 and -1 or 1
end

-- Z on a harvestable object. Rocks need a pickaxe; every blade chops wood,
-- but without a hatchet trees take 1.5x the swings and the bokken needs twice
-- as many for bamboo. Tall plants lean further away with every hit.
function World.hit(i)
  local o = WO[i]
  local d = OBJ[o]
  if not d or not d.tool then return end
  local ox, oy = objPos(i)
  local oz = math.max(WH[i], 0)
  if d.tool == "pick" and not Inv.has("pick") then
    UI.toast("Need " .. TOOLNAME.pick .. " for that")
    Sfx.play("clank")
    FX.burst(ox, oy, oz + 6, 3, { C_WHITE, C_GRAY }, 0.8, 10)
    return
  end
  local need = d.hits or 1
  if not Inv.has("axe") then
    if d.tool == "axe" then
      need = ceil(need * 1.5)
      if not World.axeHint then
        World.axeHint = true
        UI.toast("A hatchet chops faster (Craft > Tools)")
      end
    elseif o == O_BAMBOO and P.weapon == "bokken" then
      need = need * 2
    end
  end
  World.hits[i] = (World.hits[i] or 0) + 1
  if d.tool == "pick" then
    Sfx.play("mine")
    FX.burst(ox, oy, oz + 6, 5, { C_GRAY, C_WHITE, C_INDIGO }, 1.2, 14)
  else
    Sfx.play("chop")
    FX.burst(ox, oy, oz + 6, 6, { C_WOOD, C_TAN, C_CREAM }, 1.1, 16)
  end
  if d.h and d.h >= 40 then
    local dx, dy = ox - P.x, oy - P.y
    local l = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    World.chop[i] = { n = need, t = 14, ux = dx / l, uy = dy / l }
    FX.burst(ox, oy, oz + 34, 6, World.LEAVES[o] or World.LEAVES.default, 0.9, 30)
  end
  FX.shake(1)
  if World.hits[i] >= need then World.harvest(i) end
end

-- a chopped tree topples away from the blade, lands in a shower of leaves and
-- breaks into the drops it leaves behind
function World.fell(d, o, ox, oy, oz, c)
  local spr = SPR[d.spr]
  local leaves = World.LEAVES[o] or World.LEAVES.default
  local e = Ent.add({ kind = "fx", x = ox, y = oy, z = oz, r = 0, always = true })
  Sfx.play("fall")
  e.update = function(self)
    if self.t == 16 then
      local lx, ly = ox + c.ux * 18, oy + c.uy * 18
      FX.shake(3)
      FX.burst(lx, ly, oz + 4, 14, leaves, 1.4, 30)
      FX.dust(lx, ly, oz, 6)
      for _, dr in ipairs(d.drop or {}) do
        local n = rnd(dr[2], dr[3])
        if n > 0 then Drops.spawn(ox, oy, oz + 6, dr[1], n) end
      end
    elseif self.t > 26 then
      self.alive = false
      FX.burst(ox + c.ux * 10, oy + c.uy * 10, oz + 4, 8, { C_WOOD, C_TAN, C_BROWN }, 1.0, 20)
    end
  end
  e.draw = function(self)
    local k = math.min(1, self.t / 16)
    Render.billRot(spr, ox, oy, oz, false, d.pm, 1, World.chopSide(c) * (0.24 + k * k * (math.pi / 2 - 0.24)), 1.5)
  end
end

function World.harvest(i)
  local o = WO[i]
  local d = OBJ[o]
  local ox, oy = objPos(i)
  local oz = math.max(WH[i], 0)
  local c = World.chop[i]
  World.hits[i], World.chop[i] = nil, nil
  World.setObj(i, d.after or 0)
  if d.regrow then
    World.regrow[#World.regrow + 1] = { i = i, at = Clock.total + d.regrow, o = o }
  end
  if c and d.spr and SPR[d.spr] then
    World.fell(d, o, ox, oy, oz, c)
    return
  end
  for _, dr in ipairs(d.drop or {}) do
    local n = rnd(dr[2], dr[3])
    if n > 0 then Drops.spawn(ox, oy, oz + 6, dr[1], n) end
  end
end

-- regrowth / fires burning out (call once per frame; cheap)
function World.update()
  local now = Clock.total
  for _, c in pairs(World.chop) do
    if c.t > 0 then c.t = c.t - 1 end
  end
  if now % 30 == 0 then
    local r = World.regrow
    local j = 0
    for k = 1, #r do
      local e = r[k]
      local keep = true
      if now >= e.at then
        local ox, oy = objPos(e.i)
        if dist(ox, oy, P.x, P.y) > 24 then
          World.setObj(e.i, e.o)
          keep = false
        end
      end
      if keep then j = j + 1 r[j] = e end
    end
    for k = j + 1, #r do r[k] = nil end
    local f = World.fires
    j = 0
    for k = 1, #f do
      local e = f[k]
      if now >= e.at and WO[e.i] == O_FIRE then
        World.setObj(e.i, O_LOGS)
      elseif WO[e.i] == O_FIRE then
        j = j + 1
        f[j] = e
      end
    end
    for k = j + 1, #f do f[k] = nil end
  end
end

-- place an object (campfire, pot) in front of the player
function World.place(o)
  local fx, fy = math.cos(P.dir), math.sin(P.dir)
  local x, y = P.x + fx * 10, P.y + fy * 10
  local cx, cy = flr(x / 8), flr(y / 8)
  if not inmap(cx, cy) then return false end
  local i = cidx(cx, cy)
  if WO[i] ~= 0 or (WF[i] & (F_WATER | F_ROOF | F_MODEL)) ~= 0 or math.abs(math.max(WH[i], 0) - P.z) > 4 then
    UI.toast("Can't place that here")
    return false
  end
  setObj(cx, cy, o)
  if o == O_FIRE then World.fires[#World.fires + 1] = { i = i, at = Clock.total + 60 * 150 } end
  Sfx.play("place")
  return true
end

function World.interact(i)
  local o = WO[i]
  local d = OBJ[o]
  local ox, oy = objPos(i)
  local oz = math.max(WH[i], 0)
  if d.hand then
    Sfx.play("pick")
    for _, dr in ipairs(d.drop or {}) do
      local n = rnd(dr[2], dr[3])
      if n > 0 then Drops.give(dr[1], n, ox, oy, oz) end
    end
    World.setObj(i, d.after or 0)
    if d.regrow then World.regrow[#World.regrow + 1] = { i = i, at = Clock.total + d.regrow, o = o } end
    return
  end
  local t = d.talk
  if t == "chest" then
    local c = World.chests[i] or { "ryo", rnd(10, 30) }
    World.setObj(i, O_CHESTO)
    World.opened[i] = true
    Sfx.play("chest")
    FX.burst(ox, oy, oz + 8, 12, { C_GOLD, C_WHITE }, 1.2, 30)
    Drops.give(c[1], c[2], ox, oy, oz)
    UI.banner("Found " .. (c[1] == "ryo" and (c[2] .. " ryo") or ((c[2] > 1 and (c[2] .. " ") or "") .. ITEM[c[1]].n)) .. "!")
  elseif t == "sign" then
    local s = World.signs[i] or ("Welcome to " .. REG[WR[i]].name .. ".")
    Dialog.say("Signpost", s)
  elseif t == "kodama" then
    World.setObj(i, 0)
    World.found[i] = true
    P.seeds = P.seeds + 1
    Sfx.play("kodama")
    FX.burst(ox, oy, oz + 6, 14, { C_WHITE, C_LIME, C_GREEN }, 1.4, 30)
    UI.banner("Ya-ha-ha! Kodama found! (" .. P.seeds .. " seeds)")
    Quest.event("kodama")
  elseif t == "shrine" then
    Shrine.interact(i)
  elseif t == "fire" then
    Menu.open("cook", { fire = true })
  elseif t == "pot" then
    Menu.open("cook", { pot = true })
  elseif t == "logs" then
    if Inv.has("wood") then
      Inv.take("wood", 1)
      World.setObj(i, O_FIRE)
      World.fires[#World.fires + 1] = { i = i, at = Clock.total + 60 * 150 }
      Sfx.play("fire")
      UI.toast("You rekindle the fire")
    else
      UI.toast("Needs 1 wood to rekindle")
    end
  elseif t == "statue" then
    Shrine.statue()
  elseif t == "jizo" then
    local day = Clock.day
    if World.blessed[i] ~= day then
      World.blessed[i] = day
      Player.heal(8)
      Sfx.play("heal")
      FX.burst(ox, oy, oz + 8, 10, { C_WHITE, C_GOLD }, 1, 30)
      Dialog.say("Jizo", "You bow to the little guardian. Warmth fills you. (+2 hearts)")
    else
      Dialog.say("Jizo", "The Jizo smiles silently. Come back tomorrow.")
    end
  end
end

-- ============================================================================
--  40 ENTITIES & PHYSICS
--  Terrain is a heightfield of 8x8 cells; anything taller than z+step is a
--  solid square, objects with r/h are solid cylinders. Movement integrates
--  velocity then pushes the body's circle out of solids (robust sliding, no
--  sticking on ledges). Ground height includes object tops and sloped roofs,
--  so you can stand on boulders, stumps and rooftops.
-- ============================================================================
ENTS = {}
Ent = {}
GRAV = 0.22

-- height of a cell's walkable top (water surface for water cells)
local function cellTop(cx, cy)
  if cx < 0 or cy < 0 or cx >= 240 or cy >= 112 then return -3 end
  local h = WH[cy * 240 + cx + 1]
  if h < 0 then return h + 1 end
  return h
end
Ent.cellTop = cellTop

-- ground height at a point (centre sample): roofs + object tops
function groundAt(x, y)
  local cx, cy = flr(x / 8), flr(y / 8)
  if cx < 0 or cy < 0 or cx >= 240 or cy >= 112 then return -3 end
  local i = cy * 240 + cx + 1
  local h = WH[i]
  if h < 0 then h = h + 1 end
  if (WF[i] & F_ROOF) ~= 0 then
    local b = BLD[WB[i]]
    if b and b.roof > 0 then h = Build_roofH(b, x, y) end
  end
  for dy = -1, 1 do
    for dx = -1, 1 do
      local j = i + dy * 240 + dx
      local o = WO[j]
      if o and o > 0 then
        local d = OBJ[o]
        if d.r then
          local ox, oy = objPos(j)
          local ex, ey = x - ox, y - oy
          if ex * ex + ey * ey < d.r * d.r then
            local top = math.max(WH[j], 0) + d.h
            if top > h then h = top end
          end
        end
      end
    end
  end
  return h
end

function isWaterAt(x, y)
  local cx, cy = flr(x / 8), flr(y / 8)
  if cx < 0 or cy < 0 or cx >= 240 or cy >= 112 then return true end
  return (WF[cy * 240 + cx + 1] & F_WATER) ~= 0
end
function flagsAt(x, y)
  local cx, cy = flr(x / 8), flr(y / 8)
  if cx < 0 or cy < 0 or cx >= 240 or cy >= 112 then return F_WATER end
  return WF[cy * 240 + cx + 1]
end

-- push a body out of solid cells/cylinders; returns hit flag and wall height
function Ent.resolve(e)
  local r = e.r
  local x, y = e.x, e.y
  local lim = e.z + (e.step or 4.5)
  local hit, wallH, wnx, wny = false, nil, 0, 0
  local avoidWater = e.dry
  for pass = 1, 2 do
    local cx0, cy0, cx1, cy1 = flr((x - r) / 8), flr((y - r) / 8), flr((x + r) / 8), flr((y + r) / 8)
    for cy = cy0, cy1 do
      for cx = cx0, cx1 do
        local h = cellTop(cx, cy)
        local solid = h > lim
        if not solid and avoidWater then
          solid = (cx < 0 or cy < 0 or cx >= 240 or cy >= 112) or (WF[cy * 240 + cx + 1] & F_WATER) ~= 0
          if solid then h = lim + 99 end
        end
        if solid then
          local qx0, qy0 = cx * 8, cy * 8
          local px = x < qx0 and qx0 or (x > qx0 + 8 and qx0 + 8 or x)
          local py = y < qy0 and qy0 or (y > qy0 + 8 and qy0 + 8 or y)
          local dx, dy = x - px, y - py
          local d2 = dx * dx + dy * dy
          if d2 < r * r then
            local nx, ny
            if d2 > 1e-6 then
              local d = math.sqrt(d2)
              nx, ny = dx / d, dy / d
              x, y = px + nx * r, py + ny * r
            else
              -- centre inside the square: leave by the nearest side
              local l, rr, t, b = x - qx0, qx0 + 8 - x, y - qy0, qy0 + 8 - y
              local m = math.min(l, rr, t, b)
              if m == l then nx, ny = -1, 0 x = qx0 - r
              elseif m == rr then nx, ny = 1, 0 x = qx0 + 8 + r
              elseif m == t then nx, ny = 0, -1 y = qy0 - r
              else nx, ny = 0, 1 y = qy0 + 8 + r end
            end
            hit = true
            if not wallH or h > wallH then wallH, wnx, wny = h, nx, ny end
          end
        end
      end
    end
    -- object cylinders
    local ccx, ccy = flr(x / 8), flr(y / 8)
    for yy = ccy - 1, ccy + 1 do
      for xx = ccx - 1, ccx + 1 do
        if xx >= 0 and yy >= 0 and xx < 240 and yy < 112 then
          local j = yy * 240 + xx + 1
          local o = WO[j]
          if o > 0 then
            local d = OBJ[o]
            if d.r then
              local top = math.max(WH[j], 0) + d.h
              if top > lim then
                local ox, oy = objPos(j)
                local dx, dy = x - ox, y - oy
                local rr = r + d.r
                local d2 = dx * dx + dy * dy
                if d2 < rr * rr then
                  local dd = math.sqrt(d2)
                  if dd < 0.001 then dx, dy, dd = 1, 0, 1 end
                  x, y = ox + dx / dd * rr, oy + dy / dd * rr
                  hit = true
                  if not wallH or top > wallH then wallH, wnx, wny = top, dx / dd, dy / dd end
                end
              end
            end
          end
        end
      end
    end
  end
  e.x, e.y = x, y
  return hit, wallH, wnx, wny
end

-- standard walker physics: horizontal velocity + gravity + ground snap
function Ent.physics(e)
  e.x = e.x + e.vx
  e.y = e.y + e.vy
  local hit, wh, nx, ny = Ent.resolve(e)
  local g = groundAt(e.x, e.y)
  if e.fly then
    -- flyers hover at their own height above ground
    local target = g + (e.hover or 10)
    e.z = e.z + (target - e.z) * 0.08
    e.ground = false
  elseif e.z > g + 0.05 or e.vz > 0 then
    e.vz = e.vz - (e.grav or GRAV)
    if e.vz < -5 then e.vz = -5 end
    e.z = e.z + e.vz
    e.ground = false
    if e.z <= g then
      e.z = g
      e.landV = e.vz
      e.vz = 0
      e.ground = true
    end
  else
    -- walking down small steps snaps, bigger drops fall
    if g < e.z - 4.6 then
      e.ground = false
    else
      e.z = g
      e.ground = true
    end
  end
  return hit, wh, nx, ny
end

function Ent.add(e)
  e.t = e.t or 0
  e.vx, e.vy, e.vz = e.vx or 0, e.vy or 0, e.vz or 0
  e.z = e.z or groundAt(e.x, e.y)
  e.r = e.r or 3
  e.alive = true
  ENTS[#ENTS + 1] = e
  return e
end

-- update all live entities near the player; compact dead ones
function Ent.updateAll(px, py)
  local n = #ENTS
  local j = 0
  for i = 1, n do
    local e = ENTS[i]
    if e.alive then
      local dx, dy = e.x - px, e.y - py
      if e.always or (dx * dx + dy * dy < 260 * 260) then
        e.t = e.t + 1
        if e.update then e:update() end
      elseif e.far then
        e:far()
      end
    end
    if e.alive then
      j = j + 1
      ENTS[j] = e
    end
  end
  for i = j + 1, n do ENTS[i] = nil end
end

function Ent.drawAll(px, py)
  for i = 1, #ENTS do
    local e = ENTS[i]
    if e.alive and e.draw then
      local dx, dy = e.x - px, e.y - py
      if dx * dx + dy * dy < 320 * 320 then e:draw() end
    end
  end
end

-- nearest entity matching pred within radius
function Ent.nearest(x, y, rad, pred)
  local best, bd = nil, rad * rad
  for i = 1, #ENTS do
    local e = ENTS[i]
    if e.alive and pred(e) then
      local d = dist2(x, y, e.x, e.y)
      if d < bd then best, bd = e, d end
    end
  end
  return best, best and math.sqrt(bd)
end

-- screen-relative facing: returns view ("s","f","b") and flip
function Ent.view(dir)
  local wx, wy = math.cos(dir), math.sin(dir)
  local ca, sa = math.cos(Cam.a), math.sin(Cam.a)
  local sx = wx * ca + wy * sa
  local up = wx * sa - wy * ca
  if math.abs(sx) >= math.abs(up) * 0.75 then
    return "s", sx < 0
  elseif up > 0 then
    return "b", sx < 0
  end
  return "f", sx < 0
end

-- shadow under an entity, on the ground below it
function Ent.shadow(e, rad)
  local g = groundAt(e.x, e.y)
  local s = rad or 4
  local hgt = e.z - g
  if hgt > 0 then s = s * math.max(0.5, 1 - hgt / 80) end
  Render.ground(SPR.shadow, e.x, e.y, g + 0.4, s)
end


-- ============================================================================
--  41 PLAYER - the ninja controller.
--  States: ground, air, climb, swim, plunge, dead. Attacks overlay ground/air.
--  Movement is camera-relative. Stamina (BotW wheel) drives sprint, climb,
--  glide and swim; running dry exhausts you until it fully refills.
-- ============================================================================
Player = {}
P = nil

local WALK, RUN, SWIM_SP, GLIDE_SP = 0.95, 1.6, 0.6, 1.55
local JUMP_V, DJUMP_V = 2.62, 2.45

function Player.new(x, y)
  local p = {
    kind = "player", x = x, y = y, r = 3, step = 4.5, dir = math.pi / 2, state = "ground",
    vx = 0, vy = 0, vz = 0, t = 0, ground = true,
    hp = 16, maxhp = 16, stam = 100, maxstam = 100, hunger = 85, ryo = 30, orbs = 0, seeds = 0,
    exhausted = false, stamDelay = 0, iframes = 0, flash = 0, jumps = 0, coyote = 0, anim = 0,
    atk = 0, combo = 0, queued = false, hitDone = false, pushT = 0, fallTop = 0, glide = false,
    weapon = "bokken", armor = nil, light = nil, lightFuel = 0, has = {}, warm = 0, cold = 0, dark = 0,
    safeX = x, safeY = y, safeZ = 0, spawnX = x, spawnY = y, kills = {},
  }
  p.z = groundAt(x, y)
  P = p
  return p
end

local function hasAbility(k) return P.has[k] end

-- world move vector from screen-space arrows
local function inputDir()
  local ix, iy = In.axis()
  if ix == 0 and iy == 0 then return 0, 0, false end
  local rx, ry = Cam.right()
  local fx, fy = Cam.fwd()
  local wx, wy = rx * ix - fx * iy, ry * ix - fy * iy
  local l = math.sqrt(wx * wx + wy * wy)
  return wx / l, wy / l, true
end

local function useStam(n)
  local p = P
  p.stam = p.stam - n
  p.stamDelay = 40
  if p.stam <= 0 then
    p.stam = 0
    p.exhausted = true
    Sfx.play("tired")
  end
end

function Player.damage(dmg, sx, sy, kind)
  local p = P
  if p.iframes > 0 or p.state == "dead" or Game.cutscene then return false end
  local def = (p.armor and ITEM[p.armor].def) or 0
  dmg = math.max(1, dmg - def)
  p.hp = p.hp - dmg
  p.iframes = 50
  p.flash = 10
  FX.shake(3)
  FX.hitstop(4)
  Sfx.play("hurt")
  if sx then
    local dx, dy = p.x - sx, p.y - sy
    local l = math.sqrt(dx * dx + dy * dy) + 0.001
    p.vx, p.vy = dx / l * 2.2, dy / l * 2.2
    if p.state == "ground" then p.vz = 1.2 p.state = "air" end
  end
  if p.state == "climb" then p.state = "air" end
  if p.hp <= 0 then
    p.hp = 0
    Player.die(kind)
  end
  return true
end

function Player.heal(q)
  P.hp = math.min(P.maxhp, P.hp + q)
end

function Player.die(why)
  local p = P
  p.state = "dead"
  p.deadT = 0
  p.vx, p.vy = 0, 0
  Sfx.play("die")
  Music.play(nil)
  Game.onDeath(why)
end

function Player.respawn()
  local p = P
  p.x, p.y = p.spawnX, p.spawnY
  p.z = groundAt(p.x, p.y)
  p.hp = p.maxhp
  p.stam = p.maxstam
  p.exhausted = false
  p.hunger = math.max(p.hunger, 50)
  p.state = "ground"
  p.vx, p.vy, p.vz = 0, 0, 0
  p.iframes = 120
  p.dark = 0
  Cam.x, Cam.y, Cam.z = p.x, p.y, p.z
end

-- ---------------------------------------------------------------------------
-- combat
-- ---------------------------------------------------------------------------
local function weaponDmg()
  local w = ITEM[P.weapon or "bokken"]
  return (w and w.dmg) or 1
end
Player.weaponDmg = weaponDmg

-- the cell in front of the player (for harvesting)
local function frontObject(reach)
  local p = P
  local best, bd = nil, 1e9
  local fx, fy = math.cos(p.dir), math.sin(p.dir)
  local cx, cy = flr(p.x / 8), flr(p.y / 8)
  for yy = cy - 2, cy + 2 do
    for xx = cx - 2, cx + 2 do
      if xx >= 0 and yy >= 0 and xx < 240 and yy < 112 then
        local i = yy * 240 + xx + 1
        local o = WO[i]
        if o > 0 then
          local ox, oy = objPos(i)
          local dx, dy = ox - p.x, oy - p.y
          local d = math.sqrt(dx * dx + dy * dy)
          local oz = (WF[i] & F_ROOF) ~= 0 and groundAt(ox, oy) or math.max(WH[i], 0)
          if d < reach and (d < 5 or (dx * fx + dy * fy) / d > 0.35) and math.abs(oz - p.z) < 14 then
            if d < bd then best, bd = i, d end
          end
        end
      end
    end
  end
  return best, bd
end
Player.frontObject = frontObject

local function swingHits()
  local p = P
  local dmg = weaponDmg()
  if p.combo == 3 then dmg = dmg + 1 end
  local fx, fy = math.cos(p.dir), math.sin(p.dir)
  local hitAny = false
  for _, e in ipairs(ENTS) do
    if e.alive and e.hostile and e.hp and e.hp > 0 then
      local dx, dy = e.x - p.x, e.y - p.y
      local d = math.sqrt(dx * dx + dy * dy)
      local reach = 17 + (e.r or 3)
      if d < reach and math.abs((e.z + (e.hz or 6)) - (p.z + 6)) < 16 + (e.tall or 0) and (d < 6 or (dx * fx + dy * fy) / d > 0.2) then
        Enemy.hurt(e, dmg, p.x, p.y, p.combo == 3 and 2.6 or 1.6)
        hitAny = true
      end
    end
  end
  if not hitAny then
    local i = frontObject(14)
    if i then World.hit(i) end
  end
  if hitAny then FX.hitstop(3) end
end

local function startAttack()
  local p = P
  if p.atk > 0 then
    if p.atk < 9 then p.queued = true end
    return
  end
  p.combo = (p.comboT and p.comboT > 0) and (p.combo % 3) + 1 or 1
  p.atk = p.combo == 3 and 22 or 16
  p.hitDone = false
  p.queued = false
  Sfx.play("swing")
end

local function throwShuriken()
  local p = P
  if Inv.count("shuriken") <= 0 then
    UI.toast("No shuriken")
    return
  end
  Inv.take("shuriken", 1)
  local fx, fy = math.cos(p.dir), math.sin(p.dir)
  Proj.spawn("shuriken", p.x + fx * 4, p.y + fy * 4, p.z + 8, fx * 3.6, fy * 3.6, 0, true, 2)
  Sfx.play("throw")
end

-- ---------------------------------------------------------------------------
-- interaction (A)
-- ---------------------------------------------------------------------------
function Player.findInteract()
  local p = P
  local fx, fy = math.cos(p.dir), math.sin(p.dir)
  -- NPCs and interactive entities first
  local best, bd = nil, 20
  for _, e in ipairs(ENTS) do
    if e.alive and e.interact then
      local dx, dy = e.x - p.x, e.y - p.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < (e.ireach or 16) and math.abs(e.z - p.z) < 16 and d < bd then best, bd = e, d end
    end
  end
  if best then return "ent", best end
  local i = frontObject(13)
  if i then
    local d = OBJ[WO[i]]
    if d.hand or d.talk then return "obj", i end
  end
  -- pagoda summit
  for _, t in ipairs(TOWERS) do
    if dist(p.x, p.y, t.x, t.y) < 16 and p.z >= t.top - 2 then return "tower", t end
  end
  return nil
end

local function interact()
  local kind, tgt = Player.findInteract()
  if kind == "ent" then
    tgt:interact()
  elseif kind == "obj" then
    World.interact(tgt)
  elseif kind == "tower" then
    Quest.tower(tgt)
  end
end

-- ---------------------------------------------------------------------------
-- update
-- ---------------------------------------------------------------------------
function Player.update()
  local p = P
  p.anim = p.anim + 1
  if p.iframes > 0 then p.iframes = p.iframes - 1 end
  if p.flash > 0 then p.flash = p.flash - 1 end
  if p.comboT and p.comboT > 0 then p.comboT = p.comboT - 1 end

  if p.state == "dead" then
    p.deadT = p.deadT + 1
    return
  end

  -- hotkeys
  if In.p.rotl then Cam.ta = Cam.ta + math.pi / 4 Sfx.play("menu") end
  if In.p.rotr then Cam.ta = Cam.ta - math.pi / 4 Sfx.play("menu") end
  for k = 1, 10 do
    if In.p["s" .. k] then UI.useSlot(k) end
  end

  local mx, my, moving = inputDir()
  local st = p.state
  local f = flagsAt(p.x, p.y)
  local inWater = (f & F_WATER) ~= 0 and p.z <= -2.5

  -- stamina regen
  if p.stamDelay > 0 then p.stamDelay = p.stamDelay - 1
  elseif st == "ground" and p.stam < p.maxstam then
    p.stam = math.min(p.maxstam, p.stam + (p.exhausted and 0.45 or 0.75))
    if p.stam >= p.maxstam then p.exhausted = false end
  end

  if st == "ground" then
    local sp = WALK
    local running = In.h.run and moving and not p.exhausted and p.atk == 0
    if running then sp = RUN useStam(0.32) end
    if (f & F_SHALLOW) ~= 0 then sp = sp * 0.65 end
    if p.atk > 0 then sp = p.atk > (p.combo == 3 and 16 or 11) and 0.9 or 0.15 end
    local tx, ty = mx * sp, my * sp
    if p.atk > 0 and not moving then
      tx, ty = math.cos(p.dir) * sp * 0.6, math.sin(p.dir) * sp * 0.6
    end
    p.vx = approach(p.vx, tx, 0.28)
    p.vy = approach(p.vy, ty, 0.28)
    if moving and p.atk == 0 then p.dir = math.atan(my, mx) end
    p.running = running
    if In.p.jump then
      p.vz = JUMP_V
      p.state = "air"
      p.jumps = 1
      p.fallTop = p.z
      Sfx.play("jump")
      FX.dust(p.x, p.y, p.z, 3)
    end
    if In.p.atk then startAttack() end
    if In.p.throw then throwShuriken() end
    if In.p.use then interact() end
    if In.p.ok then interact() end
    if inWater then p.state = "swim" end
  elseif st == "air" then
    local sp = p.glide and GLIDE_SP or (p.running and RUN or WALK * 1.05)
    p.vx = approach(p.vx, mx * sp, p.glide and 0.1 or 0.14)
    p.vy = approach(p.vy, my * sp, p.glide and 0.1 or 0.14)
    if moving then p.dir = math.atan(my, mx) end
    if In.p.jump then
      if p.coyote > 0 then
        p.vz = JUMP_V
        p.jumps = 1
        p.coyote = 0
        p.fallTop = p.z
        Sfx.play("jump")
      elseif hasAbility("djump") and p.jumps < 2 then
        p.vz = DJUMP_V
        p.jumps = 2
        p.fallTop = p.z
        Sfx.play("djump")
        FX.ring(p.x, p.y, p.z, C_GREEN)
      end
    end
    p.glide = false
    if In.h.jump and p.vz < -0.3 and hasAbility("kite") and not p.exhausted and p.stam > 0 then
      p.glide = true
      if p.vz < -0.42 then p.vz = -0.42 end
      useStam(0.2)
      p.fallTop = p.z
    end
    if In.p.atk then
      if p.z - groundAt(p.x, p.y) > 10 then
        p.state = "plunge"
        p.vz = -4.2
        p.vx, p.vy = 0, 0
        Sfx.play("swing")
      else
        startAttack()
      end
    end
    if In.p.throw then throwShuriken() end
    if p.coyote > 0 then p.coyote = p.coyote - 1 end
  elseif st == "climb" then
    p.vx, p.vy = 0, 0
    local ix, iy = In.axis()
    local nx, ny = p.wnx, p.wny
    -- tangent oriented so that "right" on screen moves right
    local tx, ty = -ny, nx
    local ca, sa = math.cos(Cam.a), math.sin(Cam.a)
    if tx * ca + ty * sa < 0 then tx, ty = -tx, -ty end
    local climbing = (iy ~= 0 or ix ~= 0)
    if p.leap and p.leap > 0 then
      p.leap = p.leap - 1
      p.z = p.z + 1.6
    elseif iy < 0 then
      p.z = p.z + 0.55
    elseif iy > 0 then
      p.z = p.z - 0.7
    end
    if ix ~= 0 then
      p.x = p.x + tx * ix * 0.5
      p.y = p.y + ty * ix * 0.5
    end
    useStam(climbing and 0.3 or 0.08)
    p.stamDelay = 40
    if In.p.jump then
      if iy > 0 then
        -- push away from the wall
        p.state = "air"
        p.vz = 1.6
        p.vx, p.vy = nx * 1.4, ny * 1.4
        p.dir = math.atan(ny, nx)
      elseif p.stam > 10 then
        p.leap = 12
        useStam(14)
        Sfx.play("jump")
      end
    end
    -- still on a wall? probe one unit into it
    local qx, qy = p.x - nx * (p.r + 1.5), p.y - ny * (p.r + 1.5)
    local wallTop = groundAt(qx, qy)
    local g = groundAt(p.x, p.y)
    if p.z <= g then
      p.z = g
      p.state = "ground"
    elseif wallTop <= p.z + 3 then
      -- mantle over the top
      p.x, p.y = qx - nx * 2, qy - ny * 2
      p.z = groundAt(p.x, p.y)
      p.state = "ground"
      p.vz = 0
      Sfx.play("land")
    elseif p.exhausted then
      p.state = "air"
      p.vz = 0
      p.fallTop = p.z
    end
    p.dir = math.atan(-ny, -nx)
  elseif st == "swim" then
    local sp = SWIM_SP
    if In.h.run and moving and not p.exhausted then sp = 0.95 useStam(0.25) else useStam(moving and 0.09 or 0.05) end
    p.vx = approach(p.vx, mx * sp, 0.12)
    p.vy = approach(p.vy, my * sp, 0.12)
    if moving then p.dir = math.atan(my, mx) end
    if p.anim % 30 == 0 and moving then FX.ripple(p.x, p.y, -3) end
    if p.exhausted then
      -- too tired: sink and wash ashore at the last safe spot
      Player.damage(4, nil, nil, "drown")
      if p.state ~= "dead" then
        p.x, p.y, p.z = p.safeX, p.safeY, p.safeZ
        p.state = "ground"
        p.stam = p.maxstam * 0.5
        p.exhausted = false
        UI.toast("You washed ashore...")
      end
      return
    end
    -- X: leap out of the water onto a bank (or at a cliff, then climb it)
    if In.p.jump then
      p.state = "air"
      p.vz = JUMP_V * 1.1
      p.jumps = 1
      p.fallTop = p.z
      p.vx, p.vy = p.vx + math.cos(p.dir) * 0.6, p.vy + math.sin(p.dir) * 0.6
      useStam(6)
      Sfx.play("splash")
      FX.burst(p.x, p.y, -2, 10, { C_WHITE, C_BLUE }, 1.2, 20)
    end
  elseif st == "plunge" then
    p.vx, p.vy = 0, 0
  end

  -- attack timing
  if p.atk > 0 then
    p.atk = p.atk - 1
    local activeAt = (p.combo == 3) and 14 or 11
    if not p.hitDone and p.atk <= activeAt then
      p.hitDone = true
      swingHits()
      local fx, fy = math.cos(p.dir), math.sin(p.dir)
      FX.slash(p.x + fx * 9, p.y + fy * 9, p.z + 6, p.combo)
    end
    if p.atk == 0 then
      p.comboT = 14
      if p.queued then
        p.queued = false
        startAttack()
      end
    end
  end

  -- physics
  local wasGround = p.ground
  local preZ = p.z
  if p.state == "climb" then
    Ent.resolve(p)
  elseif p.state == "swim" then
    p.x, p.y = p.x + p.vx, p.y + p.vy
    -- banks up to one terrain step (4) above the water can be swum onto
    p.step = 7.5
    Ent.resolve(p)
    p.step = 4.5
    p.z = -3
    local g = groundAt(p.x, p.y)
    if not isWaterAt(p.x, p.y) and g <= p.z + 7.5 then
      p.z = g
      p.state = "ground"
      FX.burst(p.x, p.y, g, 6, { C_WHITE, C_BLUE }, 0.8, 14)
    end
  else
    local hit, wh, nx, ny = Ent.physics(p)
    -- climbing: pushing into a wall that is too tall to step on
    if hit and wh and wh > p.z + 4.5 and moving and (mx * nx + my * ny) < -0.6 and not p.exhausted and p.atk == 0 and p.state ~= "plunge" then
      p.pushT = p.pushT + 1
      local need = p.state == "air" and 2 or 7
      if p.pushT > need and wh < 400 then
        p.state = "climb"
        p.wnx, p.wny = nx, ny
        p.vz = 0
        p.glide = false
        p.pushT = 0
      end
    else
      p.pushT = 0
    end
    if p.state == "ground" and not p.ground then
      p.state = "air"
      p.coyote = 7
      p.fallTop = p.z
    elseif (p.state == "air" or p.state == "plunge") and p.ground then
      local fall = p.fallTop - p.z
      if p.state == "plunge" then
        FX.shake(4)
        Sfx.play("slam")
        FX.ring(p.x, p.y, p.z, C_WHITE)
        for _, e in ipairs(ENTS) do
          if e.alive and e.hostile and e.hp and e.hp > 0 and dist(e.x, e.y, p.x, p.y) < 22 then
            Enemy.hurt(e, weaponDmg() * 2, p.x, p.y, 3)
          end
        end
        p.atk = 0
      else
        Sfx.play("land")
      end
      FX.dust(p.x, p.y, p.z, 4)
      p.state = "ground"
      p.glide = false
      p.jumps = 0
      if fall > 46 then
        Player.damage(math.min(16, flr((fall - 46) / 10) + 2), nil, nil, "fall")
      end
    end
    if p.state == "air" and p.vz > 0 then p.fallTop = math.max(p.fallTop, p.z) end
    if inWater and p.state ~= "swim" and p.z <= -2.5 then p.state = "swim" p.glide = false end
  end

  -- remember safe ground for respawn after drowning/falling into hazards
  if p.state == "ground" and not isWaterAt(p.x, p.y) and (flagsAt(p.x, p.y) & F_HAZ) == 0 and p.anim % 20 == 0 then
    p.safeX, p.safeY, p.safeZ = p.x, p.y, p.z
  end
  if (flagsAt(p.x, p.y) & F_HAZ) ~= 0 and p.state == "ground" then
    if Player.damage(4, nil, nil, "lava") and p.state ~= "dead" then
      p.x, p.y, p.z = p.safeX, p.safeY, p.safeZ
    end
  end
  p.moving = moving
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------
function Player.sprite()
  local p = P
  local view, flip = Ent.view(p.dir)
  local walkF = (p.anim // 8) % 2
  local moving = (math.abs(p.vx) + math.abs(p.vy)) > 0.15
  local name
  if p.state == "climb" then
    name = "n_climb"
    flip = (p.anim // 12) % 2 == 0
    return name, flip
  elseif p.state == "swim" then
    return "n_swim", flip
  elseif p.state == "air" and p.glide then
    return "n_glide", flip
  end
  if p.atk > 0 then
    view = "s"
    name = (p.combo == 2) and "n_s_slash2" or "n_s_slash1"
    if p.combo == 3 then name = (p.atk > 11) and "n_s_slash1" or "n_s_slash2" end
    return name, flip
  end
  if p.state == "air" or p.state == "plunge" then
    return p.vz > 0 and "n_s_jump" or "n_s_fall", flip
  end
  if view == "s" then
    if moving then
      local k = (p.anim // (p.running and 5 or 7)) % 4
      name = (k == 0 or k == 2) and "n_s_idle" or (k == 1 and "n_s_walk1" or "n_s_walk2")
    else
      name = "n_s_idle"
    end
  elseif view == "f" then
    name = moving and "n_f_walk1" or "n_f_idle"
    if moving then flip = walkF == 1 end
  else
    name = moving and "n_b_walk1" or "n_b_idle"
    if moving then flip = walkF == 1 end
  end
  return name, flip
end

function Player.draw()
  local p = P
  if p.state == "dead" and p.deadT > 40 then return end
  if p.iframes > 0 and (p.anim // 3) % 2 == 0 and p.flash == 0 then
    Ent.shadow(p, 4)
    return
  end
  Ent.shadow(p, 4)
  local name, flip = Player.sprite()
  local r = SPR[name]
  local z = p.z
  if p.state == "swim" then z = -3 end
  -- x-ray silhouette when hidden behind terrain: draw flat silhouette first,
  -- then the real sprite depth-tested on top
  Pal.solid(C_INDIGO)
  Render.billFlat(r, p.x, p.y, z, flip)
  Render.setPM(nil)
  Pal.reset()
  local pm = nil
  if p.flash > 0 then pm = PM_WHITE end
  Render.bill(r, p.x, p.y, z, flip, pm)
  Render.setPM(nil)
end

-- ============================================================================
--  42 ENEMIES - data-driven foes with a telegraphed windup before each hit.
--  idle -> chase -> windup (flashing) -> strike -> recover; hurt knocks back.
--  Enemies cannot jump: climbing a ledge is a valid escape (except flyers,
--  ghosts and ranged foes).
-- ============================================================================
Enemy = {}
ETYPE = {
  bandit = { spr = { "ban_s1", "ban_s2" }, atk = "ban_atk", hp = 4, sp = 0.72, dmg = 2, aggro = 80, reach = 13, windup = 22, cd = 46, r = 3,
    drops = { { "ryo", 2, 6 }, { "rice", 0, 1 } }, name = "Bandit" },
  ronin = { base = "bandit", pm = { [C_WOOD] = C_INDIGO, [C_BROWN] = C_NIGHT, [C_RED] = C_GRAY, [C_TAN] = C_GRAY }, hp = 10, dmg = 3, sp = 0.85,
    windup = 18, name = "Ronin", drops = { { "ryo", 10, 18 }, { "iron", 0, 1 } } },
  wolf = { spr = { "wolf1", "wolf2" }, hp = 3, sp = 1.12, dmg = 2, aggro = 90, reach = 12, windup = 14, cd = 40, r = 4, lunge = true,
    drops = { { "meat", 0, 1 }, { "pelt", 0, 1 } }, name = "Wolf", pack = true },
  snowwolf = { base = "wolf", pm = { [C_GRAY] = C_WHITE, [C_WHITE] = C_CREAM, [C_INDIGO] = C_GRAY }, hp = 5, dmg = 3, name = "Snow Wolf",
    drops = { { "meat", 1, 1 }, { "pelt", 1, 2 } } },
  boar = { spr = { "boar1", "boar2" }, hp = 5, sp = 0.62, dmg = 3, aggro = 70, reach = 13, windup = 28, cd = 70, r = 5, charge = true,
    drops = { { "meat", 1, 2 } }, name = "Boar" },
  kappa = { spr = { "kap1", "kap2" }, hp = 4, sp = 0.75, dmg = 2, aggro = 70, reach = 12, windup = 18, cd = 50, r = 3, hop = true, swims = true,
    drops = { { "cucumber", 0, 1 }, { "fish", 0, 1 }, { "ryo", 1, 4 } }, name = "Kappa" },
  tengu = { spr = { "ten1", "ten2" }, hp = 5, sp = 0.85, dmg = 2, aggro = 110, reach = 12, windup = 20, cd = 70, r = 4, fly = true, hover = 16,
    ranged = "feather", range = 70, drops = { { "feather", 1, 2 }, { "ryo", 2, 6 } }, name = "Tengu", anim = 6 },
  yurei = { spr = { "yur1", "yur2" }, hp = 4, sp = 0.5, dmg = 2, aggro = 100, reach = 12, windup = 22, cd = 60, r = 3, ghost = true, hover = 3,
    night = true, drops = { { "essence", 1, 1 } }, name = "Yurei", front = true },
  onibi = { spr = { "wisp1", "wisp2" }, hp = 2, sp = 0.55, dmg = 2, aggro = 110, reach = 0, ranged = "fire", range = 80, cd = 100, r = 3, fly = true,
    hover = 10, night = true, light = 26, drops = { { "ember", 1, 1 } }, name = "Onibi", front = true, anim = 6 },
  oni = { spr = { "oni1", "oni1" }, atk = "oni_atk", hp = 16, sp = 0.48, dmg = 4, aggro = 90, reach = 19, windup = 34, cd = 70, r = 6, smash = true,
    drops = { { "iron", 1, 2 }, { "ryo", 12, 24 } }, name = "Oni", tall = 8, heavy = true },
  spider = { spr = { "spi1", "spi2" }, hp = 3, sp = 1.0, dmg = 2, aggro = 80, reach = 11, windup = 16, cd = 50, r = 4, ranged = "web", range = 60,
    drops = { { "silk", 1, 2 } }, name = "Spider" },
  kitsune = { spr = { "fox1", "fox2" }, hp = 6, sp = 1.2, dmg = 2, aggro = 100, reach = 12, windup = 16, cd = 45, r = 4, blink = true, ranged = "fire",
    range = 60, drops = { { "ryo", 10, 25 } }, name = "Kitsune" },
}
for k, t in pairs(ETYPE) do
  if t.base then
    local b = ETYPE[t.base]
    for kk, vv in pairs(b) do if t[kk] == nil then t[kk] = vv end end
  end
  t.id = k
end

function Enemy.spawn(kind, x, y, opt)
  local T = ETYPE[kind]
  opt = opt or {}
  local e = Ent.add({ kind = "enemy", et = T, x = x, y = y, r = T.r, hp = (opt.hp or T.hp), maxhp = (opt.hp or T.hp), hostile = true,
    state = "idle", st = 0, hx = x, hy = y, dir = rnd() * TAU, cd = 0, flash = 0, sc = opt.sc or 1, step = 4.5,
    fly = T.fly, hover = T.hover, dry = not T.swims, group = opt.group, pm = opt.pm or (T.pm and Pal.mk(T.pm)) })
  e.update = Enemy.update
  e.draw = Enemy.draw
  e.light = T.light
  if T.fly then e.z = groundAt(x, y) + (T.hover or 10) end
  if T.ghost then e.z = groundAt(x, y) + (T.hover or 3) end
  return e
end

function Enemy.hurt(e, dmg, sx, sy, kb)
  if e.hp <= 0 or e.inv and e.inv > 0 then return end
  e.hp = e.hp - dmg
  e.flash = 8
  e.inv = 6
  FX.burst(e.x, e.y, e.z + 8, 6, { C_WHITE, C_RED, C_GOLD }, 1.2, 14)
  FX.text(e.x, e.y, e.z + 18, tostring(dmg), C_GOLD)
  Sfx.play("hit")
  if not e.boss then
    local dx, dy = e.x - sx, e.y - sy
    local l = math.sqrt(dx * dx + dy * dy) + 0.001
    local k = (e.et and e.et.heavy) and kb * 0.4 or kb
    e.vx, e.vy = dx / l * k, dy / l * k
    if e.state == "windup" and not (e.et and e.et.heavy) then e.state = "recover" e.st = 10 end
    if e.state == "idle" then e.state = "chase" end
    e.state = e.state == "windup" and "windup" or e.state
    e.hurtT = 10
  end
  if e.onHurt then e:onHurt(dmg) end
  if e.hp <= 0 then Enemy.kill(e) end
end

function Enemy.kill(e)
  e.hp = 0
  e.state = "dead"
  e.st = 0
  e.hostile = false
  Sfx.play("kill")
  FX.burst(e.x, e.y, e.z + 8, 16, { C_WHITE, C_GRAY, C_NIGHT, C_RED }, 1.6, 30)
  local T = e.et
  if T and T.drops then
    local luck = Inv.has("charm") and 1.5 or 1
    for _, dr in ipairs(T.drops) do
      local n = rnd(dr[2], dr[3])
      if dr[1] == "ryo" then n = flr(n * luck) end
      if n > 0 then Drops.spawn(e.x, e.y, e.z + 6, dr[1], n) end
    end
  end
  if T then
    P.kills[T.id] = (P.kills[T.id] or 0) + 1
    Quest.event("kill", T.id)
  end
  if e.onDeath then e:onDeath() end
end

local function faceTo(e, tx, ty) e.dir = math.atan(ty - e.y, tx - e.x) end

local function steer(e, tx, ty, sp)
  local dx, dy = tx - e.x, ty - e.y
  local l = math.sqrt(dx * dx + dy * dy)
  if l < 0.5 then e.vx, e.vy = e.vx * 0.7, e.vy * 0.7 return l end
  local a = math.atan(dy, dx) + (e.avoid or 0)
  e.vx = approach(e.vx, math.cos(a) * sp, 0.15)
  e.vy = approach(e.vy, math.sin(a) * sp, 0.15)
  e.dir = a
  return l
end

function Enemy.update(e)
  local T = e.et
  if e.flash > 0 then e.flash = e.flash - 1 end
  if e.inv and e.inv > 0 then e.inv = e.inv - 1 end
  if e.state == "dead" then
    e.st = e.st + 1
    if e.st > 24 then e.alive = false end
    return
  end
  if T.night and Clock.isDay() and e.t % 60 == 0 then
    FX.burst(e.x, e.y, e.z + 8, 8, { C_WHITE, C_BLUE }, 1, 20)
    e.alive = false
    return
  end
  local p = P
  local dpx, dpy = p.x - e.x, p.y - e.y
  local dp = math.sqrt(dpx * dpx + dpy * dpy)
  local pAlive = p.state ~= "dead"
  local dz = p.z - e.z
  e.st = e.st + 1
  if e.cd > 0 then e.cd = e.cd - 1 end
  if e.hurtT and e.hurtT > 0 then
    e.hurtT = e.hurtT - 1
    e.vx, e.vy = e.vx * 0.85, e.vy * 0.85
  elseif e.state == "idle" then
    if e.st > 80 + rnd(60) or not e.wx then
      e.st = 0
      local a = rnd() * TAU
      e.wx, e.wy = e.hx + math.cos(a) * rnd(8, 32), e.hy + math.sin(a) * rnd(8, 32)
    end
    steer(e, e.wx, e.wy, T.sp * 0.4)
    if pAlive and dp < T.aggro and math.abs(dz) < 40 and not Game.safe then
      e.state = "chase"
      e.st = 0
      if T.pack then
        for _, o in ipairs(ENTS) do
          if o.alive and o.et == T and o.state == "idle" and dist(o.x, o.y, e.x, e.y) < 60 then o.state = "chase" end
        end
      end
    end
  elseif e.state == "chase" then
    local leash = dist(e.x, e.y, e.hx, e.hy)
    if not pAlive or dp > T.aggro * 2.2 or leash > 260 or Game.safe then
      e.state = "home"
    elseif T.ranged and dp < (T.range or 70) and dp > (T.reach > 0 and T.reach * 2 or 20) and e.cd == 0 and math.abs(dz) < 50 then
      e.state = "shoot"
      e.st = 0
      e.vx, e.vy = 0, 0
    elseif T.reach > 0 and dp < T.reach and math.abs(dz) < 12 + (T.tall or 0) and e.cd == 0 then
      e.state = "windup"
      e.st = 0
      e.vx, e.vy = 0, 0
      faceTo(e, p.x, p.y)
      Sfx.play("growl")
    else
      local keep = (T.reach == 0) and 50 or 0
      if dp > keep then steer(e, p.x, p.y, T.sp) else e.vx, e.vy = e.vx * 0.8, e.vy * 0.8 end
      if T.blink and e.st % 120 == 60 and dp > 30 then
        -- kitsune trick: vanish and reappear beside you
        FX.burst(e.x, e.y, e.z + 6, 10, { C_GOLD, C_RED }, 1, 20)
        local a = rnd() * TAU
        e.x, e.y = p.x + math.cos(a) * 22, p.y + math.sin(a) * 22
        Ent.resolve(e)
        e.z = groundAt(e.x, e.y)
        Sfx.play("blink")
      end
    end
  elseif e.state == "home" then
    if steer(e, e.hx, e.hy, T.sp * 0.7) < 6 then e.state = "idle" e.hp = math.min(e.maxhp, e.hp + 1) end
    if pAlive and dp < T.aggro * 0.6 and not Game.safe then e.state = "chase" end
  elseif e.state == "windup" then
    e.vx, e.vy = e.vx * 0.7, e.vy * 0.7
    if e.st >= T.windup then
      e.state = "strike"
      e.st = 0
      Sfx.play("swing")
      if T.lunge then
        local a = e.dir
        e.vx, e.vy = math.cos(a) * 2.6, math.sin(a) * 2.6
      elseif T.charge then
        local a = e.dir
        e.vx, e.vy = math.cos(a) * 2.4, math.sin(a) * 2.4
        e.chargeT = 34
      end
      if T.smash then
        FX.shake(4)
        FX.ring(e.x + math.cos(e.dir) * 12, e.y + math.sin(e.dir) * 12, e.z, C_BROWN)
        Sfx.play("slam")
        local hx, hy = e.x + math.cos(e.dir) * 12, e.y + math.sin(e.dir) * 12
        if dist(hx, hy, p.x, p.y) < 20 and math.abs(dz) < 14 then Player.damage(T.dmg, e.x, e.y, T.id) end
      elseif not T.charge and not T.lunge then
        if dp < T.reach * 1.35 and math.abs(dz) < 12 + (T.tall or 0) then Player.damage(T.dmg, e.x, e.y, T.id) end
      end
    end
  elseif e.state == "strike" then
    if (T.lunge or T.charge) and dp < (e.r + 5) and math.abs(dz) < 10 and not e.struck then
      e.struck = Player.damage(T.dmg, e.x, e.y, T.id) or true
    end
    if T.charge then
      e.chargeT = e.chargeT - 1
      if e.st % 6 == 0 then FX.dust(e.x, e.y, e.z, 2) end
      if e.chargeT <= 0 or e.hitWall then e.state = "recover" e.st = 0 end
    else
      e.vx, e.vy = e.vx * 0.86, e.vy * 0.86
      if e.st > 12 then e.state = "recover" e.st = 0 end
    end
  elseif e.state == "recover" then
    e.vx, e.vy = e.vx * 0.8, e.vy * 0.8
    if e.st > 14 then
      e.state = "chase"
      e.cd = T.cd
      e.struck = nil
      e.st = 0
    end
  elseif e.state == "shoot" then
    faceTo(e, p.x, p.y)
    if e.st == 18 then
      local a = e.dir
      local spd = T.ranged == "fire" and 1.5 or 2.2
      local tz = (p.z + 7 - (e.z + 8)) / math.max(dp, 1) * spd
      Proj.spawn(T.ranged, e.x, e.y, e.z + 8, math.cos(a) * spd, math.sin(a) * spd, tz, false, T.ranged == "web" and 1 or T.dmg)
      Sfx.play("throw")
    end
    if e.st > 34 then e.state = "chase" e.cd = T.cd e.st = 0 end
  end

  -- movement
  if T.ghost then
    e.x, e.y = e.x + e.vx, e.y + e.vy
    e.z = groundAt(e.x, e.y) + (T.hover or 3) + math.sin(e.t / 15) * 2
  else
    local px0, py0 = e.x, e.y
    local hit = Ent.physics(e)
    if T.hop and e.ground and (math.abs(e.vx) + math.abs(e.vy)) > 0.3 and e.t % 24 == 0 then e.vz = 1.4 end
    e.hitWall = hit
    -- simple obstacle avoidance when stuck
    if hit and e.state == "chase" then
      e.avoid = (e.avoidT and e.avoidT > 0) and e.avoid or ((rnd() < 0.5) and 1.1 or -1.1)
      e.avoidT = 40
    end
    if e.avoidT then
      e.avoidT = e.avoidT - 1
      if e.avoidT <= 0 then e.avoid, e.avoidT = 0, nil end
    end
    if T.fly then e.z = e.z + math.sin(e.t / 10) * 0.3 end
  end
end

function Enemy.draw(e)
  local T = e.et
  local frames = T.spr
  local name = frames[1 + (e.t // (T.anim or 10)) % #frames]
  if (e.state == "windup" or e.state == "strike") and T.atk then name = T.atk end
  if math.abs(e.vx) + math.abs(e.vy) < 0.1 and e.state ~= "windup" and not T.anim then name = frames[1] end
  local r = SPR[name]
  if not r then return end
  local flip = false
  if not T.front then
    local _, f = Ent.view(e.dir)
    flip = f
  end
  local pm = e.pm
  if e.flash > 0 then pm = PM_WHITE
  elseif e.state == "windup" and (e.st // 3) % 2 == 0 then pm = PM_RED end
  if e.state == "dead" then
    if (e.st // 2) % 2 == 0 then return end
    pm = PM_WHITE
  end
  if not T.ghost then Ent.shadow(e, (e.r + 1) * e.sc) end
  local z = e.z
  if T.ghost or T.fly then z = z + math.sin(e.t / 12) * 1.5 end
  Render.bill(r, e.x, e.y, z, flip, pm, e.sc)
  Render.setPM(nil)
  -- health bar when hurt
  if e.hp < e.maxhp and e.hp > 0 and not e.boss then
    local sx, sy = proj(e.x, e.y, z)
    local w = 12
    local top = sy - r[4] * e.sc - 4
    rect(sx - w / 2, top, w, 2, C_NIGHT)
    rect(sx - w / 2, top, w * e.hp / e.maxhp, 2, C_RED)
  end
end

-- ---------------------------------------------------------------------------
-- spawning: camps (fixed, respawn), wildlife (day), yokai (night)
-- ---------------------------------------------------------------------------
CAMPS = {}
function Enemy.camp(kind, cx, cy, n, opt)
  CAMPS[#CAMPS + 1] = { kind = kind, x = cx * 8 + 4, y = cy * 8 + 4, n = n or 1, opt = opt or {}, alive = 0, next = 0, members = {} }
end

local WILD = {
  sakura = { "wolf", "boar" }, bamboo = { "wolf", "spider", "boar" }, plains = { "wolf", "boar", "bandit" },
  snow = { "snowwolf", "tengu" }, haunted = { "spider", "wolf" }, coast = { "bandit", "boar" },
  marsh = { "kappa", "spider" }, volcano = { "oni" },
}

function Enemy.director()
  local p = P
  local now = Clock.total
  -- camps
  for _, c in ipairs(CAMPS) do
    local d = dist(c.x, c.y, p.x, p.y)
    local alive = 0
    for _, m in ipairs(c.members) do if m.alive and m.hp > 0 then alive = alive + 1 end end
    c.alive = alive
    if alive == 0 and d < 230 and d > 120 and now >= c.next and not c.done then
      c.members = {}
      for k = 1, c.n do
        local a = k / c.n * TAU
        local e = Enemy.spawn(c.kind, c.x + math.cos(a) * 10, c.y + math.sin(a) * 10, c.opt)
        e.camp = c
        c.members[#c.members + 1] = e
      end
      c.next = now + OBJ_DAY * (c.opt.respawn or 1)
      if c.opt.once then c.done = true end
    end
  end
  if now % 240 ~= 0 or Game.safe then return end
  local count = 0
  for _, e in ipairs(ENTS) do
    if e.alive and e.kind == "enemy" and not e.camp and dist(e.x, e.y, p.x, p.y) < 240 then count = count + 1 end
  end
  local night = not Clock.isDay()
  local limit = night and 5 or 3
  if count >= limit then return end
  -- pick a spot 120-170 units away on dry land, not in a town
  for tries = 1, 6 do
    local a = rnd() * TAU
    local r = rnd(120, 170)
    local x, y = p.x + math.cos(a) * r, p.y + math.sin(a) * r
    local cx, cy = flr(x / 8), flr(y / 8)
    if inmap(cx, cy) then
      local i = cidx(cx, cy)
      if (WF[i] & (F_WATER | F_TOWN | F_NOSPAWN | F_ROOF | F_MODEL)) == 0 and WH[i] >= 0 then
        local biome = REG[WR[i]].biome
        local kind
        if night then
          kind = (rnd() < 0.55) and "yurei" or "onibi"
          if biome == "haunted" and rnd() < 0.3 then kind = "kitsune" end
        else
          if rnd() < 0.5 then return end
          kind = pick(WILD[biome])
        end
        local n = (ETYPE[kind].pack) and rnd(2, 3) or 1
        for k = 1, n do Enemy.spawn(kind, x + k * 6, y + k * 3) end
        return
      end
    end
  end
end

-- ============================================================================
--  43 NPCs - townsfolk who wander, face you, show "!"/"?" quest markers,
--  run shops and inns, and chat (lines vary by region and story progress).
-- ============================================================================
NPC = {}
NPCK = {
  sensei = { spr = "eld_f1", name = "Sensei Hayate" },
  shopkeep = { spr = "vil_f1", pm = { [C_BLUE] = C_WOOD, [C_INDIGO] = C_BROWN } },
  innkeep = { spr = "wom_f1", pm = { [C_PINK] = C_GOLD, [C_WHITE] = C_CREAM } },
  farmer = { spr = "vil_f1", pm = { [C_BLUE] = C_GREEN, [C_INDIGO] = C_DKGRN } },
  villager = { spr = "vil_f1" },
  woman = { spr = "wom_f1" },
  child = { spr = "kid_f1" },
  lady = { spr = "lady_f1", name = "Lady Sayo" },
  captain = { spr = "grd_f1", pm = { [C_RED] = C_INDIGO, [C_GOLD] = C_WHITE }, name = "Captain Ishida" },
  guard = { spr = "grd_f1", name = "Castle Guard" },
  smith = { spr = "vil_f1", pm = { [C_BLUE] = C_NIGHT, [C_INDIGO] = C_GRAY, [C_TAN] = C_GRAY, [C_WOOD] = C_BROWN } },
  teamaster = { spr = "eld_f1", pm = { [C_GRAY] = C_GREEN, [C_WHITE] = C_GRAY } },
  monk = { spr = "eld_f1", pm = { [C_GRAY] = C_GOLD, [C_WHITE] = C_CREAM, [C_BROWN] = C_WOOD } },
  tailor = { spr = "wom_f1", pm = { [C_PINK] = C_BLUE, [C_RED] = C_GOLD } },
  woodcutter = { spr = "vil_f1", pm = { [C_BLUE] = C_DKGRN, [C_INDIGO] = C_BROWN } },
  fisher = { spr = "vil_f1", pm = { [C_BLUE] = C_INDIGO, [C_RED] = C_WHITE } },
  merchant = { spr = "vil_f1", pm = { [C_BLUE] = C_RED, [C_INDIGO] = C_BROWN } },
  tanuki = { spr = "fox1", pm = { [C_WOOD] = C_BROWN, [C_TAN] = C_WOOD, [C_CREAM] = C_TAN }, name = "Ponta the Tanuki" },
}
local VARIANTS = {
  villager = { nil, { [C_BLUE] = C_GREEN, [C_INDIGO] = C_DKGRN }, { [C_BLUE] = C_WOOD, [C_INDIGO] = C_BROWN }, { [C_BLUE] = C_GRAY } },
  woman = { nil, { [C_PINK] = C_BLUE, [C_RED] = C_INDIGO }, { [C_PINK] = C_LIME, [C_RED] = C_GREEN }, { [C_PINK] = C_GOLD } },
}
local NAMES = { "Hiro", "Saki", "Jiro", "Yumi", "Ken", "Rin", "Sota", "Hana", "Daichi", "Emi", "Kaito", "Nao", "Riku", "Aoi" }

-- flavour lines by role, then by region
local LINES = {
  villager = { "Have you tried the onigiri at the inn? Best in the province.", "The nights grow longer since the Treasures vanished.",
    "Keep a torch handy. The dark has teeth.", "I saw a tiny white spirit on a rock pillar. A kodama!",
    "Bandits camp along the roads. Travel by day.", "Climb the pagodas - you can see the whole land from up there." },
  guard = { "Halt! ...Ah, a shinobi. Carry on.", "The Shogun's castle is closed to commoners.", "Oni were sighted near the eastern coast.",
    "We guard the walls. You guard the roads." },
  child = { "Ninja! Ninja! Can you jump on the roofs?", "Mama says yurei only come out at night.", "I want a kite like yours!" },
  woman = { "Sakura petals make lovely dango.", "The tea master in Kyo pays well for wild herbs.", "Rest at an inn and you'll wake refreshed." },
  monk = { "Kneel at a Jizo once a day. He will mend your wounds.", "Spirit shrines test the body. Spirit orbs reward the brave.",
    "Four orbs offered to the Kannon statue in Kyo grant great strength." },
}
local REGIONLINES = {
  ["Mount Fuyu"] = { "Without a fur cloak the mountain wind will freeze you.", "Hot tea or stew keeps the cold away for a while." },
  ["Minato Coast"] = { "Kappa! Offer one a cucumber and it might spare you.", "The bridge to Onigashima is sealed with sacred rope." },
  ["Whispering Bamboo"] = { "Bamboo shoots, boiled, give you strength.", "Spider silk is strong as steel." },
}

function NPC.spawnAll()
  local n = 0
  for _, s in ipairs(NPCSPAWN) do
    n = n + 1
    local K = NPCK[s.kind] or NPCK.villager
    local d = s.data or {}
    local pmt = K.pm
    local v = VARIANTS[s.kind]
    if v and not d.name then pmt = v[1 + n % #v] end
    local e = Ent.add({ kind = "npc", role = s.kind, id = d.id or s.kind, x = s.x, y = s.y, hx = s.x, hy = s.y, r = 3, step = 4.5,
      name = d.name or K.name or NAMES[1 + (n * 7) % #NAMES], data = d, spr = K.spr, pm = pmt and Pal.mk(pmt) or nil,
      dir = math.pi / 2, wander = (s.kind == "villager" or s.kind == "woman" or s.kind == "child" or s.kind == "guard") and 18 or 4,
      dry = true, always = false })
    e.update = NPC.update
    e.draw = NPC.draw
    e.interact = NPC.talk
  end
end

function NPC.find(id)
  for _, e in ipairs(ENTS) do
    if e.alive and e.kind == "npc" and e.id == id then return e end
  end
end

function NPC.update(e)
  local p = P
  local d = dist(e.x, e.y, p.x, p.y)
  if Dialog.active and Dialog.who == e then
    e.vx, e.vy = 0, 0
    e.dir = math.atan(p.y - e.y, p.x - e.x)
  elseif d < 26 then
    e.vx, e.vy = e.vx * 0.7, e.vy * 0.7
    e.dir = math.atan(p.y - e.y, p.x - e.x)
  else
    e.wt = (e.wt or 0) - 1
    if e.wt <= 0 then
      e.wt = rnd(90, 240)
      if rnd() < 0.6 and e.wander > 4 then
        local a = rnd() * TAU
        e.tx, e.ty = e.hx + math.cos(a) * rnd(4, e.wander), e.hy + math.sin(a) * rnd(4, e.wander)
      else
        e.tx = nil
      end
    end
    if e.tx then
      local dx, dy = e.tx - e.x, e.ty - e.y
      local l = math.sqrt(dx * dx + dy * dy)
      if l > 2 then
        e.vx, e.vy = dx / l * 0.35, dy / l * 0.35
        e.dir = math.atan(dy, dx)
      else
        e.tx = nil
        e.vx, e.vy = 0, 0
      end
    else
      e.vx, e.vy = 0, 0
    end
  end
  Ent.physics(e)
end

function NPC.draw(e)
  local r = SPR[e.spr]
  if not r then return end
  local moving = math.abs(e.vx) + math.abs(e.vy) > 0.05
  local _, flip = Ent.view(e.dir)
  local bob = moving and ((e.t // 8) % 2) or 0
  Ent.shadow(e, 4)
  Render.bill(r, e.x, e.y, e.z + bob * 0.8, moving and ((e.t // 8) % 2 == 0) or flip, e.pm)
  Render.setPM(nil)
  -- quest marker
  local mk = Quest.marker(e)
  if mk then
    local mr = SPR[mk]
    local sx, sy = proj(e.x, e.y, e.z)
    local y = sy - r[4] - 10 + math.sin(Frame / 10) * 1.5
    blit(mr, flr(sx - mr[3] / 2), flr(y))
  end
end

function NPC.chatter(e)
  local pool = LINES[e.role] or LINES.villager
  local reg = REG[WR[cidx(clamp(flr(e.x / 8), 0, 239), clamp(flr(e.y / 8), 0, 111))]]
  local extra = reg and REGIONLINES[reg.name]
  if extra and rnd() < 0.5 then pool = extra end
  e.line = ((e.line or rnd(#pool)) % #pool) + 1
  Dialog.say(e.name, pool[e.line], nil, e)
end

function NPC.talk(e)
  Sfx.play("talk")
  if Quest.onTalk(e) then return end
  local d = e.data
  if d.shop then
    Dialog.say(e.name, "Welcome! Take a look.", function() Menu.open("shop", { shop = d.shop, who = e }) end, e)
  elseif d.inn then
    Dialog.ask(e.name, "A warm futon for " .. d.inn .. " ryo? You'll wake at dawn, fully rested.", { "Rest", "No thanks" }, function(c)
      if c == 1 then
        if P.ryo >= d.inn then
          P.ryo = P.ryo - d.inn
          Game.sleep(e)
        else
          Dialog.say(e.name, "Oh dear, you're short on ryo.", nil, e)
        end
      end
    end, e)
  elseif e.role == "tanuki" then
    if P.seeds >= 3 and Inv.size < 16 then
      P.seeds = P.seeds - 3
      Inv.size = math.min(16, Inv.size + 2)
      Sfx.play("upgrade")
      Dialog.say(e.name, "Pon pon! Three kodama seeds! I'll stitch your bag bigger. (Inventory +2 slots)", nil, e)
    else
      Dialog.say(e.name, "Kodama hide atop stone pillars and deep in the woods. Bring me 3 of their seeds and I'll enlarge your bag! (You have " .. P.seeds .. ")", nil, e)
    end
  elseif e.role == "guard" and Quest.state("mq4") ~= "done" and dist(e.x, e.y, POI.bridge.x, POI.bridge.y) < 40 then
    Dialog.say(e.name, "The bridge is sealed by the Shogun's order.", nil, e)
  else
    NPC.chatter(e)
  end
end

-- the lost cat wanders near the bamboo forest until rescued
function NPC.spawnCat()
  if Quest.state("cat") == "done" or Inv.has("cat") then return end
  local c = POI.cat
  local e = Ent.add({ kind = "npc", role = "cat", id = "tama", name = "Tama", x = c.x, y = c.y, hx = c.x, hy = c.y, r = 2, spr = "cat1",
    wander = 14, dir = 0, dry = true })
  e.update = NPC.update
  e.draw = NPC.draw
  e.interact = function(self)
    if Quest.active("cat") then
      self.alive = false
      Inv.add("cat", 1)
      Sfx.play("cat")
      Quest.event("found", "cat")
      Dialog.say("Tama", "Mrrow! (Tama hops into your arms.)")
    else
      Dialog.say("Tama", "Mrrow? The cat looks lost.")
    end
  end
end

-- ============================================================================
--  44 QUESTS - main story (the Three Sacred Treasures) and side quests.
--  QS[id] = { st = "active"|"done", step = n, count = k }
--  Step types: craft, tower, talk, have, kill, boss, find. Events advance
--  steps; turning in "have" steps consumes the items.
-- ============================================================================
Quest = { tracked = "mq1" }
QS = {}

QUESTS = {
  { id = "mq1", main = true, name = "The Way of the Shinobi", giver = "sensei",
    intro = { "Kage, awake at last! Oni and yokai grow bold since the Three Sacred Treasures were stolen.",
      "A shinobi survives alone. Cut bamboo with Z, pull grass with A, then craft a torch (TAB, Light tab)." },
    steps = {
      { t = "craft", item = "torch", text = "Craft a torch (TAB > Light)", hint = "Bamboo: Z on bamboo. Grass: A on tall grass." },
      { t = "tower", n = 1, text = "Climb the Hanamura Pagoda, press A on top", target = "tower1",
        say = { "Good. Now climb the pagoda east of the village and survey the land.", "Push against a wall to climb. Press X while climbing to leap up." } },
      { t = "talk", npc = "sensei", text = "Return to Sensei Hayate",
        say = { "You see the whole Sakura Vale from up there, yes? Then you are ready.",
          "Take my kite. In the air, hold X to glide on the wind.",
          "Go east to Kyo. Lady Sayo at the castle has need of a shinobi." } },
    },
    reward = { ryo = 40, items = { { "shuriken", 10 } }, ability = "kite", text = "Got the Kite Glider! Hold X in mid-air to glide." } },
  { id = "mq2", main = true, name = "Shadow over Kyo", after = { "mq1" }, auto = true,
    steps = {
      { t = "talk", npc = "lady", text = "Meet Lady Sayo at Kyo Castle", target = "castle",
        say = { "Hayate's student. Welcome, Kage.",
          "Shuten-doji, the Oni King, stole the Three Sacred Treasures. Without them the nights lengthen and yokai roam freely.",
          "The Magatama Jewel is in the Spider Lair, west of Takemura. The Yata Mirror is on the summit of Mount Fuyu, held by the Tengu Lord.",
          "And Kusanagi, the Sword, lies in the belly of Orochi, the serpent of the Great Lake.",
          "Recover all three and I will unseal the bridge to Onigashima." } },
    },
    reward = { ryo = 50, text = "Three treasures to find. Check your map (M)." } },
  { id = "jewel", main = true, name = "The Jewel in the Web", after = { "mq2" }, auto = true,
    steps = { { t = "boss", boss = "jorogumo", text = "Defeat Jorogumo in the Spider Lair", target = "lair" } },
    reward = { items = { { "magatama", 1 } }, ability = "djump", text = "The Magatama Jewel! Press X again in mid-air to double jump." } },
  { id = "mirror", main = true, name = "The Mirror on the Peak", after = { "mq2" }, auto = true,
    steps = { { t = "boss", boss = "tengulord", text = "Defeat the Tengu Lord atop Mount Fuyu", target = "summit" } },
    reward = { items = { { "mirror", 1 } }, ability = "mirror", text = "The Yata Mirror! Its light keeps the Yami away." } },
  { id = "sword", main = true, name = "The Sword in the Serpent", after = { "mq2" }, auto = true,
    steps = { { t = "boss", boss = "orochi", text = "Slay Orochi in the Great Lake", target = "lake" } },
    reward = { equip = "kusanagi", text = "Kusanagi, the grass-cutting sword, is yours!" } },
  { id = "mq4", main = true, name = "Onigashima", after = { "jewel", "mirror", "sword" }, auto = true,
    steps = {
      { t = "talk", npc = "lady", text = "Bring the Treasures to Lady Sayo", target = "castle",
        say = { "The Jewel, the Mirror and the Sword... you did it, Kage!",
          "I have lifted the seal on the bridge south of the Kappa Marsh.",
          "Cross to Onigashima and end Shuten-doji's reign. The whole realm is with you." } },
      { t = "boss", boss = "shuten", text = "Defeat Shuten-doji on Onigashima", target = "onigashima" },
    },
    reward = { ryo = 500, finale = true, text = "The Oni King is defeated! Dawn returns to the realm." } },
  -- side quests ---------------------------------------------------------------
  { id = "rice", name = "Rice for the Village", giver = "farmer",
    intro = { "Bandits stole our harvest! Could you gather 5 rice from the paddies east of the village? Press A on the rice plants." },
    steps = { { t = "have", item = "rice", n = 5, text = "Gather 5 rice", target = "paddies" },
      { t = "talk", npc = "farmer", take = { "rice", 5 }, text = "Bring the rice to Farmer Goro", say = { "Wonderful! Here, take some onigiri for the road." } } },
    reward = { ryo = 20, items = { { "onigiri", 3 } } } },
  { id = "cat", name = "Where is Tama?", giver = "mei",
    intro = { "My cat Tama ran off towards the bamboo forest! Please find her!" },
    steps = { { t = "find", what = "cat", text = "Find Tama near the bamboo forest", target = "cat" },
      { t = "talk", npc = "mei", take = { "cat", 1 }, text = "Bring Tama home to Little Mei", say = { "TAMA! Thank you, ninja! Take my lucky charm!" } } },
    reward = { items = { { "charm", 1 } }, text = "Got the Maneki Charm! Foes drop more ryo." } },
  { id = "bounty", name = "Bandit Bounty", giver = "captain", after = { "mq1" },
    intro = { "Bandits plague the roads around Kyo. Defeat six of them and the Shogun's purse is yours." },
    steps = { { t = "kill", kind = "bandit", n = 6, text = "Defeat bandits" },
      { t = "talk", npc = "captain", text = "Report to Captain Ishida", say = { "Six bandits! The roads are safer already. Here is your reward." } } },
    reward = { ryo = 90, items = { { "sarmor", 1 } }, text = "Got Samurai Armor! Equip it from your bag." } },
  { id = "tea", name = "Leaves for Tea", giver = "teamaster",
    intro = { "The finest tea needs wild herbs. Bring me four and I'll brew you something special." },
    steps = { { t = "have", item = "herb", n = 4, text = "Gather 4 wild herbs" },
      { t = "talk", npc = "teamaster", take = { "herb", 4 }, text = "Bring herbs to Tea Master Rikyu", say = { "Splendid herbs. Drink this tea in the cold mountains." } } },
    reward = { ryo = 20, items = { { "tea", 3 } } } },
  { id = "pelts", name = "Warm Pelts", giver = "tailor",
    intro = { "Nobody climbs Mount Fuyu without a fur cloak. Bring me three wolf pelts and I'll sew you one." },
    steps = { { t = "have", item = "pelt", n = 3, text = "Collect 3 wolf pelts" },
      { t = "talk", npc = "tailor", take = { "pelt", 3 }, text = "Bring pelts to Tailor Kiku", say = { "Fine pelts! Here, your cloak. The mountain cold can't touch you now." } } },
    reward = { items = { { "cloak", 1 } }, text = "Got the Fur Cloak! Equip it to resist the cold." } },
  { id = "kappa", name = "Kappa Trouble", giver = "fisher",
    intro = { "Kappa keep stealing my catch! Thin them out - four should do." },
    steps = { { t = "kill", kind = "kappa", n = 4, text = "Defeat 4 kappa" },
      { t = "talk", npc = "fisher", text = "Report to Fisher Isamu", say = { "Ha! The river is mine again. Have some sushi!" } } },
    reward = { ryo = 50, items = { { "sushi", 3 } } } },
  { id = "package", name = "Special Delivery", giver = "merchant", give = { "package", 1 },
    intro = { "Could you carry this package to the innkeeper of Yukimura, up in the mountains? He pays on delivery." },
    steps = { { t = "talk", npc = "inn_yuki", take = { "package", 1 }, text = "Deliver the package to Yukimura's inn", target = "yukimura",
      say = { "My new tea set! All the way from Minato. Here's your fee." } } },
    reward = { ryo = 70 } },
  { id = "silk", name = "Threads of Steel", giver = "woodcutter",
    intro = { "My wife weaves with spider silk. Bring 4 silk from the forest spiders and I'll forge you something sharp." },
    steps = { { t = "have", item = "silk", n = 4, text = "Collect 4 spider silk" },
      { t = "talk", npc = "woodcutter", take = { "silk", 4 }, text = "Bring silk to Woodcutter Taro", say = { "Strong thread! Here, my old katana - it's served me well." } } },
    reward = { items = { { "katana", 1 }, { "shuriken", 10 } } } },
  { id = "spirits", name = "Restless Spirits", giver = "abbot",
    intro = { "Yurei wander the night, unable to pass on. Grant peace to five of them." },
    steps = { { t = "kill", kind = "yurei", n = 5, text = "Calm 5 yurei (night only)" },
      { t = "talk", npc = "abbot", text = "Return to Abbot Genshin", say = { "The spirits rest. Take this orb - the gods noticed your kindness." } } },
    reward = { orbs = 1, ryo = 40 } },
}
QBYID = {}
for _, q in ipairs(QUESTS) do QBYID[q.id] = q end

function Quest.reset()
  QS = {}
  Quest.tracked = "mq1"
end

function Quest.state(id)
  local s = QS[id]
  if not s then return "none" end
  return s.st
end
function Quest.active(id) return QS[id] and QS[id].st == "active" end
function Quest.step(id)
  local s = QS[id]
  if not s or s.st ~= "active" then return nil end
  return QBYID[id].steps[s.step]
end

local function prereqDone(q)
  if not q.after then return true end
  for _, a in ipairs(q.after) do if Quest.state(a) ~= "done" then return false end end
  return true
end

function Quest.start(id, silent)
  local q = QBYID[id]
  if QS[id] then return end
  QS[id] = { st = "active", step = 1, count = 0 }
  if q.give then Drops.give(q.give[1], q.give[2]) end
  if not silent then
    UI.banner("New quest: " .. q.name)
    Sfx.play("quest")
  end
  if q.main or not Quest.tracked or Quest.state(Quest.tracked) ~= "active" then Quest.tracked = id end
  Quest.check(id)
end

local function finish(id)
  local q = QBYID[id]
  local s = QS[id]
  s.st = "done"
  local r = q.reward or {}
  if r.ryo then P.ryo = P.ryo + r.ryo end
  if r.items then for _, it in ipairs(r.items) do Drops.give(it[1], it[2]) end end
  if r.ability then P.has[r.ability] = true end
  if r.orbs then P.orbs = P.orbs + r.orbs end
  if r.equip then
    Inv.add(r.equip, 1)
    P.weapon = r.equip
  end
  Sfx.play("complete")
  UI.banner("Quest complete: " .. q.name, r.text)
  -- unlock automatic follow-ups
  for _, n in ipairs(QUESTS) do
    if n.auto and not QS[n.id] and prereqDone(n) then Quest.start(n.id) end
  end
  if Quest.tracked == id then
    Quest.tracked = nil
    for _, n in ipairs(QUESTS) do
      if Quest.state(n.id) == "active" and (n.main or not Quest.tracked) then Quest.tracked = n.id break end
    end
  end
  if r.finale then Game.finale() end
  Game.autosave()
end

function Quest.advance(id)
  local s = QS[id]
  local q = QBYID[id]
  s.step = s.step + 1
  s.count = 0
  if s.step > #q.steps then
    finish(id)
  else
    Sfx.play("quest")
    local st = q.steps[s.step]
    UI.toast(st.text)
    Quest.check(id)
  end
end

-- re-evaluate passive conditions (have / craft-owned)
function Quest.check(id)
  local s = QS[id]
  if not s or s.st ~= "active" then return end
  local st = QBYID[id].steps[s.step]
  if st.t == "have" and Inv.count(st.item) >= st.n then Quest.advance(id)
  elseif st.t == "craft" and Inv.has(st.item) then Quest.advance(id)
  elseif st.t == "tower" and Quest.towerCount() >= st.n then Quest.advance(id)
  elseif st.t == "boss" and Boss.defeated[st.boss] then Quest.advance(id) end
end

function Quest.event(kind, what)
  for id, s in pairs(QS) do
    if s.st == "active" then
      local st = QBYID[id].steps[s.step]
      if kind == "kill" and st.t == "kill" and st.kind == what then
        s.count = s.count + 1
        UI.toast(st.text .. " " .. s.count .. "/" .. st.n)
        if s.count >= st.n then Quest.advance(id) end
      elseif kind == "found" and st.t == "find" and st.what == what then
        Quest.advance(id)
      elseif kind == "boss" and st.t == "boss" and st.boss == what then
        Quest.advance(id)
      elseif kind == "item" or kind == "craft" or kind == "tower" then
        Quest.check(id)
      end
    end
  end
end

-- talking to an NPC: quest turn-ins, steps and offers. returns true if handled
function Quest.onTalk(e)
  -- active step that targets this NPC
  for _, q in ipairs(QUESTS) do
    local s = QS[q.id]
    if s and s.st == "active" then
      local st = q.steps[s.step]
      if st.t == "talk" and st.npc == e.id then
        if st.take and Inv.count(st.take[1]) < st.take[2] then
          local prev = q.steps[s.step - 1]
          if prev and prev.t == "have" then s.step = s.step - 1 end
          Dialog.say(e.name, "You still need " .. st.take[2] .. " " .. ITEM[st.take[1]].n .. ".", nil, e)
          return true
        end
        if st.take then Inv.take(st.take[1], st.take[2]) end
        Dialog.lines(e.name, st.say or { "Thank you!" }, function() Quest.advance(q.id) end, e)
        return true
      end
    end
  end
  -- giver reminders for active quests
  for _, q in ipairs(QUESTS) do
    local s = QS[q.id]
    if s and s.st == "active" and q.giver == e.id then
      local st = q.steps[s.step]
      if st.say and st.t ~= "talk" then
        Dialog.lines(e.name, st.say, nil, e)
      else
        Dialog.say(e.name, "Remember: " .. st.text .. "." .. (st.hint and (" " .. st.hint) or ""), nil, e)
      end
      return true
    end
  end
  -- offer a new quest
  for _, q in ipairs(QUESTS) do
    if q.giver == e.id and not QS[q.id] and prereqDone(q) and not q.auto then
      Dialog.lines(e.name, q.intro or { "I need help." }, function()
        Dialog.ask(e.name, "Will you help? (" .. q.name .. ")", { "Accept", "Not now" }, function(c)
          if c == 1 then Quest.start(q.id) end
        end, e)
      end, e)
      return true
    end
  end
  return false
end

-- "!" when a quest can be offered, "?" when this NPC is a turn-in target
function Quest.marker(e)
  for _, q in ipairs(QUESTS) do
    local s = QS[q.id]
    if s and s.st == "active" then
      local st = q.steps[s.step]
      if st.t == "talk" and st.npc == e.id then return "question" end
    elseif not s and q.giver == e.id and prereqDone(q) and not q.auto then
      return "exclaim"
    end
  end
  return nil
end

-- world position of the tracked objective (for the compass and map pin)
function Quest.target(id)
  id = id or Quest.tracked
  local st = id and Quest.step(id)
  if not st then return nil end
  if st.t == "talk" then
    local n = NPC.find(st.npc)
    if n then return n.x, n.y end
  end
  if st.t == "tower" then
    for _, t in ipairs(TOWERS) do if not Quest.towersOn[t.id] then return t.x, t.y end end
  end
  if st.target then
    if st.target == "tower1" then return TOWERS[1].x, TOWERS[1].y end
    local p = POI[st.target]
    if p then return p.x, p.y end
  end
  return nil
end

function Quest.text(id)
  local st = Quest.step(id)
  if not st then return nil end
  local s = QS[id]
  local t = st.text
  if st.t == "kill" then t = t .. " (" .. s.count .. "/" .. st.n .. ")" end
  if st.t == "have" then t = t .. " (" .. math.min(Inv.count(st.item), st.n) .. "/" .. st.n .. ")" end
  return t
end

-- ---------------------------------------------------------------------------
-- pagoda towers: survey the region (reveal map) + fast travel point
-- ---------------------------------------------------------------------------
Quest.towersOn = {}
function Quest.towerCount()
  local n = 0
  for _ in pairs(Quest.towersOn) do n = n + 1 end
  return n
end
function Quest.tower(t)
  if Quest.towersOn[t.id] then
    UI.toast(t.name .. ": the view is breathtaking.")
    return
  end
  Quest.towersOn[t.id] = true
  MapUI.reveal(t.x, t.y, 70)
  Sfx.play("tower")
  FX.burst(t.x, t.y, t.top + 8, 30, { C_GOLD, C_WHITE, C_PINK }, 2, 50)
  UI.banner(t.name .. " surveyed!", "Map revealed. Fast travel unlocked here.")
  Quest.event("tower")
  Game.autosave()
end

-- ============================================================================
--  45 CLOCK & SURVIVAL - day/night cycle (DS-style clock), palette tint,
--  hunger, cold, warmth buffs, darkness danger ("the Yami") and weather.
-- ============================================================================
Clock = { total = 0, t = 0.08, day = 1, len = 60 * 60 * 6, rain = 0, rainT = 0, snow = false }
-- phases on the 0..1 dial
DUSK, NIGHT, DAWN = 0.58, 0.72, 0.96

function Clock.isDay() return Clock.t < DUSK + 0.04 or Clock.t > DAWN end
function Clock.isNight() return Clock.t >= NIGHT and Clock.t < DAWN end
function Clock.phase()
  local t = Clock.t
  if t < DUSK then return "day" elseif t < NIGHT then return "dusk" elseif t < DAWN then return "night" end
  return "dawn"
end

-- palette multipliers through the day
local KEYS = {
  { 0.00, 1.00, 1.00, 1.00 },
  { 0.50, 1.00, 1.00, 1.00 },
  { 0.62, 1.05, 0.80, 0.66 },
  { 0.72, 0.50, 0.50, 0.85 },
  { 0.80, 0.36, 0.40, 0.72 },
  { 0.92, 0.36, 0.40, 0.72 },
  { 0.97, 0.90, 0.80, 0.85 },
  { 1.00, 1.00, 1.00, 1.00 },
}
function Clock.tint()
  local t = Clock.t
  for k = 1, #KEYS - 1 do
    local a, b = KEYS[k], KEYS[k + 1]
    if t >= a[1] and t <= b[1] then
      local u = (t - a[1]) / (b[1] - a[1])
      local r, g, bl = lerp(a[2], b[2], u), lerp(a[3], b[3], u), lerp(a[4], b[4], u)
      if Clock.rain > 0 then
        local w = Clock.rain * 0.25
        r, g, bl = r * (1 - w), g * (1 - w), bl * (1 - w * 0.6)
      end
      return r, g, bl
    end
  end
  return 1, 1, 1
end

function Clock.update()
  Clock.total = Clock.total + 1
  Clock.t = Clock.t + 1 / Clock.len
  if Clock.t >= 1 then
    Clock.t = Clock.t - 1
    Clock.day = Clock.day + 1
    UI.banner("Day " .. Clock.day)
    Game.autosave()
  end
  -- weather: occasional rain showers (snow in the north)
  Clock.rainT = Clock.rainT - 1
  if Clock.rainT <= 0 then
    Clock.rainT = rnd(60 * 60, 60 * 150)
    Clock.raining = (rnd() < 0.3)
  end
  Clock.rain = approach(Clock.rain, Clock.raining and 1 or 0, 0.004)
end

-- survival tick for the player
function Clock.survival()
  local p = P
  if p.state == "dead" or Game.safeTime then return end
  -- hunger
  if Clock.total % 300 == 0 then
    p.hunger = math.max(0, p.hunger - 1)
  end
  if p.hunger <= 0 and Clock.total % 240 == 0 then
    Player.damage(1, nil, nil, "starve")
    UI.toast("You are starving!")
  end
  -- warmth buffs and cold
  if p.warm > 0 then p.warm = p.warm - 1 end
  local reg = REG[WR[cidx(clamp(flr(p.x / 8), 0, 239), clamp(flr(p.y / 8), 0, 111))]]
  local cold = reg and reg.biome == "snow" and p.z > 20 and not (p.armor == "cloak") and p.warm <= 0 and not Light.nearFire(p.x, p.y)
  if cold then
    p.cold = p.cold + 1
    if p.cold == 1 then UI.toast("It's freezing! Find warmth.") end
    if p.cold > 240 and Clock.total % 200 == 0 then Player.damage(1, nil, nil, "cold") end
  else
    p.cold = 0
  end
  -- darkness: at night, outside any light, the Yami strikes
  if Clock.isNight() and not P.has.mirror then
    if Light.level(p.x, p.y) <= 0 then
      p.dark = p.dark + 1
      if p.dark == 60 then UI.toast("It's too dark... something is watching.") Sfx.play("whisper") end
      if p.dark > 240 and p.dark % 90 == 0 then
        Player.damage(3, nil, nil, "dark")
        FX.burst(p.x, p.y, p.z + 8, 12, { C_NIGHT, C_INDIGO }, 1.5, 20)
        UI.toast("The Yami claws at you! Light a torch or fire!")
      end
    else
      p.dark = 0
    end
  else
    p.dark = 0
  end
end

-- ---------------------------------------------------------------------------
-- light sources and the DS-style darkness overlay
-- ---------------------------------------------------------------------------
Light = { list = {} }

function Light.collect()
  local L = {}
  local p = P
  -- the player's torch/lantern or the sacred mirror (no player on the title screen)
  if p then
    local pr = 0
    if p.light and ITEM[p.light] then pr = ITEM[p.light].light end
    if p.has.mirror then pr = math.max(pr, 50) end
    if pr > 0 then L[#L + 1] = { p.x, p.y, p.z + 6, pr + math.sin(Clock.total / 6) * 1.5 } end
    L[#L + 1] = { p.x, p.y, p.z, 14 } -- faint night vision
  end
  -- objects with light (lanterns, fires) in visible chunks
  for _, k in ipairs(Render.visChunks or {}) do
    local l = OLIST[k]
    if l then
      for ci in pairs(l) do
        local o = WO[ci]
        if o > 0 then
          local d = OBJ[o]
          if d.light and (o ~= O_TORO or (WF[ci] & F_NOSPAWN) ~= 0 or true) then
            local ox, oy = objPos(ci)
            local fl = (o == O_FIRE) and math.sin(Clock.total / 4 + ci) * 2 or 0
            L[#L + 1] = { ox, oy, math.max(WH[ci], 0) + 6, d.light + fl }
          end
        end
      end
    end
  end
  for _, e in ipairs(ENTS) do
    if e.alive and e.light then L[#L + 1] = { e.x, e.y, e.z + 4, e.light } end
  end
  Light.list = L
  return L
end

function Light.level(x, y)
  for _, l in ipairs(Light.list) do
    if l[4] > 16 then
      local dx, dy = x - l[1], y - l[2]
      if dx * dx + dy * dy < (l[4] * 0.8) ^ 2 then return 1 end
    end
  end
  return 0
end

function Light.nearFire(x, y)
  local cx, cy = flr(x / 8), flr(y / 8)
  for yy = cy - 3, cy + 3 do
    for xx = cx - 3, cx + 3 do
      if inmap(xx, yy) and WO[cidx(xx, yy)] == O_FIRE then return true end
    end
  end
  return false
end

-- per-row spans: everything outside the light ellipses goes black, with
-- dithered rims for a soft edge. a = darkness amount 0..1 (fades in at dusk
-- by darkening every 4th/2nd row first).
function Light.overlay(a)
  if a <= 0 then return end
  local sl = {}
  local sp = Cam.sp * 1.15
  for _, l in ipairs(Light.list) do
    local sx, sy = proj(l[1], l[2], l[3])
    sl[#sl + 1] = { sx, sy, l[4], l[4] * sp }
  end
  local R1, R2 = 0.8, 0.92
  local rowMask = a >= 0.85 and 1 or (a >= 0.5 and 2 or 4)
  local function dark(x0, x1, y)
    if x1 > x0 then rect(x0, y, x1 - x0, 1, C_INK) end
  end
  local spans = {}
  for y = 0, 135 do
    local n = 0
    for k = 1, #sl do
      local s = sl[k]
      local dy = (y - s[2]) / s[4]
      if dy > -1 and dy < 1 then
        local hw = s[3] * math.sqrt(1 - dy * dy)
        n = n + 1
        local sp2 = spans[n]
        if not sp2 then sp2 = {} spans[n] = sp2 end
        sp2[1], sp2[2], sp2[3], sp2[4] = s[1] - hw, s[1] + hw, s[1], hw
      end
    end
    for k = n + 1, #spans do spans[k] = nil end
    if y % rowMask == 0 then
      if n == 0 then
        dark(0, 240, y)
      else
        table.sort(spans, function(p, q) return p[1] < q[1] end)
        local x = 0
        for k = 1, n do
          local s = spans[k]
          local l = flr(s[1])
          if l > x then dark(x, math.min(l, 240), y) end
          local r = ceil(s[2])
          if r > x then x = r end
        end
        if x < 240 then dark(x, 240, y) end
        -- soft rims
        if a >= 0.85 then
          for k = 1, n do
            local s = spans[k]
            local cx, hw = s[3], s[4]
            local rim = hw * (1 - R1) + 1
            for side = -1, 1, 2 do
              local xa = side < 0 and flr(cx - hw) or ceil(cx + hw * R1)
              local xb = side < 0 and flr(cx - hw * R1) or ceil(cx + hw)
              for xx = math.max(0, xa), math.min(239, xb) do
                local d = math.abs(xx - cx) / hw
                local covered = false
                for j = 1, n do
                  if j ~= k then
                    local o = spans[j]
                    if math.abs(xx - o[3]) < o[4] * R1 then covered = true break end
                  end
                end
                if not covered then
                  if d > R2 then
                    if (xx + y) % 2 == 0 then pix(xx, y, C_INK) end
                  elseif d > R1 then
                    if (xx + y) % 4 == 0 and y % 2 == 0 then pix(xx, y, C_INK) end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

-- ============================================================================
--  46 FX - particles, slash arcs, floating text, screen shake, hit-stop.
--  Particles live in world space and are projected each frame (no depth).
-- ============================================================================
FX = { parts = {}, texts = {}, shakeA = 0, stop = 0, sprites = {} }
PM_WHITE = nil

function FX.init()
  PM_WHITE = {}
  for i = 0, 15 do PM_WHITE[i] = C_WHITE end
  PM_RED = {}
  for i = 0, 15 do PM_RED[i] = C_RED end
  PM_RED[0] = 0
  PM_GOLD = Pal.mk { [C_WHITE] = C_GOLD, [C_CREAM] = C_GOLD }
end

function FX.shake(a) if a > FX.shakeA then FX.shakeA = a end end
function FX.hitstop(n) if n > FX.stop then FX.stop = n end end

function FX.add(x, y, z, vx, vy, vz, life, c, g, size)
  local ps = FX.parts
  if #ps > 240 then return end
  ps[#ps + 1] = { x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, life = life, max = life, c = c, g = g or 0.08, s = size or 1 }
end

function FX.dust(x, y, z, n)
  for i = 1, n do
    local a = rnd() * TAU
    FX.add(x, y, z + 1, math.cos(a) * 0.5, math.sin(a) * 0.5, rndf(0.2, 0.6), rnd(10, 18), (i % 2 == 0) and C_CREAM or C_TAN, 0.03)
  end
end

function FX.burst(x, y, z, n, cols, sp, life)
  for i = 1, n do
    local a = rnd() * TAU
    local s = rndf(0.4, sp or 1.4)
    FX.add(x, y, z, math.cos(a) * s, math.sin(a) * s, rndf(0.5, 1.8), rnd(math.min(10, life or 26), life or 26), cols[rnd(#cols)], 0.12)
  end
end

function FX.ring(x, y, z, c)
  for i = 0, 15 do
    local a = i / 16 * TAU
    FX.add(x, y, z + 1, math.cos(a) * 1.3, math.sin(a) * 1.3, 0.1, 14, c, 0)
  end
end

function FX.ripple(x, y, z)
  FX.sprites[#FX.sprites + 1] = { spr = "ripple", x = x, y = y, z = z, life = 24, max = 24 }
end

function FX.slash(x, y, z, combo)
  local _, f = Ent.view(P.dir)
  FX.sprites[#FX.sprites + 1] = { spr = "slash", x = x, y = y, z = z - 6, life = 7, max = 7, flip = f,
    sc = combo == 3 and 2 or 1, pm = combo == 3 and PM_GOLD or nil }
end

function FX.sprite(name, x, y, z, life, sc, flip, pm)
  FX.sprites[#FX.sprites + 1] = { spr = name, x = x, y = y, z = z, life = life, max = life, sc = sc, flip = flip, pm = pm }
end

function FX.text(x, y, z, str, c)
  local t = FX.texts
  if #t > 12 then table.remove(t, 1) end
  t[#t + 1] = { x = x, y = y, z = z, s = str, c = c or C_WHITE, life = 50 }
end

function FX.update()
  if FX.shakeA > 0 then
    FX.shakeA = FX.shakeA * 0.85
    if FX.shakeA < 0.3 then FX.shakeA = 0 end
  end
  local ps = FX.parts
  local j = 0
  for i = 1, #ps do
    local p = ps[i]
    p.life = p.life - 1
    if p.life > 0 then
      p.x, p.y, p.z = p.x + p.vx, p.y + p.vy, p.z + p.vz
      p.vz = p.vz - p.g
      p.vx, p.vy = p.vx * 0.96, p.vy * 0.96
      j = j + 1
      ps[j] = p
    end
  end
  for i = j + 1, #ps do ps[i] = nil end
  local ss = FX.sprites
  j = 0
  for i = 1, #ss do
    local s = ss[i]
    s.life = s.life - 1
    if s.life > 0 then j = j + 1 ss[j] = s end
  end
  for i = j + 1, #ss do ss[i] = nil end
  local ts = FX.texts
  j = 0
  for i = 1, #ts do
    local t = ts[i]
    t.life = t.life - 1
    t.z = t.z + 0.35
    if t.life > 0 then j = j + 1 ts[j] = t end
  end
  for i = j + 1, #ts do ts[i] = nil end
end

-- depth-tested sprite effects (drawn with the world)
function FX.drawWorld()
  for _, s in ipairs(FX.sprites) do
    local r = SPR[s.spr]
    if r then Render.bill(r, s.x, s.y, s.z, s.flip, s.pm, s.sc, 4) end
  end
  Render.setPM(nil)
end

-- particles and texts (screen space, over the world)
function FX.drawTop()
  for _, p in ipairs(FX.parts) do
    local sx, sy = proj(p.x, p.y, p.z)
    if p.s > 1 or p.life > p.max * 0.6 then
      rect(sx, sy, p.s + 1, p.s + 1, p.c)
    else
      pix(sx, sy, p.c)
    end
  end
  for _, t in ipairs(FX.texts) do
    local sx, sy = proj(t.x, t.y, t.z)
    local w = print(t.s, 0, -20, 0, false, 1, true)
    print(t.s, sx - w / 2 + 1, sy + 1, C_NIGHT, false, 1, true)
    print(t.s, sx - w / 2, sy, t.c, false, 1, true)
  end
end

-- ============================================================================
--  47 PROJECTILES & DROPS
-- ============================================================================
Proj = {}
local PSPR = { shuriken = "shuriken", arrow = "arrow", feather = "feather", fire = "fireball", web = "web" }

-- friendly = thrown by the player (hits enemies), else hits the player
function Proj.spawn(kind, x, y, z, vx, vy, vz, friendly, dmg)
  local e = Ent.add({ kind = "proj", pk = kind, x = x, y = y, z = z, vx = vx, vy = vy, vz = vz or 0, r = 2,
    friendly = friendly, dmg = dmg or 1, life = 80, always = true })
  e.update = Proj.update
  e.draw = Proj.draw
  return e
end

function Proj.update(e)
  e.life = e.life - 1
  e.x, e.y, e.z = e.x + e.vx, e.y + e.vy, e.z + e.vz
  if e.pk == "fire" then e.vz = e.vz - 0.02 end
  if e.life <= 0 then e.alive = false return end
  local g = groundAt(e.x, e.y)
  if g > e.z then
    e.alive = false
    FX.burst(e.x, e.y, e.z, 4, { C_GRAY, C_WHITE }, 0.8, 10)
    Sfx.play("clank")
    return
  end
  if e.friendly then
    for _, t in ipairs(ENTS) do
      if t.alive and t.hostile and t.hp and t.hp > 0 and dist(e.x, e.y, t.x, t.y) < (t.r or 3) + 4 and math.abs(e.z - (t.z + (t.hz or 6))) < 12 + (t.tall or 0) then
        Enemy.hurt(t, e.dmg, e.x - e.vx * 3, e.y - e.vy * 3, 1.2)
        e.alive = false
        return
      end
    end
  else
    local p = P
    if p.state ~= "dead" and dist(e.x, e.y, p.x, p.y) < 6 and math.abs(e.z - (p.z + 7)) < 10 then
      Player.damage(e.dmg, e.x - e.vx * 3, e.y - e.vy * 3, e.pk)
      if e.pk == "web" then P.webbed = 90 end
      e.alive = false
    end
  end
end

function Proj.draw(e)
  local r = SPR[PSPR[e.pk]]
  if not r then return end
  local flip = (e.t // 3) % 2 == 0
  Render.bill(r, e.x, e.y, e.z - r[4] / 2, flip, nil, 1, 3)
end

-- ---------------------------------------------------------------------------
-- dropped items: pop out, then fly to the player
-- ---------------------------------------------------------------------------
Drops = {}
function Drops.spawn(x, y, z, id, n)
  local a = rnd() * TAU
  local e = Ent.add({ kind = "drop", item = id, n = n, x = x, y = y, z = z, vx = math.cos(a) * 0.7, vy = math.sin(a) * 0.7,
    vz = 1.6, r = 2, step = 6, life = 60 * 120 })
  e.update = Drops.update
  e.draw = Drops.draw
  return e
end

-- straight to inventory with a small fly-up icon
function Drops.give(id, n, x, y, z)
  if id == "ryo" then
    P.ryo = P.ryo + n
    FX.text(x or P.x, y or P.y, (z or P.z) + 14, "+" .. n .. " ryo", C_GOLD)
    Sfx.play("coin")
    return
  end
  local left = Inv.add(id, n)
  local got = n - left
  if got > 0 then
    FX.text(x or P.x, y or P.y, (z or P.z) + 14, "+" .. got .. " " .. ITEM[id].n, C_WHITE)
    Quest.event("item", id)
  end
  if left > 0 then
    UI.toast("Inventory full!")
    Drops.spawn(P.x, P.y, P.z + 4, id, left)
  end
end

function Drops.update(e)
  e.life = e.life - 1
  if e.life <= 0 then e.alive = false return end
  local p = P
  local d = dist(e.x, e.y, p.x, p.y)
  if e.t > 24 and d < 28 and p.state ~= "dead" then
    local full = e.item ~= "ryo" and Inv.free() == 0 and Inv.count(e.item) % (ITEM[e.item].s) == 0
    if not full then
      local k = 0.12 + (28 - d) * 0.01
      e.x = e.x + (p.x - e.x) * k
      e.y = e.y + (p.y - e.y) * k
      e.z = e.z + (p.z + 4 - e.z) * k
      if d < 5 then
        e.alive = false
        Drops.give(e.item, e.n, e.x, e.y, e.z)
        if e.item ~= "ryo" then Sfx.play("pick") end
      end
      return
    end
  end
  e.vx, e.vy = e.vx * 0.92, e.vy * 0.92
  Ent.physics(e)
end

function Drops.draw(e)
  local r = e.item == "ryo" and SPR.ryo or SPR["i_" .. e.item]
  if not r then return end
  local bob = math.sin(e.t / 8) * 1.5
  if e.life < 300 and (e.t // 4) % 2 == 0 then return end
  Ent.shadow(e, 3)
  Render.bill(r, e.x, e.y, e.z + 2 + bob, false, nil, 1, 3)
end

-- ============================================================================
--  48 BOSSES & SHRINES
--  Jorogumo (spider queen), Tengu Lord, Orochi (lake serpent heads) and
--  Shuten-doji (Oni King). Each spawns when you enter its arena and resets if
--  you leave or fall. Spirit shrines hold trials that award spirit orbs.
-- ============================================================================
Boss = { defeated = {}, cur = nil }

local BOSSDEF = {
  jorogumo = { name = "Jorogumo, Spider Queen", hp = 40, spr = { "spi1", "spi2" }, sc = 3, r = 10,
    pm = { [C_INDIGO] = C_NIGHT, [C_NIGHT] = C_INDIGO, [C_RED] = C_PINK }, poi = "lair" },
  tengulord = { name = "Sojobo, Tengu Lord", hp = 46, spr = { "ten1", "ten2" }, sc = 2, r = 8, fly = true, hover = 20,
    pm = { [C_INDIGO] = C_NIGHT, [C_RED] = C_GOLD, [C_NIGHT] = C_INDIGO }, poi = "summit" },
  orochi = { name = "Yamata no Orochi", hp = 64, spr = { "oro1", "oro2" }, sc = 2, r = 8, poi = "lake" },
  shuten = { name = "Shuten-doji, Oni King", hp = 90, spr = { "oni1", "oni1" }, atk = "oni_atk", sc = 2, r = 12,
    pm = { [C_RED] = C_INDIGO, [C_WHITE] = C_GOLD, [C_GOLD] = C_RED }, poi = "onigashima" },
}
for id, b in pairs(BOSSDEF) do b.id = id end

local function bossQuestReady(id)
  if id == "shuten" then
    local s = QS.mq4
    return s and s.st == "active" and s.step >= 2
  end
  return Quest.state("mq2") == "done"
end

function Boss.update()
  local p = P
  -- the sealed bridge to Onigashima
  local br = POI.bridge
  if br and not bossQuestReady("shuten") and Quest.state("mq4") ~= "done" then
    local d = dist(p.x, p.y, br.x + 12, br.y + 12)
    if d < 14 then
      local dx, dy = p.x - (br.x + 12), p.y - (br.y + 12)
      local l = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      p.x, p.y = br.x + 12 + dx / l * 14, br.y + 12 + dy / l * 14
      if Frame % 90 == 0 then UI.toast("A sacred seal blocks the bridge.") end
    end
  end
  local b = Boss.cur
  if b then
    if not b.alive or b.hp <= 0 and b.state == "gone" then Boss.cur = nil return end
    local def = b.def
    local a = POI[def.poi]
    if p.state == "dead" or dist(p.x, p.y, a.x, a.y) > 210 then
      -- reset the fight
      for _, e in ipairs(ENTS) do if e.minion or e.bossPart then e.alive = false end end
      b.alive = false
      Boss.cur = nil
      Music.region()
    end
    return
  end
  for id, def in pairs(BOSSDEF) do
    if not Boss.defeated[id] and bossQuestReady(id) then
      local a = POI[def.poi]
      if a and dist(p.x, p.y, a.x, a.y) < 64 and p.state ~= "dead" then
        Boss.spawn(id)
        return
      end
    end
  end
end

function Boss.spawn(id)
  local def = BOSSDEF[id]
  local a = POI[def.poi]
  local e = Ent.add({ kind = "enemy", boss = true, def = def, name = def.name, x = a.x, y = a.y - 24, r = def.r, hp = def.hp, maxhp = def.hp,
    hostile = true, sc = def.sc, state = "intro", st = 0, dir = math.pi / 2, cd = 60, flash = 0, step = 8, dry = true,
    pm = def.pm and Pal.mk(def.pm) or nil, always = true, tall = 14, hz = 14, fly = def.fly, hover = def.hover })
  e.update = Boss["u_" .. id] or Boss.u_generic
  e.draw = Boss.draw
  e.onDeath = Boss.onDeath
  if id == "orochi" then
    e.x, e.y = a.x, a.y
    e.hidden = true
    e.r = 6
  end
  Boss.cur = e
  Music.play("boss")
  UI.banner(def.name)
  FX.shake(5)
  Sfx.play("roar")
  return e
end

function Boss.onDeath(e)
  local def = e.def
  Boss.defeated[def.id] = true
  Boss.cur = nil
  for _, m in ipairs(ENTS) do if m.minion or m.bossPart then m.alive = false end end
  FX.shake(8)
  for k = 1, 4 do FX.burst(e.x, e.y, e.z + 10 + k * 4, 16, { C_GOLD, C_WHITE, C_RED, C_PINK }, 2.4, 50) end
  Sfx.play("victory")
  Quest.event("boss", def.id)
  Music.region()
  Game.autosave()
end

local function shootAt(e, kind, spread, n, spd, dmg)
  local p = P
  local a0 = math.atan(p.y - e.y, p.x - e.x)
  for k = 1, n do
    local a = a0 + (k - (n + 1) / 2) * spread
    local d = dist(e.x, e.y, p.x, p.y)
    local vz = (p.z + 7 - (e.z + 14)) / math.max(d, 1) * spd
    Proj.spawn(kind, e.x + math.cos(a) * 8, e.y + math.sin(a) * 8, e.z + 14, math.cos(a) * spd, math.sin(a) * spd, vz, false, dmg)
  end
  Sfx.play("throw")
end

local function minion(kind, x, y)
  local m = Enemy.spawn(kind, x, y)
  m.minion = true
  m.always = true
  m.state = "chase"
  return m
end

local function common(e)
  if e.flash > 0 then e.flash = e.flash - 1 end
  if e.inv and e.inv > 0 then e.inv = e.inv - 1 end
  if e.state == "dead" then
    e.st = e.st + 1
    if e.st % 6 == 0 then FX.burst(e.x + rnd(-10, 10), e.y + rnd(-6, 6), e.z + rnd(4, 24), 8, { C_GOLD, C_WHITE, C_RED }, 1.5, 24) end
    if e.st > 70 then e.alive = false end
    return true
  end
  e.st = e.st + 1
  if e.cd > 0 then e.cd = e.cd - 1 end
  if e.state == "intro" then
    if e.st > 50 then e.state = "idle" e.st = 0 end
    return true
  end
  return false
end

local function contact(e, dmg, rad)
  local p = P
  if dist(e.x, e.y, p.x, p.y) < (rad or e.r + 4) and math.abs(p.z - e.z) < 18 then Player.damage(dmg, e.x, e.y, "boss") end
end

-- Jorogumo: leaps, web fans, spiderlings
function Boss.u_jorogumo(e)
  if common(e) then return end
  local p = P
  local enraged = e.hp < e.maxhp / 2
  if e.state == "idle" then
    e.dir = math.atan(p.y - e.y, p.x - e.x)
    local sp = enraged and 0.75 or 0.5
    e.vx, e.vy = math.cos(e.dir) * sp, math.sin(e.dir) * sp
    if e.cd == 0 then
      local r = rnd()
      e.st = 0
      if r < 0.4 then e.state = "leapW" Sfx.play("growl")
      elseif r < 0.8 then e.state = "web"
      else e.state = "summon" end
    end
    contact(e, 3)
  elseif e.state == "leapW" then
    e.vx, e.vy = 0, 0
    if e.st > 24 then
      e.state = "leap"
      e.st = 0
      local d = dist(e.x, e.y, p.x, p.y)
      e.vx, e.vy = (p.x - e.x) / 40, (p.y - e.y) / 40
      e.vz = 4
    end
  elseif e.state == "leap" then
    if e.ground and e.st > 4 then
      FX.shake(5)
      FX.ring(e.x, e.y, e.z, C_GRAY)
      Sfx.play("slam")
      contact(e, 4, 24)
      e.state = "idle"
      e.cd = enraged and 50 or 80
      e.vx, e.vy = 0, 0
    end
  elseif e.state == "web" then
    e.vx, e.vy = 0, 0
    if e.st == 20 or (enraged and e.st == 40) then shootAt(e, "web", 0.3, 5, 1.8, 1) end
    if e.st > 50 then e.state = "idle" e.cd = 70 end
  elseif e.state == "summon" then
    if e.st == 20 then
      minion("spider", e.x + 16, e.y)
      minion("spider", e.x - 16, e.y)
      Sfx.play("growl")
    end
    if e.st > 40 then e.state = "idle" e.cd = 90 end
  end
  Ent.physics(e)
end

-- Tengu Lord: hovers, feather volleys, dives, gusts
function Boss.u_tengulord(e)
  if common(e) then return end
  local p = P
  local a = POI.summit
  local g = groundAt(e.x, e.y)
  if e.state == "idle" then
    local ang = e.t / 90
    local tx, ty = a.x + math.cos(ang) * 40, a.y + math.sin(ang) * 26
    e.x, e.y = e.x + (tx - e.x) * 0.03, e.y + (ty - e.y) * 0.03
    e.z = e.z + ((g + 22) - e.z) * 0.05
    e.dir = math.atan(p.y - e.y, p.x - e.x)
    if e.cd == 0 then
      local r = rnd()
      e.st = 0
      if r < 0.45 then e.state = "volley" elseif r < 0.8 then e.state = "diveW" else e.state = "gust" end
      if e.hp < e.maxhp / 2 and not e.summoned then e.summoned = true e.state = "summon" end
    end
  elseif e.state == "volley" then
    if e.st % 22 == 10 then shootAt(e, "feather", 0.25, 3, 2.4, 2) end
    if e.st > 70 then e.state = "idle" e.cd = 60 end
  elseif e.state == "diveW" then
    e.flash = (e.st // 3) % 2 == 0 and 2 or 0
    if e.st > 26 then
      e.state = "dive"
      e.st = 0
      e.tx, e.ty = p.x, p.y
    end
  elseif e.state == "dive" then
    e.x, e.y = e.x + (e.tx - e.x) * 0.12, e.y + (e.ty - e.y) * 0.12
    e.z = e.z + ((g + 4) - e.z) * 0.15
    contact(e, 3, 14)
    if e.st > 24 then e.state = "idle" e.cd = 50 end
  elseif e.state == "gust" then
    if e.st > 20 and e.st < 70 then
      local dx, dy = p.x - e.x, p.y - e.y
      local l = math.max(1, math.sqrt(dx * dx + dy * dy))
      if l < 90 then
        p.x, p.y = p.x + dx / l * 0.9, p.y + dy / l * 0.9
        Ent.resolve(p)
        if e.st % 4 == 0 then FX.add(p.x - dx / l * 10, p.y - dy / l * 10, p.z + rnd(2, 14), dx / l * 2, dy / l * 2, 0, 16, C_WHITE, 0) end
      end
    end
    if e.st > 80 then e.state = "idle" e.cd = 60 end
  elseif e.state == "summon" then
    if e.st == 20 then minion("tengu", e.x + 20, e.y) minion("tengu", e.x - 20, e.y) Sfx.play("growl") end
    if e.st > 40 then e.state = "idle" e.cd = 60 end
  end
end

-- Orochi: heads surface from the lake around the island, bite or spit fire
function Boss.u_orochi(e)
  if common(e) then return end
  local p = P
  local a = POI.lake
  if e.state == "idle" then
    e.hidden = true
    e.hostile = false
    if e.st > 40 then
      -- surface at a water spot near the player
      for tries = 1, 12 do
        local ang = rnd() * TAU
        local r = rnd(18, 34)
        local x, y = p.x + math.cos(ang) * r, p.y + math.sin(ang) * r
        if isWaterAt(x, y) and dist(x, y, a.x, a.y) < 120 then
          e.x, e.y = x, y
          e.z = -3
          e.state = "rise"
          e.st = 0
          e.hidden = false
          e.hostile = true
          FX.burst(x, y, -2, 16, { C_WHITE, C_BLUE }, 1.6, 30)
          Sfx.play("splash")
          break
        end
      end
    end
  elseif e.state == "rise" then
    e.dir = math.atan(p.y - e.y, p.x - e.x)
    if e.st == 30 then
      if rnd() < 0.5 or dist(e.x, e.y, p.x, p.y) > 30 then shootAt(e, "fire", 0.35, 3, 1.6, 2)
      else e.state = "bite" e.st = 0 Sfx.play("growl") end
    end
    if e.st > 90 then
      e.state = "idle"
      e.st = 0
      FX.burst(e.x, e.y, -2, 12, { C_WHITE, C_BLUE }, 1.4, 24)
    end
  elseif e.state == "bite" then
    if e.st == 16 then
      local d = dist(e.x, e.y, p.x, p.y)
      if d < 30 then
        local nx, ny = (p.x - e.x) / d, (p.y - e.y) / d
        FX.burst(e.x + nx * 16, e.y + ny * 16, e.z + 10, 8, { C_RED, C_WHITE }, 1, 14)
        if d < 26 and math.abs(p.z - e.z) < 20 then Player.damage(3, e.x, e.y, "boss") end
      end
      Sfx.play("swing")
    end
    if e.st > 40 then e.state = "rise" e.st = 31 end
  end
end

-- Shuten-doji: smashes, fire rings, charges, summons oni
function Boss.u_shuten(e)
  if common(e) then return end
  local p = P
  local rage = e.hp < e.maxhp / 3
  if e.state == "idle" then
    e.dir = math.atan(p.y - e.y, p.x - e.x)
    local sp = rage and 0.7 or 0.45
    e.vx, e.vy = math.cos(e.dir) * sp, math.sin(e.dir) * sp
    if e.cd == 0 then
      local d = dist(e.x, e.y, p.x, p.y)
      e.st = 0
      local r = rnd()
      if d < 30 then e.state = "smashW"
      elseif r < 0.4 then e.state = "fire"
      elseif r < 0.8 then e.state = "chargeW"
      else e.state = "smashW" end
      if e.hp < e.maxhp / 2 and not e.summoned then e.summoned = true e.state = "summon" end
    end
    contact(e, 3)
  elseif e.state == "smashW" then
    e.vx, e.vy = 0, 0
    e.flash = (e.st // 3) % 2 == 0 and 2 or 0
    if e.st > (rage and 22 or 32) then
      e.state = "smash"
      e.st = 0
      local hx, hy = e.x + math.cos(e.dir) * 20, e.y + math.sin(e.dir) * 20
      FX.shake(6)
      FX.ring(hx, hy, e.z, C_RED)
      FX.burst(hx, hy, e.z, 20, { C_BROWN, C_GRAY, C_RED }, 2, 30)
      Sfx.play("slam")
      if dist(hx, hy, p.x, p.y) < 28 and math.abs(p.z - e.z) < 14 then Player.damage(5, e.x, e.y, "boss") end
    end
  elseif e.state == "smash" then
    if e.st > 24 then e.state = "idle" e.cd = rage and 30 or 50 end
  elseif e.state == "fire" then
    e.vx, e.vy = 0, 0
    if e.st == 20 or (rage and e.st == 45) then
      for k = 0, 11 do
        local a = k / 12 * TAU + e.st
        Proj.spawn("fire", e.x, e.y, e.z + 12, math.cos(a) * 1.4, math.sin(a) * 1.4, 0, false, 2)
      end
      Sfx.play("fire")
    end
    if e.st > 60 then e.state = "idle" e.cd = 50 end
  elseif e.state == "chargeW" then
    e.vx, e.vy = 0, 0
    e.dir = math.atan(p.y - e.y, p.x - e.x)
    e.flash = (e.st // 3) % 2 == 0 and 2 or 0
    if e.st > 26 then e.state = "charge" e.st = 0 e.vx, e.vy = math.cos(e.dir) * 2.6, math.sin(e.dir) * 2.6 Sfx.play("roar") end
  elseif e.state == "charge" then
    contact(e, 4, 16)
    if e.st % 5 == 0 then FX.dust(e.x, e.y, e.z, 3) end
    if e.st > 40 or e.hitWall then e.state = "idle" e.cd = 40 e.vx, e.vy = 0, 0 FX.shake(3) end
  elseif e.state == "summon" then
    e.vx, e.vy = 0, 0
    if e.st == 20 then minion("oni", e.x + 24, e.y) minion("oni", e.x - 24, e.y) Sfx.play("roar") end
    if e.st > 40 then e.state = "idle" e.cd = 60 end
  end
  local hit = Ent.physics(e)
  e.hitWall = hit
end

function Boss.draw(e)
  if e.hidden then return end
  local def = e.def
  local frames = def.spr
  local name = frames[1 + (e.t // 10) % #frames]
  if def.atk and (e.state == "smashW" or e.state == "smash" or e.state == "chargeW") then name = def.atk end
  if def.id == "orochi" and e.state == "bite" then name = "oro2" end
  local r = SPR[name]
  local _, flip = Ent.view(e.dir)
  local pm = e.pm
  if e.flash > 0 then pm = PM_WHITE end
  if e.state == "dead" and (e.st // 3) % 2 == 0 then pm = PM_WHITE end
  if e.state == "intro" and (e.st // 4) % 2 == 0 then pm = PM_RED end
  local z = e.z
  if def.id == "orochi" then
    local rise = e.state == "rise" and math.min(1, e.st / 20) or (e.state == "bite" and 1 or 0)
    z = -3 - (1 - rise) * 30
    FX.add(e.x + rnd(-6, 6), e.y + rnd(-4, 4), -2, 0, 0, 0.2, 10, C_WHITE, 0)
  else
    Ent.shadow(e, e.r)
  end
  Render.bill(r, e.x, e.y, z, flip, pm, e.sc)
  Render.setPM(nil)
end

-- ---------------------------------------------------------------------------
-- spirit shrines
-- ---------------------------------------------------------------------------
Shrine = { done = {}, trial = nil }
local TRIALFOES = { "bandit", "wolf", "bandit", "tengu", "kappa", "ronin", "snowwolf", "kappa" }

function Shrine.find(i)
  local cx, cy = (i - 1) % 240, (i - 1) // 240
  for _, s in ipairs(SHRINES) do
    if math.abs(s.cx - cx) <= 1 and math.abs(s.cy - cy) <= 1 then return s end
  end
end

function Shrine.interact(i)
  local s = Shrine.find(i)
  if not s then return end
  -- shrines are also rest points: heal and save
  P.spawnX, P.spawnY = s.x, s.y + 16
  if Shrine.done[s.id] then
    Player.heal(P.maxhp)
    Sfx.play("heal")
    Game.autosave()
    Dialog.say(s.name, "The shrine is at peace. You feel renewed. (Healed, game saved)")
    return
  end
  if s.trial == "combat" then
    if Shrine.trial then
      Dialog.say(s.name, "Defeat the spirits of the trial!")
      return
    end
    Dialog.ask(s.name, "A Trial of Strength. Defeat the shadows summoned here to earn a Spirit Orb.", { "Begin", "Later" }, function(c)
      if c ~= 1 then return end
      local kind = TRIALFOES[s.id] or "bandit"
      Shrine.trial = { s = s, foes = {} }
      for k = 1, 3 + (s.id % 2) do
        local a = k / 4 * TAU
        local e = Enemy.spawn(kind, s.x + math.cos(a) * 26, s.y + 18 + math.sin(a) * 18, { pm = Pal.mk({ [C_RED] = C_INDIGO, [C_BROWN] = C_NIGHT, [C_WOOD] = C_INDIGO, [C_GRAY] = C_INDIGO }) })
        e.state = "chase"
        e.always = true
        e.minion = true
        table.insert(Shrine.trial.foes, e)
      end
      Music.play("boss")
      Sfx.play("roar")
    end)
  else
    Dialog.say(s.name, "A Trial of Agility. Climb the stone pillars and claim the Spirit Orb at the top.")
  end
end

function Shrine.update()
  local t = Shrine.trial
  if t then
    local alive = 0
    for _, e in ipairs(t.foes) do if e.alive and e.hp > 0 then alive = alive + 1 end end
    if alive == 0 then
      Shrine.trial = nil
      Shrine.complete(t.s)
      Music.region()
    elseif dist(P.x, P.y, t.s.x, t.s.y) > 160 or P.state == "dead" then
      for _, e in ipairs(t.foes) do e.alive = false end
      Shrine.trial = nil
      UI.toast("The trial fades...")
      Music.region()
    end
  end
  -- spire trials: touch the orb on the highest pillar
  for _, s in ipairs(SHRINES) do
    if s.top and not Shrine.done[s.id] then
      local ox, oy, oz = s.top[1] * 8 + 4, s.top[2] * 8 + 4, s.top[3]
      if dist(P.x, P.y, ox, oy) < 8 and math.abs(P.z - oz) < 6 then
        Shrine.complete(s)
      end
    end
  end
end

function Shrine.complete(s)
  Shrine.done[s.id] = true
  P.orbs = P.orbs + 1
  Sfx.play("upgrade")
  FX.burst(P.x, P.y, P.z + 10, 24, { C_WHITE, C_BLUE, C_GOLD }, 2, 40)
  UI.banner("Spirit Orb obtained! (" .. P.orbs .. ")", "Offer 4 orbs at the Kannon statue in Kyo.")
  Game.autosave()
end

function Shrine.drawOrbs()
  for _, s in ipairs(SHRINES) do
    if s.top and not Shrine.done[s.id] then
      local ox, oy, oz = s.top[1] * 8 + 4, s.top[2] * 8 + 4, s.top[3]
      if dist(ox, oy, Cam.x, Cam.y) < 300 then
        Render.bill(SPR.orb, ox, oy, oz + 3 + math.sin(Frame / 12) * 2, false, nil, 1, 2)
      end
    end
  end
end

-- Kannon statue: trade 4 orbs for a heart or stamina
function Shrine.statue()
  if P.orbs < 4 then
    Dialog.say("Kannon Statue", "The goddess of mercy waits. Offer 4 Spirit Orbs for her blessing. (You have " .. P.orbs .. ")")
    return
  end
  Dialog.ask("Kannon Statue", "Offer 4 Spirit Orbs. Which blessing do you seek?", { "Heart container", "Stamina vessel" }, function(c)
    if c == 1 and P.maxhp < 48 then
      P.orbs = P.orbs - 4
      P.maxhp = P.maxhp + 4
      P.hp = P.maxhp
      UI.banner("Heart container! Max hearts " .. (P.maxhp // 4))
    elseif c == 2 and P.maxstam < 200 then
      P.orbs = P.orbs - 4
      P.maxstam = P.maxstam + 25
      P.stam = P.maxstam
      UI.banner("Stamina vessel! Stamina " .. P.maxstam)
    else
      return
    end
    Sfx.play("upgrade")
    Game.autosave()
  end)
end

-- ============================================================================
--  50 UI - dialog box, toasts, banners and the in-game HUD (drawn on VRAM
--  bank 1 so the day/night tint of bank 0 never touches it).
--  Layout (Don't Starve x BotW): hearts top-left with the tracked quest
--  under them; day clock + hunger badge + ryo top-right; hotbar + equipment
--  bottom-centre; crafting tabs on the left edge; stamina wheel by the ninja.
-- ============================================================================
UI = { toasts = {}, bannerT = 0, regionT = 0 }
Dialog = { active = false, pages = {}, page = 1, chars = 0 }

function textw(s, small) return print(s, 0, -40, 0, false, 1, small) end

-- wrap to a pixel width using real glyph widths
function wrap(s, w, small)
  local lines, line = {}, ""
  for word in s:gmatch("%S+") do
    local test = line == "" and word or (line .. " " .. word)
    if textw(test, small) > w and line ~= "" then
      lines[#lines + 1] = line
      line = word
    else
      line = test
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

-- shadowed text
function tprint(s, x, y, c, small, sh)
  print(s, x + 1, y + 1, sh or C_NIGHT, false, 1, small)
  return print(s, x, y, c or C_WHITE, false, 1, small)
end

-- framed panel
function panel(x, y, w, h, bg)
  rect(x, y, w, h, bg or C_NIGHT)
  rectb(x, y, w, h, C_TAN)
  pix(x, y, 0) pix(x + w - 1, y, 0) pix(x, y + h - 1, 0) pix(x + w - 1, y + h - 1, 0)
end

-- ---------------------------------------------------------------------------
-- toasts & banners
-- ---------------------------------------------------------------------------
function UI.toast(s)
  local t = UI.toasts
  if t[#t] and t[#t].s == s then t[#t].life = 150 return end
  t[#t + 1] = { s = s, life = 150 }
  if #t > 3 then table.remove(t, 1) end
end
function UI.banner(s, sub)
  UI.bannerS, UI.bannerSub, UI.bannerT = s, sub, 200
end

-- ---------------------------------------------------------------------------
-- dialog
-- ---------------------------------------------------------------------------
function Dialog.lines(name, list, onDone, who)
  Dialog.active = true
  Dialog.name = name
  Dialog.pages = {}
  -- the box shows 4 lines: longer texts continue on further pages
  for _, s in ipairs(list) do
    local ls = wrap(s, 220)
    for k = 1, math.max(1, #ls), 4 do
      Dialog.pages[#Dialog.pages + 1] = table.concat(ls, " ", k, math.min(k + 3, #ls))
    end
  end
  Dialog.page = 1
  Dialog.chars = 0
  Dialog.onDone = onDone
  Dialog.opts = nil
  Dialog.who = who
end
function Dialog.say(name, s, onDone, who) Dialog.lines(name, { s }, onDone, who) end
function Dialog.ask(name, s, opts, onChoice, who)
  Dialog.lines(name, { s }, nil, who)
  Dialog.opts = opts
  Dialog.sel = 1
  Dialog.onChoice = onChoice
end

function Dialog.update()
  if not Dialog.active then return end
  local text = Dialog.pages[Dialog.page]
  local full = Dialog.chars >= #text
  Dialog.chars = Dialog.chars + 1.5
  if Frame % 4 == 0 and not full then Sfx.play("blip") end
  local adv = In.p.atk or In.p.use or In.p.ok or In.p.jump
  if Dialog.opts and full and Dialog.page == #Dialog.pages then
    if In.p.up then Dialog.sel = (Dialog.sel - 2) % #Dialog.opts + 1 Sfx.play("menu") end
    if In.p.down then Dialog.sel = Dialog.sel % #Dialog.opts + 1 Sfx.play("menu") end
    if In.p.atk or In.p.use or In.p.ok then
      local f, c = Dialog.onChoice, Dialog.sel
      Dialog.active = false
      Sfx.play("select")
      if f then f(c) end
    elseif In.p.jump then
      local f = Dialog.onChoice
      Dialog.active = false
      if f then f(#Dialog.opts) end
    end
    return
  end
  if adv then
    if not full then
      Dialog.chars = #text
    elseif Dialog.page < #Dialog.pages then
      Dialog.page = Dialog.page + 1
      Dialog.chars = 0
    else
      Dialog.active = false
      local f = Dialog.onDone
      Dialog.onDone = nil
      if f then f() end
    end
  end
end

function Dialog.draw()
  if not Dialog.active then return end
  local x, y, w, h = 4, 92, 232, 42
  panel(x, y, w, h)
  local text = Dialog.pages[Dialog.page]
  local shown = text:sub(1, flr(Dialog.chars))
  local lines = wrap(shown, w - 12)
  for i, l in ipairs(lines) do
    if i <= 4 then print(l, x + 6, y + 6 + (i - 1) * 8, C_WHITE) end
  end
  -- name tag
  if Dialog.name then
    local nw = textw(Dialog.name) + 8
    panel(x + 4, y - 9, nw, 11, C_RED)
    print(Dialog.name, x + 8, y - 7, C_WHITE)
  end
  if Dialog.opts and Dialog.chars >= #text and Dialog.page == #Dialog.pages then
    local ow = 0
    for _, o in ipairs(Dialog.opts) do ow = math.max(ow, textw(o)) end
    local oh = #Dialog.opts * 9 + 4
    panel(236 - ow - 18, y - oh - 2, ow + 16, oh)
    for i, o in ipairs(Dialog.opts) do
      local yy = y - oh + 1 + (i - 1) * 9
      if i == Dialog.sel then print(">", 236 - ow - 14, yy, C_GOLD) end
      print(o, 236 - ow - 8, yy, i == Dialog.sel and C_GOLD or C_WHITE)
    end
  elseif Dialog.chars >= #text and (Frame // 15) % 2 == 0 then
    tri(x + w - 10, y + h - 8, x + w - 4, y + h - 8, x + w - 7, y + h - 4, C_GOLD)
  end
end

-- ---------------------------------------------------------------------------
-- HUD pieces
-- ---------------------------------------------------------------------------
local function drawHearts(x, y)
  local p = P
  local n = p.maxhp // 4
  for i = 0, n - 1 do
    local hx = x + (i % 10) * 8
    local hy = y + (i // 10) * 8
    local q = clamp(p.hp - i * 4, 0, 4)
    blit(SPR.heart0, hx, hy)
    if q > 0 then
      clip(hx, hy, q == 4 and 8 or (q * 2 + 1), 8)
      blit(SPR.heart, hx, hy)
      clip()
    end
  end
  -- low health pulse
  if p.hp <= 4 and (Frame // 10) % 2 == 0 then
    local hx = x + ((p.hp - 1) // 4 % 10) * 8
    rectb(hx - 1, y - 1, 9, 9, C_RED)
  end
  return y + ((n - 1) // 10 + 1) * 8
end

local function drawClock(cx, cy, r)
  -- DS dial: day gold, dusk red, night indigo
  circ(cx, cy, r + 1, C_NIGHT)
  local segs = 24
  for k = 0, segs - 1 do
    local t0 = k / segs
    local col = (t0 < DUSK and C_GOLD) or (t0 < NIGHT and C_RED) or (t0 < DAWN and C_INDIGO) or C_PINK
    local a0, a1 = t0 * TAU - math.pi / 2, (k + 1) / segs * TAU - math.pi / 2
    tri(cx, cy, cx + math.cos(a0) * r, cy + math.sin(a0) * r, cx + math.cos(a1) * r, cy + math.sin(a1) * r, col)
  end
  circ(cx, cy, r - 4, C_NIGHT)
  circb(cx, cy, r + 1, C_TAN)
  local a = Clock.t * TAU - math.pi / 2
  line(cx, cy, cx + math.cos(a) * (r + 1), cy + math.sin(a) * (r + 1), C_WHITE)
  circ(cx, cy, 1, C_WHITE)
  local s = tostring(Clock.day)
  local w = textw(s, true)
  print(s, cx - w / 2 + 1, cy - 2, C_WHITE, false, 1, true)
end

local function drawBadge(cx, cy, r, frac, col, icon, label)
  circ(cx, cy, r + 1, C_NIGHT)
  circ(cx, cy, r, C_INDIGO)
  local fill = clamp(frac, 0, 1)
  local top = flr(cy + r - fill * 2 * r)
  clip(cx - r, top, 2 * r + 1, 2 * r + 2)
  circ(cx, cy, r, col)
  clip()
  circb(cx, cy, r + 1, C_TAN)
  if icon then blit(icon, cx - 4, cy - 4) end
  if label then
    local w = textw(label, true)
    print(label, cx - w / 2 + 1, cy + r + 3, C_NIGHT, false, 1, true)
    print(label, cx - w / 2, cy + r + 2, C_WHITE, false, 1, true)
  end
end

local function drawStamina()
  local p = P
  if p.stam >= p.maxstam and not p.exhausted then
    UI.stamShow = math.max(0, (UI.stamShow or 0) - 1)
    if UI.stamShow <= 0 then return end
  else
    UI.stamShow = 40
  end
  local sx, sy = proj(p.x, p.y, p.z)
  local cx, cy = flr(sx + 12), flr(sy - 22)
  local vessels = math.ceil(p.maxstam / 100)
  local frac = p.stam / p.maxstam
  local r = 6
  circ(cx, cy, r + 1, C_NIGHT)
  local col = p.exhausted and ((Frame // 6) % 2 == 0 and C_RED or C_GOLD) or C_LIME
  local n = 20
  local fillN = flr(frac * n + 0.5)
  for k = 0, n - 1 do
    local a0, a1 = k / n * TAU - math.pi / 2, (k + 1) / n * TAU - math.pi / 2
    tri(cx, cy, cx + math.cos(a0) * r, cy + math.sin(a0) * r, cx + math.cos(a1) * r, cy + math.sin(a1) * r, k < fillN and col or C_DKGRN)
  end
  circ(cx, cy, 2, C_NIGHT)
end

local function slot(x, y, s, sel, num)
  rect(x, y, 12, 12, sel and C_TAN or C_NIGHT)
  rectb(x, y, 12, 12, sel and C_GOLD or C_INDIGO)
  if s then
    local r = SPR[s.id == "ryo" and "ryo" or ("i_" .. s.id)]
    if r then blit(r, x + 2, y + 2) end
    if s.n > 1 then
      local t = tostring(s.n)
      local w = textw(t, true)
      print(t, x + 11 - w, y + 7, C_NIGHT, false, 1, true)
      print(t, x + 10 - w, y + 6, C_WHITE, false, 1, true)
    end
  end
end
UI.slot = slot

local function drawHotbar()
  local n = Inv.size
  local w = n * 12 + 4 + 3 * 12
  local x0 = flr((240 - w) / 2)
  local y = 123
  rect(x0 - 2, y - 2, w + 4, 15, C_NIGHT)
  for i = 1, n do slot(x0 + (i - 1) * 12, y, Inv.slots[i], false, i) end
  local ex = x0 + n * 12 + 4
  local eq = { P.weapon, P.armor, P.light }
  for k = 1, 3 do
    slot(ex + (k - 1) * 12, y, eq[k] and { id = eq[k], n = 1 } or nil, false)
    if not eq[k] then
      local lab = ({ "W", "A", "L" })[k]
      print(lab, ex + (k - 1) * 12 + 4, y + 3, C_INDIGO, false, 1, true)
    end
  end
  -- light fuel bar
  if P.light and P.lightFuel and ITEM[P.light].fuel < 99999 then
    local f = P.lightFuel / ITEM[P.light].fuel
    rect(ex + 24, y + 12, flr(12 * f), 1, C_GOLD)
  end
end

local function drawCraftTabs()
  local icons = { "tab_tools", "tab_light", "tab_surv", "tab_combat", "tab_dress" }
  for k, ic in ipairs(icons) do
    local y = 34 + (k - 1) * 12
    rect(0, y, 11, 11, C_NIGHT)
    rectb(-1, y, 12, 11, C_INDIGO)
    blit(SPR[ic], 1, y + 1)
  end
  print("TAB", 0, 96, C_GRAY, false, 1, true)
end

local function drawObjective()
  local tx, ty = Quest.target()
  if not tx then return end
  local tz = groundAt(tx, ty)
  local sx, sy = proj(tx, ty, tz)
  local onScreen = sx > 8 and sx < 232 and sy > 30 and sy < 118
  if onScreen then
    local y = sy - 24 + math.sin(Frame / 8) * 2
    if dist(tx, ty, P.x, P.y) > 20 then blit(SPR.pin, flr(sx - 4), flr(y)) end
  else
    -- arrow at the screen edge, kept clear of the HUD corners and hotbar
    local cx, cy = 120, 78
    local dx, dy = sx - cx, sy - cy
    local l = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx / l, dy / l
    local t = math.min(96 / math.max(math.abs(dx), 0.01), 32 / math.max(math.abs(dy), 0.01))
    local ax, ay = cx + dx * t, cy + dy * t
    local px, py = -dy, dx
    local c = (Frame // 8) % 2 == 0 and C_GOLD or C_RED
    tri(ax + dx * 6, ay + dy * 6, ax + px * 4, ay + py * 4, ax - px * 4, ay - py * 4, C_NIGHT)
    tri(ax + dx * 5, ay + dy * 5, ax + px * 3, ay + py * 3, ax - px * 3, ay - py * 3, c)
    local d = flr(dist(tx, ty, P.x, P.y) / 8)
    local s = d .. "m"
    local w = textw(s, true)
    tprint(s, ax - dx * 9 - w / 2, ay - dy * 9 - 2, C_WHITE, true)
  end
end

local function drawPrompt()
  if Dialog.active or Menu.cur then return end
  local kind, tgt = Player.findInteract()
  local label, x, y, z
  if kind == "ent" then
    label = tgt.prompt or (tgt.kind == "npc" and ("Talk: " .. tgt.name) or "Use")
    x, y, z = tgt.x, tgt.y, tgt.z + 22
  elseif kind == "obj" then
    local d = OBJ[WO[tgt]]
    local verbs = { chest = "Open", sign = "Read", kodama = "Take seed", shrine = "Pray", fire = "Cook", pot = "Cook", logs = "Rekindle",
      statue = "Offer orbs", jizo = "Bow" }
    label = (d.talk and verbs[d.talk] or "Pick up") .. ": " .. (d.name or "")
    x, y = objPos(tgt)
    z = math.max(WH[tgt], 0) + 16
  elseif kind == "tower" then
    label = "Survey the land"
    x, y, z = tgt.x, tgt.y, tgt.top + 20
  else
    -- harvesting hint
    local i = Player.frontObject(13)
    if i then
      local d = OBJ[WO[i]]
      if d.tool and d.name then
        local verb = d.tool == "axe" and "Chop" or (d.tool == "pick" and "Mine" or "Cut")
        local sx, sy = proj(P.x, P.y, P.z)
        local s = verb .. " " .. d.name
        local w = textw(s, true) + 12
        rect(sx - w / 2, sy + 4, w, 9, C_NIGHT)
        blit(SPR.key_z, flr(sx - w / 2), flr(sy + 4))
        print(s, sx - w / 2 + 10, sy + 6, C_WHITE, false, 1, true)
      end
    end
    return
  end
  local sx, sy = proj(x, y, z)
  local w = textw(label, true) + 12
  local bx = clamp(flr(sx - w / 2), 1, 239 - w)
  local by = clamp(flr(sy - 6), 14, 112)
  rect(bx, by, w, 9, C_NIGHT)
  blit(SPR.key_a, bx, by)
  print(label, bx + 10, by + 2, C_WHITE, false, 1, true)
end

function UI.drawHUD()
  local p = P
  local y = drawHearts(2, 2)
  -- tracked quest
  local qt = Quest.tracked and Quest.text(Quest.tracked)
  if qt then
    local q = QBYID[Quest.tracked]
    local col = q.main and C_GOLD or C_WHITE
    tprint(Menu.fit((q.main and "* " or "- ") .. qt, 166, true), 2, y + 2, col, true)
  end
  -- top right: clock, hunger, ryo
  drawClock(226, 13, 11)
  drawBadge(203, 12, 8, p.hunger / 100, (p.hunger < 25) and ((Frame // 10) % 2 == 0 and C_RED or C_GOLD) or C_GOLD, SPR.bowl, tostring(flr(p.hunger)))
  local rs = tostring(p.ryo)
  local rw = textw(rs, true)
  blit(SPR.ryo, 230 - rw - 10, 29)
  tprint(rs, 230 - rw, 31, C_GOLD, true)
  if p.orbs > 0 then
    blit(SPR.orbi, 230 - rw - 30, 29)
    tprint(tostring(p.orbs), 230 - rw - 20, 31, C_BLUE, true)
  end
  -- status icons
  local sxx = 182
  if p.cold > 0 then tprint("COLD", sxx - 6, 4, (Frame // 10) % 2 == 0 and C_BLUE or C_WHITE, true) end
  if p.dark > 60 then tprint("DARK", sxx - 6, 12, C_RED, true) end
  if p.warm > 0 then tprint("WARM", sxx - 6, 20, C_GOLD, true) end
  drawCraftTabs()
  drawHotbar()
  drawStamina()
  drawObjective()
  drawPrompt()
  -- boss bar
  local b = Boss.cur
  if b and b.alive and not b.hidden or (b and b.def and b.def.id == "orochi" and b.alive) then
    local w = 120
    local x = 60
    rect(x - 1, 18, w + 2, 6, C_NIGHT)
    rect(x, 19, flr(w * math.max(0, b.hp) / b.maxhp), 4, C_RED)
    rectb(x - 1, 18, w + 2, 6, C_GOLD)
    local nw = textw(b.def.name, true)
    tprint(b.def.name, 120 - nw / 2, 26, C_WHITE, true)
  end
  -- toasts
  local ty = 113
  for i = #UI.toasts, 1, -1 do
    local t = UI.toasts[i]
    t.life = t.life - 1
    if t.life > 0 then
      local s = Menu.fit(t.s, 216, true)
      local w = textw(s, true)
      rect(14, ty - 1, w + 4, 8, C_NIGHT)
      print(s, 16, ty, C_CREAM, false, 1, true)
      ty = ty - 9
    else
      table.remove(UI.toasts, i)
    end
  end
  -- banner
  if UI.bannerT > 0 then
    UI.bannerT = UI.bannerT - 1
    local a = math.min(1, UI.bannerT / 20, (200 - UI.bannerT) / 10)
    if a > 0.3 then
      local small = textw(UI.bannerS) > 216
      local w = textw(UI.bannerS, small)
      local bw = math.min(236, math.max(w, UI.bannerSub and textw(UI.bannerSub, true) or 0) + 16)
      local h = UI.bannerSub and 20 or 13
      panel(120 - bw / 2, 38, bw, h, C_NIGHT)
      print(UI.bannerS, 120 - w / 2, small and 42 or 41, C_GOLD, false, 1, small)
      if UI.bannerSub then
        local sw = textw(UI.bannerSub, true)
        print(UI.bannerSub, 120 - sw / 2, 50, C_WHITE, false, 1, true)
      end
    end
  end
  -- region name
  if UI.regionT > 0 then
    UI.regionT = UI.regionT - 1
    if UI.regionT < 150 then
      local s = UI.regionS
      local w = textw(s) * 1
      local x = 120 - w / 2
      local y = 64
      if (UI.regionT > 10) or (Frame % 2 == 0) then
        print(s, x + 1, y + 1, C_NIGHT)
        print(s, x, y, C_WHITE)
        line(x - 10, y + 9, x + w + 10, y + 9, C_GOLD)
      end
    end
  end
end

function UI.region(name)
  UI.regionS = name
  UI.regionT = 170
end

-- hotkey use of a hotbar slot
function UI.useSlot(k)
  local s = Inv.slots[k]
  if s then Menu.useItem(k) end
end

-- ============================================================================
--  51 MENUS - pause menu (Items / Craft / Map / Quests / System), cooking,
--  shops, world map with fog of war and pagoda fast travel.
-- ============================================================================
Menu = { cur = nil, tab = 1, sel = 1, ctab = 1, csel = 1 }
MapUI = { seen = {} }
local TABN = { "Items", "Craft", "Map", "Quests", "System" }

function Menu.open(kind, opt)
  Menu.cur = kind
  Menu.opt = opt or {}
  Menu.sel = 1
  Menu.sub = nil
  if kind == "pause" then Menu.tab = Menu.opt.tab or Menu.tab end
  if kind == "cook" then Menu.pick = {} end
  if kind == "shop" then Menu.buy = true end
  Sfx.play("open")
end
function Menu.close()
  Menu.cur = nil
  Sfx.play("close")
end

-- ---------------------------------------------------------------------------
-- using items
-- ---------------------------------------------------------------------------
function Menu.useItem(k)
  local s = Inv.slots[k]
  if not s then return end
  local it = ITEM[s.id]
  local p = P
  if it.k == "food" then
    if it.hun then p.hunger = math.min(100, p.hunger + it.hun) end
    if it.hp then
      if it.hp > 0 then Player.heal(it.hp) else Player.damage(-it.hp, nil, nil, "food") UI.toast("Ugh... that was bad.") end
    end
    if it.stam then
      p.stam = math.min(p.maxstam, p.stam + it.stam)
      if p.stam > 0 then p.exhausted = false end
    end
    if it.warm then p.warm = math.max(p.warm, it.warm) UI.toast("You feel warm inside.") end
    Inv.take(s.id, 1)
    Sfx.play("eat")
    FX.text(p.x, p.y, p.z + 18, "Yum!", C_GOLD)
  elseif it.k == "weapon" then
    p.weapon = s.id
    UI.toast("Equipped " .. it.n)
    Sfx.play("equip")
  elseif it.k == "armor" then
    p.armor = (p.armor == s.id) and nil or s.id
    UI.toast(p.armor and ("Wearing " .. it.n) or "Unequipped")
    Sfx.play("equip")
  elseif it.k == "light" then
    if p.light == s.id then
      p.light = nil
      UI.toast("Light put away")
    else
      p.light = s.id
      p.lightFuel = it.fuel
      if s.id == "torch" then Inv.take("torch", 1) end
      UI.toast("Lit the " .. it.n)
    end
    Sfx.play("fire")
  elseif it.k == "place" then
    local o = it.obj == "fire" and O_FIRE or O_POT
    if World.place(o) then Inv.take(s.id, 1) end
  elseif it.k == "bed" then
    if Clock.isNight() or Clock.t > DUSK then
      if Game.safeToSleep() then Game.sleep() else UI.toast("Too dangerous to sleep here!") end
    else
      UI.toast("You can only sleep at dusk or night.")
    end
  elseif it.k == "tool" then
    UI.toast(it.d)
  else
    UI.toast(it.n .. ": " .. it.d)
  end
end

local function dropItem(k)
  local s = Inv.slots[k]
  if not s or ITEM[s.id].key then return end
  Inv.slots[k] = nil
  local e = Drops.spawn(P.x + math.cos(P.dir) * 8, P.y + math.sin(P.dir) * 8, P.z + 6, s.id, s.n)
  e.t = -60
  if P.weapon == s.id then P.weapon = "bokken" end
  if P.armor == s.id then P.armor = nil end
end

-- ---------------------------------------------------------------------------
-- update
-- ---------------------------------------------------------------------------
local function nav(n, cols)
  cols = cols or 1
  local s = Menu.sel
  if In.p.up then s = s - cols end
  if In.p.down then s = s + cols end
  if cols > 1 then
    if In.p.left then s = s - 1 end
    if In.p.right then s = s + 1 end
  end
  if s ~= Menu.sel then Sfx.play("menu") end
  Menu.sel = clamp(s, 1, math.max(1, n))
end

local function recipesIn(tab)
  local l = {}
  for _, r in ipairs(RECIPES) do if r.tab == TABS[tab] then l[#l + 1] = r end end
  return l
end

local function cookables(pot)
  local l = {}
  for i = 1, Inv.size do
    local s = Inv.slots[i]
    if s and ITEM[s.id].k == "food" then
      if pot or ITEM[s.id].cook then
        local dup = false
        for _, x in ipairs(l) do if x == s.id then dup = true end end
        if not dup then l[#l + 1] = s.id end
      end
    end
  end
  return l
end

local function potResult(pick)
  local have = {}
  for _, id in ipairs(pick) do have[id] = (have[id] or 0) + 1 end
  for _, r in ipairs(POT) do
    local ok = true
    local n = 0
    for _, nd in ipairs(r.need) do
      if (have[nd[1]] or 0) ~= nd[2] then ok = false end
      n = n + nd[2]
    end
    if ok and n == #pick then return r.out end
  end
  return nil
end

function Menu.update()
  local k = Menu.cur
  if In.p.menu and k == "pause" then Menu.close() return end
  if k == "pause" then
    if not Menu.sub then
      if In.p.left and Menu.tab ~= 1 or In.p.rotl then Menu.tab = (Menu.tab - 2) % 5 + 1 Menu.sel = 1 Sfx.play("menu") return end
      if In.p.right and Menu.tab ~= 1 or In.p.rotr then Menu.tab = Menu.tab % 5 + 1 Menu.sel = 1 Sfx.play("menu") return end
    end
    if In.p.jump then
      if Menu.sub then Menu.sub = nil Sfx.play("close") else Menu.close() end
      return
    end
    local t = Menu.tab
    if t == 1 then
      if In.p.left and Menu.sel % 4 == 1 then Menu.tab = 5 Menu.sel = 1 Sfx.play("menu") return end
      if In.p.right and Menu.sel % 4 == 0 then Menu.tab = 2 Menu.sel = 1 Sfx.play("menu") return end
      nav(Inv.size, 4)
      if In.p.atk or In.p.ok then Menu.useItem(Menu.sel) end
      if In.p.use then dropItem(Menu.sel) Sfx.play("place") end
    elseif t == 2 then
      local list = recipesIn(Menu.ctab)
      if In.p.throw then Menu.ctab = Menu.ctab % #TABS + 1 Menu.sel = 1 Sfx.play("menu") end
      nav(#list)
      local r = list[Menu.sel]
      if r and (In.p.atk or In.p.ok) then
        if Craft.make(r) then
          Sfx.play("craft")
          UI.toast("Crafted " .. ITEM[r.out].n .. (r.n > 1 and (" x" .. r.n) or ""))
          Quest.event("craft", r.out)
        else
          Sfx.play("error")
          UI.toast("Missing ingredients")
        end
      end
    elseif t == 3 then
      local on = {}
      for _, tw in ipairs(TOWERS) do if Quest.towersOn[tw.id] then on[#on + 1] = tw end end
      nav(#on)
      local tw = on[Menu.sel]
      if tw and (In.p.atk or In.p.ok) then
        if Boss.cur or Shrine.trial then
          UI.toast("Can't travel during a battle!")
        else
          Menu.close()
          Game.travel(tw)
        end
      end
    elseif t == 4 then
      local list = Menu.questList()
      nav(#list)
      if list[Menu.sel] and (In.p.atk or In.p.ok) and Quest.state(list[Menu.sel].id) == "active" then
        Quest.tracked = list[Menu.sel].id
        Sfx.play("select")
      end
    elseif t == 5 then
      nav(5)
      if In.p.atk or In.p.ok then
        if Menu.sel == 1 then
          Game.save()
          UI.toast("Game saved")
          Sfx.play("select")
        elseif Menu.sel == 2 then
          Menu.sub = "help"
        elseif Menu.sel == 3 then
          Audio.setLevels((Audio.music + 3) % 4, Audio.sfx)
          Sfx.play("select")
        elseif Menu.sel == 4 then
          Audio.setLevels(Audio.music, (Audio.sfx + 3) % 4)
          Sfx.play("select")
        elseif Menu.sel == 5 then
          Game.save()
          Menu.close()
          Game.toTitle()
        end
      end
    end
  elseif k == "cook" then
    if In.p.jump or In.p.menu then Menu.close() return end
    local pot = Menu.opt.pot
    local list = cookables(pot)
    nav(#list + (pot and 1 or 0))
    if In.p.atk or In.p.ok then
      if pot then
        if Menu.sel == #list + 1 then
          local out = potResult(Menu.pick)
          if out then
            for _, id in ipairs(Menu.pick) do Inv.take(id, 1) end
            Drops.give(out, 1)
            Sfx.play("craft")
            UI.toast("Cooked " .. ITEM[out].n .. "!")
          else
            Sfx.play("error")
            UI.toast("That combination makes nothing...")
          end
          Menu.pick = {}
        else
          local id = list[Menu.sel]
          if id and #Menu.pick < 3 then
            local used = 0
            for _, x in ipairs(Menu.pick) do if x == id then used = used + 1 end end
            if Inv.count(id) > used then Menu.pick[#Menu.pick + 1] = id Sfx.play("menu") end
          end
        end
      else
        local id = list[Menu.sel]
        if id then
          Inv.take(id, 1)
          Drops.give(ITEM[id].cook, 1)
          Sfx.play("craft")
        end
      end
    end
    if In.p.use and pot then Menu.pick = {} end
  elseif k == "shop" then
    if In.p.jump or In.p.menu then Menu.close() return end
    if In.p.left or In.p.right then Menu.buy = not Menu.buy Menu.sel = 1 Sfx.play("menu") end
    local stock = SHOPS[Menu.opt.shop]
    if Menu.buy then
      nav(#stock // 2)
      if In.p.atk or In.p.ok then
        local id, price = stock[Menu.sel * 2 - 1], stock[Menu.sel * 2]
        if P.ryo < price then Sfx.play("error") UI.toast("Not enough ryo")
        elseif Inv.add(id, 1) > 0 then Sfx.play("error") UI.toast("Bag is full")
        else
          P.ryo = P.ryo - price
          Sfx.play("coin")
          Quest.event("item", id)
        end
      end
    else
      nav(Inv.size)
      if In.p.atk or In.p.ok then
        local s = Inv.slots[Menu.sel]
        if s and not ITEM[s.id].key and ITEM[s.id].sell then
          Inv.take(s.id, 1)
          P.ryo = P.ryo + ITEM[s.id].sell
          if P.weapon == s.id and not Inv.has(s.id) then P.weapon = "bokken" end
          if P.armor == s.id and not Inv.has(s.id) then P.armor = nil end
          Sfx.play("coin")
        end
      end
    end
  end
end

function Menu.questList()
  local l = {}
  for _, q in ipairs(QUESTS) do if Quest.state(q.id) == "active" then l[#l + 1] = q end end
  for _, q in ipairs(QUESTS) do if Quest.state(q.id) == "done" then l[#l + 1] = q end end
  return l
end

-- ---------------------------------------------------------------------------
-- drawing. Panels keep a key-hint footer row on their last 10 pixels: content
-- ends above the divider. The world behind menus is dimmed through the bank-0
-- palette (Game.tick), not with scanlines.
-- ---------------------------------------------------------------------------
-- key cap: the Z/X/A/S sprites, else a drawn cap with the letter(s)
function Menu.key(k, x, y)
  local r = SPR["key_" .. k]
  if r then blit(r, x, y) return 8 end
  local w = textw(k:upper(), true) + 3
  rect(x, y, w, 7, C_NIGHT)
  rect(x + 1, y, w - 2, 7, C_WHITE)
  print(k:upper(), x + 2, y + 1, C_NIGHT, false, 1, true)
  return w
end

-- hints from the left ({key, label} pairs), the close key on the right
local function footer(items, x0, x1, y, back)
  line(x0, y - 3, x1, y - 3, C_INDIGO)
  local x = x0 + 2
  for _, it in ipairs(items) do
    x = x + Menu.key(it[1], x, y) + 2
    x = x + print(it[2], x, y + 1, C_WHITE, false, 1, true) + 6
  end
  local s = back or "Close"
  local w = textw(s, true)
  Menu.key("x", x1 - w - 11, y)
  print(s, x1 - w - 1, y + 1, C_WHITE, false, 1, true)
end

-- text cut to a pixel width with an ellipsis
function Menu.fit(s, w, small)
  if textw(s, small) <= w then return s end
  while #s > 1 and textw(s .. "..", small) > w do s = s:sub(1, -2) end
  return s .. ".."
end

local function itemInfo(id, x, y, w)
  local it = ITEM[id]
  if not it then return end
  tprint(Menu.fit(it.n, w), x, y, C_GOLD)
  local yy = y + 10
  for _, l in ipairs(wrap(it.d or "", w, true)) do print(l, x, yy, C_WHITE, false, 1, true) yy = yy + 7 end
  local stats = {}
  if it.hun then stats[#stats + 1] = "Hunger +" .. it.hun end
  if it.hp then stats[#stats + 1] = (it.hp > 0 and "Hearts +" or "Hearts ") .. (it.hp / 4) end
  if it.stam then stats[#stats + 1] = "Stamina +" .. math.min(it.stam, 100) end
  if it.dmg then stats[#stats + 1] = "Attack " .. it.dmg end
  if it.def then stats[#stats + 1] = "Defense " .. it.def end
  for _, s in ipairs(stats) do print(s, x, yy + 2, C_LIME, false, 1, true) yy = yy + 7 end
  return yy
end

-- equal tabs centred between the Q and E caps
local function drawTabs()
  local n, w, gap = #TABN, 41, 2
  local x0 = (240 - (n * w + (n - 1) * gap)) // 2
  Menu.key("q", x0 - 11, 5)
  Menu.key("e", x0 + n * w + (n - 1) * gap + 4, 5)
  for i, name in ipairs(TABN) do
    local x = x0 + (i - 1) * (w + gap)
    local sel = i == Menu.tab
    rect(x, 3, w, 12, sel and C_RED or C_NIGHT)
    rectb(x, 3, w, 12, sel and C_GOLD or C_TAN)
    print(name, x + (w - textw(name)) // 2 + 1, 6, sel and C_WHITE or C_GRAY)
  end
end

-- first visible row of a scrolling list of n rows showing `rows` at a time
function Menu.scroll(n, rows)
  return clamp(Menu.sel - rows // 2, 1, math.max(1, n - rows + 1))
end
function Menu.scrollMarks(x, y0, y1, first, rows, n)
  if first > 1 then tri(x, y0 + 3, x + 4, y0 + 3, x + 2, y0, C_GOLD) end
  if first + rows - 1 < n then tri(x, y1 - 3, x + 4, y1 - 3, x + 2, y1, C_GOLD) end
end

function Menu.draw()
  local k = Menu.cur
  if not k then return end
  if k == "pause" then
    drawTabs()
    local t = Menu.tab
    if t == 1 then
      panel(4, 17, 232, 115)
      for i = 1, Inv.size do
        local cx = 10 + ((i - 1) % 4) * 16
        local cy = 21 + ((i - 1) // 4) * 16
        UI.slot(cx, cy, Inv.slots[i], i == Menu.sel)
        if i <= 10 then print(tostring(i % 10), cx - 4, cy, C_GRAY, false, 1, true) end
      end
      print("Equipped", 10, 84, C_TAN, false, 1, true)
      local eq = { P.weapon, P.armor, P.light }
      for j = 1, 3 do
        UI.slot(10 + (j - 1) * 16, 91, eq[j] and { id = eq[j], n = 1 } or nil, false)
      end
      print("Bag " .. Inv.size .. "/16", 10, 107, C_GRAY, false, 1, true)
      line(76, 20, 76, 116, C_INDIGO)
      blit(SPR.seed, 82, 106)
      print(P.seeds .. " seeds", 92, 108, C_WHITE, false, 1, true)
      blit(SPR.orbi, 136, 106)
      print(P.orbs .. " orbs", 146, 108, C_WHITE, false, 1, true)
      local s = Inv.slots[Menu.sel]
      local hints = {}
      if s then
        itemInfo(s.id, 82, 22, 148)
        local it = ITEM[s.id]
        local act = ({ food = "Eat", weapon = "Equip", armor = "Wear", light = "Light", place = "Place", bed = "Sleep" })[it.k]
        if act then hints[#hints + 1] = { "z", act } end
        if not it.key then hints[#hints + 1] = { "a", "Drop" } end
      else
        print("Empty slot", 82, 22, C_GRAY)
      end
      footer(hints, 8, 231, 122)
    elseif t == 2 then
      panel(4, 17, 232, 115)
      local icons = { "tab_tools", "tab_light", "tab_surv", "tab_combat", "tab_dress" }
      for i, ic in ipairs(icons) do
        local y = 21 + (i - 1) * 19
        rect(8, y, 16, 16, i == Menu.ctab and C_RED or C_NIGHT)
        rectb(8, y, 16, 16, i == Menu.ctab and C_GOLD or C_INDIGO)
        blit(SPR[ic], 12, y + 4)
      end
      tprint(TABS[Menu.ctab], 30, 21, C_GOLD)
      local list = recipesIn(Menu.ctab)
      for i, r in ipairs(list) do
        local y = 32 + (i - 1) * 12
        local can = Craft.can(r)
        if i == Menu.sel then rect(29, y - 2, 82, 12, C_INDIGO) end
        blit(SPR["i_" .. r.out], 31, y)
        print(Menu.fit(ITEM[r.out].n .. (r.n > 1 and (" x" .. r.n) or ""), 66, true), 42, y + 1, can and C_WHITE or C_GRAY, false, 1, true)
      end
      line(114, 20, 114, 116, C_INDIGO)
      local r = list[Menu.sel]
      if r then
        local yy = itemInfo(r.out, 120, 22, 110)
        yy = math.max(yy + 4, 66)
        print("Needs:", 120, yy, C_TAN, false, 1, true)
        for j, nd in ipairs(r.need) do
          local have = Inv.count(nd[1])
          local y2 = yy + 8 + (j - 1) * 10
          blit(SPR["i_" .. nd[1]], 120, y2)
          print(Menu.fit(ITEM[nd[1]].n, 64, true) .. " " .. have .. "/" .. nd[2], 131, y2 + 2, have >= nd[2] and C_LIME or C_RED, false, 1, true)
        end
      end
      footer({ { "z", "Craft" }, { "s", "Category" } }, 8, 231, 122)
    elseif t == 3 then
      MapUI.draw()
    elseif t == 4 then
      panel(4, 17, 232, 115)
      local list = Menu.questList()
      local rows = 12
      local first = Menu.scroll(#list, rows)
      for i = first, math.min(#list, first + rows - 1) do
        local q = list[i]
        local y = 21 + (i - first) * 8
        local done = Quest.state(q.id) == "done"
        local col = done and C_GRAY or (q.main and C_GOLD or C_WHITE)
        if i == Menu.sel then rect(7, y - 1, 100, 8, C_INDIGO) end
        print(Menu.fit((Quest.tracked == q.id and ">" or " ") .. q.name, 96, true), 8, y, col, false, 1, true)
      end
      Menu.scrollMarks(107, 19, 115, first, rows, #list)
      line(114, 20, 114, 116, C_INDIGO)
      local q = list[Menu.sel]
      local hints = {}
      if q then
        local yy = 22
        for _, l in ipairs(wrap(q.name, 110, true)) do tprint(l, 120, yy, q.main and C_GOLD or C_WHITE, true) yy = yy + 7 end
        yy = yy + 3
        local s = QS[q.id]
        for j, st in ipairs(q.steps) do
          local done = s.st == "done" or j < s.step
          local cur = s.st == "active" and j == s.step
          if done or cur then
            local txt = cur and Quest.text(q.id) or st.text
            for _, l in ipairs(wrap((done and "v " or "> ") .. txt, 110, true)) do
              if yy <= 110 then print(l, 120, yy, done and C_GRAY or C_WHITE, false, 1, true) end
              yy = yy + 7
            end
            yy = yy + 2
          end
        end
        if s.st == "active" then hints[1] = { "z", Quest.tracked == q.id and "Tracking" or "Track" } end
      end
      footer(hints, 8, 231, 122)
    elseif t == 5 then
      panel(4, 17, 232, 115)
      if Menu.sub == "help" then
        local lines = { "Arrows  move      SHIFT/C  sprint", "X  jump, hold in air: glide, in water: leap", "Z  katana / chop / mine, in air: plunge",
          "A  talk, pick up, open, cook", "S  throw shuriken   Q/E  rotate camera", "Push into walls to climb, X to leap",
          "TAB menu   M map   J quests   1-0 use slot", "Eat to stay fed. At night carry light,", "or the Yami will find you." }
        for i, l in ipairs(lines) do print(l, 12, 23 + (i - 1) * 10, C_WHITE, false, 1, true) end
        footer({}, 8, 231, 122, "Back")
      else
        local lv = Audio.LEVELS
        local opts = { "Save game", "Controls", "Music volume: " .. lv[Audio.music], "Sound volume: " .. lv[Audio.sfx], "Save & quit to title" }
        for i, o in ipairs(opts) do
          local y = 23 + (i - 1) * 13
          if i == Menu.sel then rect(10, y - 3, 150, 12, C_INDIGO) end
          print(o, 16, y, i == Menu.sel and C_GOLD or C_WHITE)
        end
        print("Day " .. Clock.day .. "   Kills " .. Menu.totalKills(), 16, 92, C_GRAY, false, 1, true)
        print("Towers " .. Quest.towerCount() .. "/" .. #TOWERS .. "   Shrines " .. Menu.count(Shrine.done) .. "/" .. #SHRINES, 16, 100, C_GRAY, false, 1, true)
        print("Kodama found " .. Menu.count(World.found) .. "/" .. #KODAMA, 16, 108, C_GRAY, false, 1, true)
        footer({ { "z", Menu.sel >= 3 and Menu.sel <= 4 and "Change" or "Select" } }, 8, 231, 122)
      end
    end
  elseif k == "cook" then
    local pot = Menu.opt.pot
    panel(30, 16, 180, 104)
    tprint(pot and "Cooking Pot" or "Campfire", 36, 20, C_GOLD)
    local list = cookables(pot)
    local n = #list + (pot and 1 or 0)
    local rows = 6
    local first = Menu.scroll(n, rows)
    for i = first, math.min(n, first + rows - 1) do
      local y = 32 + (i - first) * 11
      if i == Menu.sel then rect(34, y - 2, 90, 11, C_INDIGO) end
      local id = list[i]
      if id then
        blit(SPR["i_" .. id], 36, y)
        print(Menu.fit(ITEM[id].n .. " x" .. Inv.count(id), 76, true), 47, y + 1, C_WHITE, false, 1, true)
      else
        print("> Cook!", 38, y + 1, C_GOLD, false, 1, true)
      end
    end
    Menu.scrollMarks(118, 30, 96, first, rows, n)
    if #list == 0 then print(pot and "No ingredients" or "Nothing to cook", 36, 34, C_GRAY, false, 1, true) end
    if pot then
      print("In the pot:", 130, 32, C_TAN, false, 1, true)
      for j, id in ipairs(Menu.pick) do blit(SPR["i_" .. id], 130 + (j - 1) * 11, 42) end
      local out = potResult(Menu.pick)
      if out then
        print("Makes:", 130, 58, C_TAN, false, 1, true)
        blit(SPR["i_" .. out], 130, 66)
        print(Menu.fit(ITEM[out].n, 64, true), 141, 68, C_LIME, false, 1, true)
      end
      footer({ { "z", "Add" }, { "a", "Clear" } }, 34, 205, 108)
    else
      local id = list[Menu.sel]
      if id then
        print("Cooks into:", 130, 32, C_TAN, false, 1, true)
        local out = ITEM[id].cook
        blit(SPR["i_" .. out], 130, 42)
        print(Menu.fit(ITEM[out].n, 64, true), 141, 44, C_LIME, false, 1, true)
      end
      footer({ { "z", "Cook" } }, 34, 205, 108)
    end
  elseif k == "shop" then
    local stock = SHOPS[Menu.opt.shop]
    panel(16, 8, 208, 122)
    local rs = tostring(P.ryo)
    local rw = textw(rs, true)
    blit(SPR.ryo, 216 - rw - 10, 12)
    print(rs, 216 - rw, 14, C_GOLD, false, 1, true)
    local who = Menu.opt.who and Menu.opt.who.name or "Shop"
    tprint(Menu.fit(who, 216 - rw - 10 - 28), 22, 13, C_GOLD)
    for j, lab in ipairs({ "Buy", "Sell" }) do
      local x = 22 + (j - 1) * 32
      local on = (j == 1) == (Menu.buy == true)
      rect(x, 24, 30, 9, on and C_RED or C_NIGHT)
      rectb(x, 24, 30, 9, on and C_GOLD or C_INDIGO)
      print(lab, x + (30 - textw(lab, true)) // 2 + 1, 26, on and C_WHITE or C_GRAY, false, 1, true)
    end
    if Menu.buy then
      for i = 1, #stock // 2 do
        local id, price = stock[i * 2 - 1], stock[i * 2]
        local y = 38 + (i - 1) * 10
        if i == Menu.sel then rect(20, y - 2, 114, 10, C_INDIGO) end
        blit(SPR["i_" .. id], 22, y - 1)
        print(Menu.fit(ITEM[id].n, 70, true), 33, y, P.ryo >= price and C_WHITE or C_GRAY, false, 1, true)
        local ps = price .. "r"
        print(ps, 132 - textw(ps, true), y, C_GOLD, false, 1, true)
      end
      line(137, 36, 137, 116, C_INDIGO)
      local id = stock[Menu.sel * 2 - 1]
      if id then itemInfo(id, 142, 38, 76) end
    else
      for i = 1, Inv.size do
        local s = Inv.slots[i]
        local y = 38 + ((i - 1) % 8) * 10
        local x = 20 + ((i - 1) // 8) * 100
        if i == Menu.sel then rect(x, y - 2, 98, 10, C_INDIGO) end
        if s then
          blit(SPR["i_" .. s.id], x + 2, y - 1)
          local it = ITEM[s.id]
          local ps = it.key and "-" or (it.sell .. "r")
          print(Menu.fit(it.n, 82 - textw(ps, true), true), x + 13, y, it.key and C_GRAY or C_WHITE, false, 1, true)
          print(ps, x + 96 - textw(ps, true), y, it.key and C_GRAY or C_GOLD, false, 1, true)
        end
      end
    end
    footer({ { "z", Menu.buy and "Buy" or "Sell" }, { "<>", "Switch" } }, 20, 219, 120, "Leave")
  end
end

function Menu.count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function Menu.totalKills() local n = 0 for _, v in pairs(P.kills) do n = n + v end return n end

-- ---------------------------------------------------------------------------
-- world map: map texture minified to 1px/cell + fog of war (4x4 cell blocks)
-- ---------------------------------------------------------------------------
function MapUI.reveal(x, y, r)
  local bx, by = flr(x / 32), flr(y / 32)
  local rb = math.ceil(r / 4)
  for yy = by - rb, by + rb do
    for xx = bx - rb, bx + rb do
      if xx >= 0 and yy >= 0 and xx < 60 and yy < 28 and (xx - bx) ^ 2 + (yy - by) ^ 2 <= rb * rb then
        MapUI.seen[yy * 60 + xx] = true
      end
    end
  end
end

function MapUI.draw()
  local ox, oy = 0, 18
  rect(0, 16, 240, 116, C_INDIGO)
  ttri(ox, oy, ox + 240, oy, ox, oy + 112, 4, 4, 1924, 4, 4, 900, 1)
  ttri(ox + 240, oy, ox + 240, oy + 112, ox, oy + 112, 1924, 4, 1924, 900, 4, 900, 1)
  -- fog
  for by = 0, 27 do
    for bx = 0, 59 do
      if not MapUI.seen[by * 60 + bx] then
        rect(ox + bx * 4, oy + by * 4, 4, 4, ((bx + by) % 2 == 0) and C_NIGHT or C_INDIGO)
      end
    end
  end
  local function mark(x, y, icon)
    local mx, my = ox + x / 8, oy + y / 8
    if MapUI.seen[flr(y / 32) * 60 + flr(x / 32)] then blit(SPR[icon], flr(mx - 4), flr(my - 4)) end
  end
  for _, t in ipairs(TOWNS) do mark(t.x, t.y, "townico") end
  for _, s in ipairs(SHRINES) do
    if MapUI.seen[flr(s.y / 32) * 60 + flr(s.x / 32)] then
      local mx, my = ox + s.x / 8, oy + s.y / 8
      circ(mx, my, 2, Shrine.done[s.id] and C_BLUE or C_WHITE)
      circb(mx, my, 2, C_NIGHT)
    end
  end
  local on = {}
  for _, tw in ipairs(TOWERS) do
    mark(tw.x, tw.y, "towerico")
    if Quest.towersOn[tw.id] then on[#on + 1] = tw end
  end
  for id, b in pairs({ jorogumo = "lair", tengulord = "summit", orochi = "lake", shuten = "onigashima" }) do
    if not Boss.defeated[id] and Quest.state("mq2") == "done" then
      local p = POI[b]
      blit(SPR.bossico, flr(ox + p.x / 8 - 4), flr(oy + p.y / 8 - 4))
    end
  end
  local tx, ty = Quest.target()
  if tx and (Frame // 10) % 2 == 0 then blit(SPR.pin, flr(ox + tx / 8 - 4), flr(oy + ty / 8 - 8)) end
  -- player
  local px, py = ox + P.x / 8, oy + P.y / 8
  if (Frame // 8) % 2 == 0 then circ(px, py, 2, C_RED) end
  circb(px, py, 3, C_WHITE)
  -- fast travel list
  if #on > 0 then
    local sel = on[clamp(Menu.sel, 1, #on)]
    if sel then
      local mx, my = ox + sel.x / 8, oy + sel.y / 8
      rectb(mx - 6, my - 6, 12, 12, (Frame // 6) % 2 == 0 and C_GOLD or C_WHITE)
      tprint("Z: travel to " .. sel.name, 4, 124, C_GOLD, true)
    end
  else
    tprint("Survey pagodas (climb + A) to unlock fast travel", 4, 124, C_WHITE, true)
  end
end

-- ============================================================================
--  60 AUDIO - everything is generated in code at boot, no binary cart
--  sections: 16 waveforms and the SFX slots are poked into sound RAM, the
--  music is a step sequencer on channels 0-2 and effects play on channel 3.
--
--    Sfx.play(name)     one-shot effect (Sfx.NAMES). "complete", "tower" and
--                       "victory" are jingles: they pause the music (ch 0-2)
--    Music.play(track)  title field night snow town oni boss, nil = stop;
--                       the same track is a no-op, others fade over
--    Music.region()     track for the player's region / town / time / battle
--    Music.update()     once per frame from Game.tick (timers + sequencers)
--    Audio.init()       from Boot.all; Audio.errors lists bad song data
--    Audio.setLevels(m, s)  music / effects volume 0-3 (System tab, pmem 255)
--
--  SFX slot (0x100E4 + id*66, verified on 1.3.1): 30 ticks x 2 bytes =
--  (15 - loudness) | wave << 4, arpeggio | pitch << 4; byte 60 = octave |
--  pitch16x << 3 | speed << 4 | reverse << 7; 61 = note; 62-65 = loops
--  (wave, volume, arpeggio, pitch) start | size << 4. Note numbers given to
--  sfx() must be Lua integers (a float raises "invalid note"); 57 = A4.
--  Slots 0-14 hold the music instruments, 16-55 the effects.
--
--  Envelope strings, one char per tick (spaces ignored):
--    v loudness 0-f, padded with 0     w waveform 0-f
--    a arpeggio 0-f semitones          p pitch 0-7 up, A-H = -1..-8
--  w/a/p repeat their last char. s = speed (-n: n+1 frames per tick),
--  x = pitch steps of 16 Hz instead of 1 Hz, r = arpeggio goes down,
--  loop = { v = { start, size }, p = ... }.
--
--  Song strings, one token per step: "D4" note ("!" louder, "?" softer),
--  "-" hold, "." rest (sustained voices play their release), a single
--  letter = hit from the track's kit. Bars are one line each.
-- ============================================================================
Audio = { ready = false, errors = {}, music = 3, sfx = 3, LEVELS = { [0] = "Off", "Low", "Mid", "High" } }
Sfx = {
  NAMES = { "swing", "hit", "kill", "hurt", "die", "jump", "djump", "land", "slam", "throw", "clank", "chop", "mine", "fall",
    "pick", "coin", "chest", "craft", "eat", "equip", "place", "fire", "heal", "upgrade", "quest", "complete", "tower",
    "kodama", "menu", "select", "open", "close", "error", "talk", "blip", "growl", "roar", "blink", "splash", "tired",
    "whisper", "cat", "victory" },
  vol = 1, busy = 0, pri = 0, t = 0, lastT = -99, queue = {},
}
Music = { cur = nil, vol = 1, fadeT = 0, human = true }

;(function()
  local WAVE_RAM, SFX_RAM, FADE, LEVEL = 0x0FFE4, 0x100E4, 40, { [0] = 0, 0.35, 0.65, 1 }

  -- --------------------------------------------------------------------------
  -- waveforms (32 x 4-bit). All 0 = white noise, all F = metallic noise.
  -- --------------------------------------------------------------------------
  local function harm(amps)
    local s, lo, hi = {}, 1e9, -1e9
    for k = 0, 31 do
      local v = 0
      for n, a in ipairs(amps) do v = v + a * sin(TAU * n * k / 32) end
      s[k] = v
      lo, hi = min(lo, v), max(hi, v)
    end
    return function(k) return flr((s[k] - lo) / (hi - lo) * 15 + 0.5) end
  end
  local WAVES = {
    [0] = function() return 0 end,                  -- white noise
    [1] = function() return 15 end,                 -- metallic noise
    [2] = harm({ 1 }),                              -- sine
    [3] = function(k) return k < 16 and k or 31 - k end, -- triangle
    [4] = function(k) return k < 16 and 15 or 0 end, -- square
    [5] = function(k) return k < 8 and 15 or 0 end, -- pulse 25%
    [6] = function(k) return k < 4 and 15 or 0 end, -- pulse 12.5%
    [7] = function(k) return k // 2 end,            -- saw
    [8] = harm({ 1, .81, .54, .25, 0, .17, .23, .2 }), -- koto attack (string plucked at 1/5)
    [9] = harm({ 1, .4, .12, .04 }),                -- koto body
    [10] = harm({ 1, .22, .1, .04 }),               -- shakuhachi
    [11] = harm({ 1, .7, .8, .5, .6, .3, .4, .2 }), -- shamisen
    [12] = harm({ 1, 0, .6, 0, .45, 0, 0, .3 }),    -- bell
    [13] = harm({ 1, 0, .2 }),                      -- drum body
    [14] = harm({ 1, .75, .55, .4, .25, .15 }),     -- bass
    [15] = harm({ 1, .45, .3, .12, .08 }),          -- fue (bamboo flute)
  }

  -- --------------------------------------------------------------------------
  -- instruments (music) and effects
  -- --------------------------------------------------------------------------
  local INST = {
    koto   = { id = 0, s = -1, w = "789", v = "fdcba 99887 76655 54443 33222 1111", p = "210" },
    shaku  = { id = 2, s = -1, w = "0a", v = "48abc cccbb bbccb baa", p = "CBA00 00000 0232 0BCB", rel = "shakuR",
      loop = { v = { 10, 8 }, p = { 10, 8 } } },
    shakuR = { id = 3, s = -1, w = "a", v = "a8643 21", p = "00ABC" },
    bass   = { id = 4, s = -2, w = "e", v = "fedcc bbaa9 98877 66554 43322 111", p = "4210" },
    taiko  = { id = 5, s = 0, x = true, w = "00d", v = "fcfed cba98 76554 43322 111", a = "fc0", p = "00543 22110 000AA B" },
    rim    = { id = 6, s = 0, w = "1d", v = "f9521" },
    kane   = { id = 7, s = 0, w = "1c", v = "db987 65432 11", a = "00606 06060 6060" },
    clap   = { id = 8, s = 0, w = "04", v = "fa41" },
    furin  = { id = 9, s = -2, w = "c", v = "bfedc baa99 88776 65544 33322 2111", p = "0000 1210ABA0", loop = { p = { 4, 8 } } },
    sham   = { id = 10, s = 0, x = true, w = "7b", v = "fdba9 88776 65544 43332 22111 10", p = "10" },
    fue    = { id = 11, s = -1, w = "0f", v = "6acdd dcccc ccddc c", p = "BA000 00000 0330CC", rel = "fueR",
      loop = { v = { 10, 6 }, p = { 10, 6 } } },
    fueR   = { id = 12, s = -1, w = "f", v = "b8532 1", p = "0ABCD" },
    bonsho = { id = 13, s = -4, w = "1c", v = "feedc dcbcb abab9 a9898 78765 4321", a = "c0" },
    wind   = { id = 14, s = -4, w = "0", v = "12345 66777 76655 44332 211", a = "01234 56776 54321 0" },
  }

  -- id, waveform/envelopes, base note (57 = A4), vol 0-15, pri (higher cuts
  -- lower), jit = random +-semitones per play
  local SFXD = {
    swing   = { id = 16, s = 0, w = "0", v = "59cef db975 4321", a = "02468 9abba 98765", note = 60, vol = 11, pri = 2, jit = 2 },
    hit     = { id = 17, s = 0, x = true, w = "10ddddd", v = "ffeca 86432 1", a = "c70", p = "00432 10AB", note = 33, vol = 15, pri = 2, jit = 1 },
    kill    = { id = 18, s = -1, w = "440", v = "fefed cba98 76543 21", a = "c7fed cba98 76543 210", note = 48, vol = 15, pri = 3 },
    hurt    = { id = 19, s = 0, r = true, w = "05", v = "ffedc ba987 65432 1", a = "00123 45678 9ab", note = 64, vol = 15, pri = 3 },
    die     = { id = 20, s = -2, r = true, w = "89", v = "fca98 eb987 da876 c9765 b8654 a8642", a = "00000 33333 55555 77777 aaaaa ccccc", note = 62, vol = 14, pri = 4 },
    jump    = { id = 21, s = 0, x = true, w = "005", v = "46876 54321", p = "00012 34567", note = 48, vol = 10, pri = 2, jit = 1 },
    djump   = { id = 22, s = 0, x = true, w = "05", v = "59a98 76543 21", a = "000cc 00cc0", p = "01234 567", note = 60, vol = 10, pri = 2 },
    land    = { id = 23, s = 0, w = "0", v = "9631", note = 33, vol = 9, pri = 1, jit = 2 },
    slam    = { id = 24, s = -1, x = true, w = "10d", v = "fffed cba98 76543 21", a = "ff0", p = "00543 22110 0AABB C", note = 38, vol = 15, pri = 3 },
    throw   = { id = 25, s = 0, w = "00111", v = "8c964 321", a = "03ccc", note = 72, vol = 11, pri = 2, jit = 2 },
    clank   = { id = 26, s = 0, w = "11c", v = "fdcba 98765 43322 11", a = "00060 60606 06060 6", note = 76, vol = 13, pri = 2, jit = 1 },
    chop    = { id = 27, s = 0, x = true, w = "0d", v = "fd953 1", p = "03210", note = 45, vol = 14, pri = 2, jit = 1 },
    mine    = { id = 28, s = 0, w = "1c", v = "feb97 65432 1", a = "00070 70", note = 69, vol = 12, pri = 2, jit = 1 },
    fall    = { id = 29, s = -1, x = true, w = "55555 50", v = "34567 8ffed cba98 76543 21", a = "00000 0fca8 65432 10", p = "01021 30", note = 36, vol = 14, pri = 3 },
    pick    = { id = 30, s = 0, w = "5", v = "cac8c a8642 1", a = "00007", note = 64, vol = 11, pri = 2 },
    coin    = { id = 31, s = 0, w = "4", v = "ccccf edcba 98765 4321", a = "00005", note = 71, vol = 11, pri = 2 },
    chest   = { id = 32, s = -1, w = "555c", v = "4650f cafca fcafe dcba9 87654 321", a = "01000 00222 777c", note = 62, vol = 13, pri = 3 },
    craft   = { id = 33, s = 0, w = "11100 0111000 c", v = "c6200 0c6200 0fdbe cafed cba98 7654", a = "00000 00000 00000 777c", note = 64, vol = 12, pri = 2 },
    eat     = { id = 34, s = 0, w = "0", v = "9b520 00ac6 20009 b521", a = "00000 00222 20001", note = 45, vol = 12, pri = 2 },
    equip   = { id = 35, s = 0, x = true, w = "1111c", v = "48cfe dcba9 87654 321", a = "0000c", p = "01233", note = 72, vol = 10, pri = 2 },
    place   = { id = 36, s = 0, w = "003", v = "c6c84 21", a = "00c", note = 38, vol = 11, pri = 2 },
    fire    = { id = 37, s = -1, w = "0", v = "2468a ccba9 87867 56453 42312 1", a = "01234 56789 99c9c 9c9c9 c9c9c 9", note = 41, vol = 12, pri = 2 },
    heal    = { id = 38, s = -1, w = "2", v = "a86ca 8ecaf db987 65432 1", a = "00022 2777c", note = 62, vol = 12, pri = 3 },
    upgrade = { id = 39, s = -2, w = "c", v = "fcafc afcaf cafca fedcb a9876 54321", a = "00022 25557 7799 9c", note = 62, vol = 13, pri = 3 },
    quest   = { id = 40, s = -2, w = "89", v = "fca8f ca8fe dcba9 87654 321", a = "00005 5557", note = 57, vol = 13, pri = 3 },
    kodama  = { id = 41, s = 0, w = "d", v = "c00b0 0c00a 00b00 90080 06004 00200", a = "00030 01004 00200 50030 01004 00200", note = 72, vol = 12, pri = 3 },
    menu    = { id = 42, s = 0, w = "4", v = "852", note = 76, vol = 8, pri = 1 },
    select  = { id = 43, s = 0, w = "4", v = "ccaa9 86421", a = "007", note = 69, vol = 10, pri = 2 },
    open    = { id = 44, s = 0, w = "5", v = "68acc a8642 1", a = "00055 57", note = 62, vol = 10, pri = 1 },
    close   = { id = 45, s = 0, r = true, w = "5", v = "ca8ca 86421", a = "00055 57", note = 74, vol = 10, pri = 1 },
    error   = { id = 46, s = 0, w = "4", v = "ccc00 ccc", a = "00000 111", note = 40, vol = 11, pri = 2 },
    talk    = { id = 47, s = 0, x = true, w = "335", v = "6aba8 6421", p = "00123 32", note = 57, vol = 10, pri = 2, jit = 2 },
    blip    = { id = 48, s = 0, w = "5", v = "63", note = 69, vol = 6, pri = 1, jit = 3 },
    growl   = { id = 49, s = 0, w = "01010 10101 01010 1", v = "69bcc ba987 65432 1", a = "01210 12101 2101", note = 28, vol = 11, pri = 2 },
    roar    = { id = 50, s = -2, x = true, w = "07070 70707 07070 70707 07070", v = "8bdff ffeed dccbb a9876 54321",
      a = "c0c0c 0c0c0 c0c0c 0c0c0 c0c0c", p = "0011 00AA 0011 00AA 0011 00AA", note = 36, vol = 15, pri = 3 },
    blink   = { id = 51, s = 0, w = "25", v = "ccba9 8642", a = "047cf c740", note = 72, vol = 10, pri = 2 },
    splash  = { id = 52, s = -1, w = "0", v = "feca9 a8786 56432 1", a = "98765 43210", note = 52, vol = 13, pri = 2 },
    tired   = { id = 53, s = -1, w = "0", v = "03542 10003 5421", note = 48, vol = 10, pri = 2 },
    whisper = { id = 54, s = -3, w = "00220 02200 22002 20022 0", v = "12345 66777 66554 43322 11",
      a = "00660 06600 66006 60066 0", p = "01210 ABA01 210AB A0121 0", note = 53, vol = 9, pri = 3 },
    cat     = { id = 55, s = -1, x = true, w = "556", v = "48cdd dccba 97531", a = "02457 77542 0", p = "00000 00000 0ABC", note = 60, vol = 11, pri = 2 },
  }

  -- --------------------------------------------------------------------------
  -- songs
  -- --------------------------------------------------------------------------
  -- the main theme in D Yo (D E G A B); night / title play it in D In
  -- (E -> Eb, B -> Bb), the same melody turned dark
  local THEME = {
    lead = {
      A = [[
        A4 - - - B4 - D5 -
        B4 - A4 - - - - -
        G4 - A4 - B4 - A4 G4
        E4 - - - - - . .
        A4 - - - B4 - D5 -
        E5 - - - D5 - B4 -
        A4 - B4 - G4 - E4 -
        D4 - - - - - . .]],
      B = [[
        D5 - - - E5 - D5 B4
        A4 - - - - - B4 -
        D5 - E5 - G5 - E5 D5
        B4 - - - - - . .
        A4 - B4 - D5 - B4 A4
        G4 - - - E4 - G4 -
        A4 - - - - - - -
        - - - - . . . .]],
      B2 = [[
        D5 - - E5 D5 - B4 A4
        B4 - - - - - D5 -
        E5 - G5 - A5 - G5 E5
        D5 - - - - - . .
        B4 - D5 - E5 - D5 B4
        A4 - - - G4 - E4 -
        D4 - - - - - - -
        - - - - . . . .]],
    },
    koto = {
      A = [[
        D3 . A3 . D4 . . .
        D3 . A3 . E4 . D4 .
        G3 . D4 . G4 . . .
        E3 . B3 . E4 . G4 .
        D3 . A3 . D4 . . .
        G3 . D4 . G4 . A4 .
        A3 . D4 . A4 . G4 .
        D3 . A3 . D4 . A3 .]],
      B = [[
        G3 D4 G4 A4 B4 . A4 .
        D3 A3 D4 E4 A4 . E4 .
        E3 B3 E4 G4 B4 . G4 .
        E3 B3 E4 . B3 . G3 .
        D3 A3 D4 E4 A4 . D4 .
        G3 D4 G4 A4 D5 . A4 .
        A3 D4 A4 . D4 . A3 .
        A3 D4 G4 . D4 . A3 .]],
      A2 = [[
        D3 A3 D4 . A4 . B4 D5
        B4 . A4 . D4 . A3 .
        G3 D4 G4 . A4 B4 A4 G4
        E4 . B3 . E3 . . .
        D3 A3 D4 . A4 . B4 D5
        E5 . D5 B4 G4 . D4 .
        A3 D4 A4 B4 G4 . E4 .
        D4 . A3 . D3 . . .]],
    },
    low = {
      A = [[
        D2 . . . . . . .
        . . . . d . . .
        G2 . . . . . . .
        E2 . . . d . . .
        D2 . . . . . . .
        G2 . . . d . . .
        A2 . . . . . . .
        D2 . . . d . k k]],
      B = [[
        G2 . . . d . . .
        D2 . . . . . . .
        E2 . . . d . . .
        E2 . . . . . k .
        D2 . . . d . . .
        G2 . . . . . . .
        A2 . . . d . . .
        A2 . . . d . d d]],
      A2 = [[
        D2 . . . d . . .
        . . . . d . k .
        G2 . . . d . . .
        E2 . . . d . k k
        D2 . . . d . . .
        G2 . . . d . k .
        A2 . . . d . . .
        D2 . . . d . d .]],
    },
  }
  THEME.koto.B2, THEME.low.B2 = THEME.koto.B, THEME.low.B

  -- town: a festival (matsuri) tune in G Yo (G A C D E)
  local TOWN = {
    fue = {
      A = [[
        D5 - E5 D5 C5 - A4 -
        G4 - A4 - C5 - - -
        D5 - E5 - G5 - E5 D5
        E5 - - - - - . .
        G5 - E5 D5 E5 - D5 C5
        A4 - C5 - D5 - - -
        C5 - A4 G4 A4 - C5 A4
        G4 - - - - - . .]],
      B = [[
        E5 - D5 - C5 - D5 -
        E5 - G5 - E5 - D5 -
        C5 - D5 - A4 - G4 -
        A4 - - - - - . .
        E5 - D5 - C5 - D5 -
        E5 - G5 - A5 - G5 E5
        D5 - C5 - A4 - C5 -
        G4 - - - - - . .]],
    },
    sham = {
      A = [[
        G3 . D4 G4 . D4 G4 .
        G3 . D4 G4 . D4 A4 .
        C4 . G4 C5 . G4 C5 .
        C4 . G4 C5 . G4 E4 .
        G3 . D4 G4 . D4 G4 .
        D4 . A4 D5 . A4 D5 .
        C4 . G4 C5 . G4 A4 .
        G3 . D4 G4 D4 . G3 .]],
      B = [[
        C4 . G4 C5 . G4 C5 .
        C4 . G4 C5 . G4 E4 .
        D4 . A4 D5 . A4 D5 .
        D4 . A4 D5 . A4 C5 .
        C4 . G4 C5 . G4 C5 .
        A3 . E4 A4 . E4 A4 .
        D4 . A4 D5 . A4 D5 .
        G3 . D4 G4 D4 . G3 .]],
      A2 = [[
        D4 . E4 D4 C4 . A3 .
        G3 . A3 . C4 D4 C4 .
        D4 . E4 . G4 . E4 D4
        E4 . G4 . E4 . D4 .
        G4 . E4 D4 E4 . D4 C4
        A3 . C4 . D4 . A3 .
        C4 . A3 G3 A3 . C4 A3
        G3 . D4 . G3 . . .]],
    },
    drum = {
      A = [[
        D . k k D . k .
        D . k . D k c .
        D . k k D . k .
        D . k . D D k k
        D . k k D . k .
        D . k . D k c .
        D . k k D . k .
        D D k k D . c c]],
      B = [[
        D . k k D . k .
        D . k . D k c .
        D . k k D . k .
        D . k . D D k k
        D . k k D . k .
        D . k . D k c .
        D . k k D k D k
        D D k k D D c .]],
    },
  }
  TOWN.drum.A2 = TOWN.drum.A

  -- battle: E In (E F A B C), 16th-note steps
  local BOSS = {
    ost = {
      A = [[
        E3 . E3 E4 . E3 F3 . E3 . E3 B3 . E3 C4 B3
        E3 . E3 E4 . E3 F3 . E3 . A3 . F3 . E3 .
        E3 . E3 E4 . E3 F3 . E3 . E3 B3 . E3 C4 B3
        E3 . E3 E4 . E3 F3 . A3 . B3 . C4 . B3 .
        E3 . E3 E4 . E3 F3 . E3 . E3 B3 . E3 C4 B3
        E3 . E3 E4 . E3 F3 . E3 . A3 . F3 . E3 .
        F3 . F3 F4 . F3 A3 . F3 . F3 C4 . F3 B3 A3
        E3 . E3 E4 . E3 F3 . E3 B3 C4 B3 A3 F3 E3 .]],
      B = [[
        A2 . A2 A3 . A2 B2 . A2 . A2 E3 . A2 F3 E3
        A2 . A2 A3 . A2 B2 . A2 . C3 . B2 . A2 .
        A2 . A2 A3 . A2 B2 . A2 . A2 E3 . A2 F3 E3
        A2 . A2 A3 . A2 B2 . C3 . E3 . F3 . E3 .
        F2 . F2 F3 . F2 A2 . F2 . F2 C3 . F2 E3 C3
        F2 . F2 F3 . F2 A2 . F2 . B2 . A2 . F2 .
        E2 . E2 E3 . E2 F2 . E2 . E2 B2 . E2 C3 B2
        E2 . E2 E3 . E2 F2 . B2 . C3 . E3 . F3 .]],
    },
    lead = {
      A = [[
        B4 - - - - - - - - - - - C5 - B4 -
        A4 - - - - - - - F4 - - - E4 - - -
        E5 - - - - - - - F5 - - - E5 - C5 -
        B4 - - - - - - - - - - - . . . .
        B4 - - - C5 - - - E5 - - - F5 - - -
        E5 - - - - - - - C5 - B4 - A4 - - -
        F4 - - - - - - - E4 - F4 - A4 - B4 -
        E4 - - - - - - - - - - - . . . .]],
      B = [[
        C5 - - - - - - - B4 - - - A4 - - -
        F4 - - - - - - - E4 - - - - - - -
        C5 - - - B4 - - - C5 - - - E5 - - -
        F5 - - - - - - - E5 - - - . . . .
        A5 - - - - - - - F5 - - - E5 - - -
        C5 - - - - - - - B4 - - - A4 - - -
        B4 - - - C5 - - - B4 - - - F4 - - -
        E4 - - - - - - - - - - - . . . .]],
    },
    drum = {
      A = [[
        D . . D . . D . D . k . D k D k
        D . . D . . D . D . k . D . k k
        D . . D . . D . D . k . D k D k
        D . . D . . D . D D k k D D k k
        D . . D . . D . D . k . D k D k
        D . . D . . D . D . k . D . k k
        D . . D . . D . D . k . D k D k
        D . k . D . k . D D D D D D D D]],
      B = [[
        D . c D . . D . D . k . D k D k
        D . . D . . D . D . k . D . k k
        D . c D . . D . D . k . D k D k
        D . . D . . D . D D k k D D k k
        D . c D . . D . D . k . D k D k
        D . . D . . D . D . k . D . k k
        D . c D . . D . D . k . D k D k
        D . k . D . k k D D k k D D D D]],
    },
  }

  local IN = { [4] = 3, [11] = 10 }
  local KIT = {
    field = { d = { "taiko", "D2", 10 }, k = { "rim", "D5", 7 } },
    night = { d = { "furin", "A5", 6 }, k = false },
    snow  = { d = { "wind", "E4", 7 }, k = { "furin", "D6", 5 } },
    title = { d = { "taiko", "D2", 14 }, k = { "kane", "E6", 7 } },
    town  = { D = { "taiko", "G2", 10 }, k = { "rim", "D5", 8 }, c = { "kane", "E6", 6 } },
    boss  = { D = { "taiko", "E2", 12 }, k = { "rim", "E5", 9 }, c = { "kane", "F6", 7 } },
    oni   = { D = { "taiko", "E2", 10 }, k = { "rim", "E5", 6 }, c = { "bonsho", "E3", 9 } },
    jingle = { T = { "taiko", "D2", 13 }, b = { "furin", "D6", 10 } },
  }
  local YO_D, YO_G, IN_E = { 2, 4, 7, 9, 11 }, { 7, 9, 0, 2, 4 }, { 4, 5, 9, 11, 0 }

  local TRACKS = {
    field = { spf = 16, order = { "A", "B", "A2", "B2" }, kit = KIT.field, scale = YO_D, voices = {
      { ch = 0, pat = THEME.koto, inst = "koto", vol = 9, jit = 1 },
      { ch = 1, pat = THEME.lead, inst = "shaku", vol = 10 },
      { ch = 2, pat = THEME.low, inst = "bass", vol = 12 } } },
    night = { spf = 20, order = { "A2", "B", "A2", "B2" }, kit = KIT.night, scale = YO_D, mode = IN, voices = {
      { ch = 0, pat = THEME.koto, inst = "koto", vol = 9, spd = -2, jit = 1 },
      { ch = 1, pat = THEME.lead, inst = "shaku", vol = 8 },
      { ch = 2, pat = THEME.low, inst = "bass", vol = 10 } } },
    snow = { spf = 18, order = { "A2", "B2", "A2", "B" }, kit = KIT.snow, scale = YO_D, voices = {
      { ch = 0, pat = THEME.koto, inst = "furin", vol = 7, oct = 1, jit = 1 },
      { ch = 1, pat = THEME.lead, inst = "shaku", vol = 8 },
      { ch = 2, pat = THEME.low, inst = "bass", vol = 10 } } },
    title = { spf = 18, order = { "A", "B" }, kit = KIT.title, scale = YO_D, mode = IN, voices = {
      { ch = 0, pat = THEME.koto, inst = "koto", vol = 10, spd = -2 },
      { ch = 1, pat = THEME.lead, inst = "shaku", vol = 11 },
      { ch = 2, pat = THEME.low, inst = "bass", vol = 12 } } },
    town = { spf = 13, order = { "A", "B", "A2", "B" }, kit = KIT.town, scale = YO_G, voices = {
      { ch = 0, pat = TOWN.sham, inst = "sham", vol = 12, jit = 1 },
      { ch = 1, pat = TOWN.fue, inst = "fue", vol = 9 },
      { ch = 2, pat = TOWN.drum, vol = 1 } } },
    boss = { spf = 7, order = { "A", "B" }, kit = KIT.boss, scale = IN_E, voices = {
      { ch = 0, pat = BOSS.ost, inst = "sham", vol = 12, jit = 1 },
      { ch = 1, pat = BOSS.lead, inst = "fue", vol = 10 },
      { ch = 2, pat = BOSS.drum, vol = 1 } } },
    oni = { spf = 10, order = { "A", "B" }, kit = KIT.oni, scale = IN_E, voices = {
      { ch = 0, pat = BOSS.ost, inst = "sham", vol = 10, jit = 1 },
      { ch = 2, pat = BOSS.drum, vol = 1 } } },
  }

  -- jingles: one part "J", channels 0-2 while the music waits
  local JINGLES = {
    complete = { spf = 6, pad = true, order = { "J" }, kit = KIT.jingle, scale = YO_D, voices = {
      { ch = 0, inst = "koto", vol = 13, pat = { J = "A4 . D5 . E5 . A5 . . . . . D6 . . . . . . . . . . ." } },
      { ch = 1, inst = "koto", vol = 10, pat = { J = "D4 . . . A4 . . . . . . . A5 . . . . . . . . . . ." } },
      { ch = 2, vol = 1, pat = { J = ". . . . . . . . . . . . b . . . . . . . . . . ." } } } },
    tower = { spf = 3, pad = true, order = { "J" }, kit = KIT.jingle, scale = YO_D, voices = {
      { ch = 0, inst = "koto", vol = 12, pat = { J = "D4 E4 G4 A4 B4 D5 E5 G5 A5 B5 D6" } },
      { ch = 1, inst = "shaku", vol = 11, pat = { J = ". . . . . . . . . . . A5 - - - - - - - - - - - - - - - D6 - - - - - - - - - - - - - - - - - - - - - - - . . . ." } },
      { ch = 2, vol = 1, pat = { J = ". . . . . . . . . . . T . . . . b" } } } },
    victory = { spf = 8, pad = true, order = { "J" }, kit = KIT.jingle, scale = YO_D, voices = {
      { ch = 0, inst = "koto", vol = 12, pat = { J = "D4 A4 D5 . G4 D5 G5 . A4 E5 A5 . B4 . A4 . D4 A4 D5 A5 D6 . . . . . . . . . . ." } },
      { ch = 1, inst = "fue", vol = 12, pat = { J = "D5 - E5 - G5 - - - A5 - - - B5 - A5 - D6 - - - - - - - - - - - - - . ." } },
      { ch = 2, vol = 1, pat = { J = "T . . . T . . . T . . . T . T T T . . . . . . . b . . . . . . ." } } } },
  }

  -- --------------------------------------------------------------------------
  -- data -> RAM
  -- --------------------------------------------------------------------------
  local function err(s) Audio.errors[#Audio.errors + 1] = s end

  local function env(name, s, pad, signed)
    local out, last = {}, 0
    s = (s or ""):gsub("%s", "")
    if #s > 30 then err(name .. ": envelope longer than 30 ticks") end
    for t = 0, 29 do
      local c = s:sub(t + 1, t + 1)
      local v
      if c == "" then v = pad or last
      elseif signed and c:match("%u") then v = 64 - c:byte()
      else v = tonumber(c, 16) or 0 end
      out[t], last = v, v
    end
    return out
  end

  -- frames until the volume envelope is silent for good (looping = nil)
  local function frames(d, V)
    if d.loop and d.loop.v then return nil end
    local last = -1
    for t = 0, 29 do if V[t] > 0 then last = t end end
    local s = d.s or 0
    if s >= 0 then return (last + 1 + s) // (1 + s) end
    return (last + 1) * (1 - s)
  end

  local function pokeSfx(name, d)
    local a = SFX_RAM + d.id * 66
    local W, V, A, P = env(name, d.w), env(name, d.v, 0), env(name, d.a), env(name, d.p, nil, true)
    for t = 0, 29 do
      poke(a + t * 2, (15 - V[t]) | (W[t] << 4))
      poke(a + t * 2 + 1, A[t] | ((P[t] & 15) << 4))
    end
    poke(a + 60, 4 | (d.x and 8 or 0) | (((d.s or 0) & 7) << 4) | (d.r and 128 or 0))
    poke(a + 61, 0)
    local L = d.loop or {}
    for k, key in ipairs({ "w", "v", "a", "p" }) do
      local l = L[key]
      poke(a + 61 + k, l and (l[1] | (l[2] << 4)) or 0)
    end
    d.len = frames(d, V)
  end

  local NOTE = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
  local function noteNum(tok)
    local l, acc, o = tok:match("^([A-G])([#b]?)(%d)")
    if not l then return nil end
    return tonumber(o) * 12 + NOTE[l] + (acc == "#" and 1 or acc == "b" and -1 or 0)
  end
  local ACC = { ["!"] = 2, ["?"] = -3 }

  local function inScale(scale, n)
    for _, pc in ipairs(scale) do if n % 12 == pc then return true end end
    return false
  end

  -- track definition -> { spf, n, voices = { { ch, ev = { [step] = event } } } }
  local function compile(name, def)
    local plen, toks = {}, {}
    for vi, v in ipairs(def.voices) do
      toks[vi] = {}
      for _, part in ipairs(def.order) do
        local list = {}
        for tok in (v.pat[part] or ""):gmatch("%S+") do list[#list + 1] = tok end
        toks[vi][part] = list
        plen[part] = max(plen[part] or 0, #list)
      end
    end
    local n = 0
    for _, part in ipairs(def.order) do n = n + plen[part] end
    local tr = { name = name, spf = def.spf, n = n, voices = {} }
    for vi, v in ipairs(def.voices) do
      local seq = {}
      for _, part in ipairs(def.order) do
        local list = toks[vi][part]
        if not def.pad and #list > 0 and #list ~= plen[part] then
          err(fmt("%s voice %d part %s: %d steps, expected %d", name, vi, part, #list, plen[part]))
        end
        for i = 1, plen[part] do seq[#seq + 1] = list[i] or "." end
      end
      local inst = v.inst and INST[v.inst]
      local rel = inst and inst.rel and INST[inst.rel]
      local ev = {}
      for i = 1, n do
        local tok = seq[i]
        local nn = noteNum(tok)
        local acc = ACC[tok:sub(-1)] or 0
        if nn then
          if def.scale and not inScale(def.scale, nn) then err(fmt("%s voice %d step %d: %s not in scale", name, vi, i, tok)) end
          if def.mode and def.mode[nn % 12] then nn = nn - nn % 12 + def.mode[nn % 12] end
          if inst then
            ev[i - 1] = { inst = inst.id, note = nn + 12 * (v.oct or 0), vol = v.vol + acc, spd = v.spd or inst.s, jit = v.jit, rel = rel }
          else
            err(fmt("%s voice %d: note without instrument", name, vi))
          end
        elseif tok ~= "." and tok ~= "-" then
          local k = def.kit and def.kit[tok:sub(1, 1)]
          if k == nil then err(fmt("%s voice %d step %d: bad token %s", name, vi, i, tok))
          elseif k then
            local ki = INST[k[1]]
            ev[i - 1] = { inst = ki.id, note = noteNum(k[2]), vol = k[3] + acc, spd = ki.s }
          end
        end
      end
      -- sustained voices: a rest after a note plays the release instrument
      if rel then
        for i = 1, n do
          if seq[i] == "." then
            local j = i
            repeat j = (j - 2) % n + 1 until seq[j] ~= "-" or j == i
            local e = ev[j - 1]
            if e and noteNum(seq[j]) then ev[i - 1] = { inst = rel.id, note = e.note, vol = e.vol, spd = rel.s } end
          end
        end
      end
      tr.voices[#tr.voices + 1] = { ch = v.ch, ev = ev }
    end
    return tr
  end

  local SONGS, JING = {}, {}

  function Audio.init()
    Audio.errors = {}
    for i = 0, 15 do
      local f = WAVES[i]
      for k = 0, 15 do poke(WAVE_RAM + i * 16 + k, f(2 * k) | (f(2 * k + 1) << 4)) end
    end
    for name, d in pairs(INST) do pokeSfx(name, d) end
    for name, d in pairs(SFXD) do pokeSfx(name, d) end
    for name, def in pairs(TRACKS) do SONGS[name] = compile(name, def) end
    for name, def in pairs(JINGLES) do JING[name] = compile(name, def) end
    Audio.ready = true
    local s = pmem(255)
    if s >> 8 == 0xA0D then Audio.setLevels(s & 3, (s >> 2) & 3) else Audio.setLevels(3, 3) end
  end

  function Audio.setLevels(m, s)
    Audio.music, Audio.sfx = m, s
    Music.vol, Sfx.vol = LEVEL[m], LEVEL[s]
    pmem(255, (0xA0D << 8) | m | (s << 2))
    if m == 0 and not Sfx.jpl then for ch = 0, 2 do sfx(-1, 0, -1, ch) end end
  end

  function Audio.has(name) return SFXD[name] ~= nil or JINGLES[name] ~= nil end
  function Audio.track(name) return SONGS[name] end
  Audio.TRACKS = TRACKS

  -- --------------------------------------------------------------------------
  -- playback
  -- --------------------------------------------------------------------------
  local function silence(c0, c1)
    for ch = c0, c1 do sfx(-1, 0, -1, ch) end
  end

  local function tickPlayer(pl, gain)
    local tr = pl.tr
    if pl.t == 0 then
      for vi, v in ipairs(tr.voices) do
        local e = v.ev[pl.step]
        if e then
          local vol = e.vol
          if e.jit and Music.human then vol = vol + rnd(-e.jit, e.jit) end
          vol = min(15, flr(vol * gain + 0.5))
          if vol > 0 then sfx(e.inst, e.note, -1, v.ch, vol, e.spd) end
          pl.sus[vi] = e.rel and vol > 0 and { e, vol } or nil
        end
      end
      pl.step = pl.step + 1
      if pl.step >= tr.n then
        if pl.loop then pl.step = 0 else pl.done = true end
      end
    end
    pl.t = (pl.t + 1) % tr.spf
  end

  -- end sustained notes softly (track fades out)
  local function release(pl)
    for vi, v in ipairs(pl.tr.voices) do
      local s = pl.sus[vi]
      if s then sfx(s[1].rel.id, s[1].note, -1, v.ch, s[2], s[1].rel.s) end
      pl.sus[vi] = nil
    end
  end

  local function startTrack(name)
    Music.pl = SONGS[name] and { tr = SONGS[name], step = 0, t = 0, loop = true, sus = {} } or nil
    Music.playing = Music.pl and name or nil
    Music.fadeT = 0
    if not Sfx.jpl then silence(0, 2) end
  end

  function Music.play(track)
    if not Audio.ready then Music.cur = track return end
    if track ~= nil and not SONGS[track] then return end
    if track == Music.cur then return end
    Music.cur = track
    if track == nil or track == "boss" or not Music.pl then
      startTrack(track)
    elseif track == Music.playing then
      Music.fadeT = 0
    elseif Music.fadeT == 0 then
      Music.fadeT = FADE
      if not Sfx.jpl then release(Music.pl) end
    end
  end

  function Music.region()
    if Game and Game.state == "finale" then return Music.play("title") end
    local b = Boss and Boss.cur
    if (b and b.alive) or (Shrine and Shrine.trial) then return Music.play("boss") end
    local r = Game and Game.region and REG[Game.region]
    local m = r and r.music or 1
    if (Clock and Clock.isNight()) or m == 4 then Music.play("night")
    elseif Game and Game.safe then Music.play("town")
    elseif m == 5 then Music.play("oni")
    elseif m == 3 then Music.play("snow")
    else Music.play("field") end
  end

  local function startJingle(name)
    Sfx.jpl = { tr = JING[name], step = 0, t = 0, loop = false, tail = 40, name = name, sus = {} }
    silence(0, 2)
  end

  function Music.update()
    if not Audio.ready then return end
    Sfx.t = Sfx.t + 1
    if Sfx.busy > 0 then Sfx.busy = Sfx.busy - 1 end
    local j = Sfx.jpl
    if j then
      if not j.done then tickPlayer(j, Sfx.vol)
      else
        j.tail = j.tail - 1
        if j.tail <= 0 then
          Sfx.jpl = nil
          silence(0, 2)
          local q = table.remove(Sfx.queue, 1)
          if q then startJingle(q) end
        end
      end
    end
    if Music.fadeT > 0 then
      Music.fadeT = Music.fadeT - 1
      if Music.fadeT == 0 then startTrack(Music.cur) end
    end
    if Sfx.jpl or not Music.pl or Music.vol <= 0 then return end
    tickPlayer(Music.pl, Music.vol * (Music.fadeT > 0 and Music.fadeT / FADE or 1))
  end

  function Sfx.play(name)
    if not Audio.ready or Sfx.vol <= 0 then return end
    if JING[name] then
      if Sfx.jpl then
        if #Sfx.queue < 2 then Sfx.queue[#Sfx.queue + 1] = name end
      else
        startJingle(name)
      end
      return
    end
    local d = SFXD[name]
    if not d then return end
    if Sfx.busy > 0 and d.pri < Sfx.pri then return end
    if name == Sfx.last and Sfx.t - Sfx.lastT < 3 then return end
    local note = d.note
    if d.jit then note = note + rnd(-d.jit, d.jit) end
    sfx(d.id, note, d.len + 1, 3, max(1, flr(d.vol * Sfx.vol + 0.5)))
    Sfx.busy, Sfx.pri, Sfx.last, Sfx.lastT = d.len, d.pri, name, Sfx.t
  end
end)()

-- ============================================================================
--  61 SAVE - persistent memory (pmem, 256 x 32-bit). Autosaves at dawn, on
--  inn rest, shrine prayer, tower survey and quest completion. Harvested
--  objects regrow on load (not saved).
-- ============================================================================
Save = { MAGIC = 0x4B470002 }
local ITEMIDS
local function itemIds()
  if ITEMIDS then return ITEMIDS end
  ITEMIDS = {}
  for id in pairs(ITEM) do ITEMIDS[#ITEMIDS + 1] = id end
  table.sort(ITEMIDS)
  ITEMIDS.idx = {}
  for i, id in ipairs(ITEMIDS) do ITEMIDS.idx[id] = i end
  return ITEMIDS
end
local function bits(t, list)
  local v = 0
  for i = 1, #list do if t[list[i]] then v = v | (1 << (i - 1)) end end
  return v
end

function Save.exists() return pmem(0) == Save.MAGIC end

function Save.write()
  local ids = itemIds()
  local p = P
  local w = pmem
  w(0, Save.MAGIC)
  w(1, flr(p.x)) w(2, flr(p.y)) w(3, p.hp) w(4, p.maxhp) w(5, p.maxstam) w(6, flr(p.hunger)) w(7, p.ryo)
  w(8, Clock.day) w(9, flr(Clock.t * 100000)) w(10, p.orbs) w(11, p.seeds) w(12, Inv.size)
  w(13, (p.has.kite and 1 or 0) | (p.has.djump and 2 or 0) | (p.has.mirror and 4 or 0))
  w(14, ids.idx[p.weapon or "bokken"] or 0) w(15, p.armor and ids.idx[p.armor] or 0) w(16, p.light and ids.idx[p.light] or 0)
  w(17, flr(p.lightFuel or 0)) w(18, flr(p.spawnX)) w(19, flr(p.spawnY))
  for i = 1, 16 do
    local s = Inv.slots[i]
    w(19 + i, s and (ids.idx[s.id] * 1000 + s.n) or 0)
  end
  for qi, q in ipairs(QUESTS) do
    local s = QS[q.id]
    local v = 0
    if s then v = (s.st == "done" and 2 or 1) + s.step * 4 + math.min(s.count, 255) * 256 end
    w(35 + qi, v)
  end
  local tw, sh = {}, {}
  for _, t in ipairs(TOWERS) do tw[#tw + 1] = t.id end
  w(56, bits(Quest.towersOn, tw))
  for _, s in ipairs(SHRINES) do sh[#sh + 1] = s.id end
  w(57, bits(Shrine.done, sh))
  w(58, bits(Boss.defeated, { "jorogumo", "tengulord", "orochi", "shuten" }))
  w(59, bits(World.found, KODAMA))
  w(61, bits(World.opened, CHESTS))
  local tq = 0
  for qi, q in ipairs(QUESTS) do if q.id == Quest.tracked then tq = qi end end
  w(62, tq)
  for k = 0, 52 do
    local v = 0
    for b = 0, 31 do if MapUI.seen[k * 32 + b] then v = v | (1 << b) end end
    w(70 + k, v)
  end
end

function Save.read()
  if not Save.exists() then return false end
  local ids = itemIds()
  local r = pmem
  Player.new(r(1), r(2))
  local p = P
  p.hp, p.maxhp, p.maxstam = r(3), r(4), r(5)
  p.stam = p.maxstam
  p.hunger, p.ryo = r(6), r(7)
  Clock.day, Clock.t = r(8), r(9) / 100000
  p.orbs, p.seeds = r(10), r(11)
  Inv.reset()
  Inv.size = math.max(10, r(12))
  local ab = r(13)
  p.has.kite, p.has.djump, p.has.mirror = (ab & 1) ~= 0, (ab & 2) ~= 0, (ab & 4) ~= 0
  p.weapon = ids[r(14)] or "bokken"
  p.armor = r(15) > 0 and ids[r(15)] or nil
  p.light = r(16) > 0 and ids[r(16)] or nil
  p.lightFuel = r(17)
  p.spawnX, p.spawnY = r(18), r(19)
  for i = 1, 16 do
    local v = r(19 + i)
    if v > 0 then Inv.slots[i] = { id = ids[v // 1000], n = v % 1000 } end
  end
  Quest.reset()
  for qi, q in ipairs(QUESTS) do
    local v = r(35 + qi)
    if v > 0 then QS[q.id] = { st = (v & 3) == 2 and "done" or "active", step = (v >> 2) & 63, count = (v >> 8) & 255 } end
  end
  Quest.towersOn = {}
  local tw = r(56)
  for _, t in ipairs(TOWERS) do if (tw & (1 << (t.id - 1))) ~= 0 then Quest.towersOn[t.id] = true end end
  Shrine.done = {}
  local sh = r(57)
  for _, s in ipairs(SHRINES) do if (sh & (1 << (s.id - 1))) ~= 0 then Shrine.done[s.id] = true end end
  local bs = r(58)
  for i, id in ipairs({ "jorogumo", "tengulord", "orochi", "shuten" }) do Boss.defeated[id] = (bs & (1 << (i - 1))) ~= 0 or nil end
  local ko = r(59)
  for i, ci in ipairs(KODAMA) do
    if (ko & (1 << (i - 1))) ~= 0 then World.found[ci] = true World.setObj(ci, 0) end
  end
  local ch = r(61)
  for i, ci in ipairs(CHESTS) do
    if (ch & (1 << (i - 1))) ~= 0 then World.opened[ci] = true World.setObj(ci, O_CHESTO) end
  end
  local tq = r(62)
  Quest.tracked = tq > 0 and QUESTS[tq] and QUESTS[tq].id or nil
  MapUI.seen = {}
  for k = 0, 52 do
    local v = r(70 + k)
    for b = 0, 31 do if (v & (1 << b)) ~= 0 then MapUI.seen[k * 32 + b] = true end end
  end
  return true
end

-- ============================================================================
--  70 GAME - states (title / play / dead / finale), the frame pipeline,
--  camera follow, weather, sleeping, fast travel, death and new game.
-- ============================================================================
Game = { state = "title", safe = false, region = nil, titleSel = 1, fade = 0 }
local WEATHER = {}

function Game.boot()
  Boot.all()
  FX.init()
  NPC.spawnAll()
  Game.state = "title"
  Game.titleSel = Save.exists() and 1 or 2
  Cam.x, Cam.y = TOWERS[1].x, TOWERS[1].y + 30
  Cam.z = math.max(0, groundAt(Cam.x, Cam.y))
  Clock.t = 0.62
  Music.play("title")
end

function Game.newGame()
  Player.new(POI.start.x, POI.start.y)
  Inv.reset()
  Inv.add("onigiri", 2)
  Inv.add("berries", 3)
  P.weapon = "bokken"
  P.spawnX, P.spawnY = POI.start.x, POI.start.y
  Quest.reset()
  Clock.t, Clock.day, Clock.total = 0.06, 1, 0
  MapUI.seen = {}
  Game.enterPlay()
  Quest.start("mq1", true)
  local q = QBYID.mq1
  Dialog.lines("Sensei Hayate", q.intro, function()
    UI.banner("The Way of the Shinobi", "Craft a torch: TAB opens the crafting menu")
  end, NPC.find("sensei"))
end

function Game.continue()
  if not Save.read() then Game.newGame() return end
  Game.enterPlay()
  UI.banner("Welcome back, Kage", "Day " .. Clock.day)
  NPC.spawnCat()
end

function Game.enterPlay()
  Game.state = "play"
  Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
  Cam.a, Cam.ta = math.pi / 4, math.pi / 4
  Game.region = nil
  NPC.spawnCat()
  Music.region()
end

function Game.toTitle()
  reset()
end

function Game.save() if P and Game.state == "play" then Save.write() end end
function Game.autosave()
  if P and Game.state == "play" and P.state ~= "dead" then
    Save.write()
    Game.savedT = 90
  end
end

function Game.onDeath(why)
  Game.state = "dead"
  Game.deadT = 0
  Game.deathWhy = why
end

function Game.finale()
  Game.state = "finale"
  Game.finT = 0
  Music.play("title")
end

function Game.safeToSleep()
  for _, e in ipairs(ENTS) do
    if e.alive and e.hostile and dist(e.x, e.y, P.x, P.y) < 100 then return false end
  end
  return true
end

-- sleep until morning (inn = full heal, bedroll = partial)
function Game.sleep(inn)
  Game.fade = 60
  Game.fadeDo = function()
    if Clock.t > 0.3 then Clock.day = Clock.day + 1 end
    Clock.t = 0.03
    P.stam = P.maxstam
    P.exhausted = false
    if inn then
      P.hp = P.maxhp
      P.spawnX, P.spawnY = P.x, P.y
    else
      Player.heal(P.maxhp // 2)
      P.hunger = math.max(0, P.hunger - 15)
    end
    for _, e in ipairs(ENTS) do if e.alive and e.kind == "enemy" and not e.camp then e.alive = false end end
    UI.banner("Day " .. Clock.day, inn and "You feel fully rested. Game saved." or "You slept rough...")
    Game.autosave()
    Music.region()
  end
end

function Game.travel(t)
  Game.fade = 50
  Game.fadeDo = function()
    P.x, P.y = t.x, t.y + 22
    P.z = groundAt(P.x, P.y)
    P.state = "ground"
    P.vx, P.vy, P.vz = 0, 0, 0
    Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
    for _, e in ipairs(ENTS) do
      if e.alive and e.kind == "enemy" and not e.camp and not e.boss then e.alive = false end
      if e.kind == "drop" or e.kind == "proj" then e.alive = false end
    end
    UI.toast("Travelled to " .. t.name)
  end
end

-- ---------------------------------------------------------------------------
-- per-frame helpers
-- ---------------------------------------------------------------------------
local function regionTick()
  if Frame % 20 ~= 0 then return end
  local p = P
  local cx, cy = clamp(flr(p.x / 8), 0, 239), clamp(flr(p.y / 8), 0, 111)
  local r = WR[cidx(cx, cy)]
  local safe = false
  for _, t in ipairs(TOWNS) do
    if dist(p.x, p.y, t.x, t.y) < t.r then safe = true Game.town = t.name end
  end
  if safe ~= Game.safe then
    Game.safe = safe
    if safe then UI.region(Game.town) end
    Music.region()
  end
  if r ~= Game.region then
    Game.region = r
    if not safe then UI.region(REG[r].name) end
    Music.region()
  end
  MapUI.reveal(p.x, p.y, 7)
  -- night music swap
  local night = Clock.isNight()
  if night ~= Game.wasNight then
    Game.wasNight = night
    Music.region()
  end
end

local function lightTick()
  local p = P
  if p.light and ITEM[p.light] and ITEM[p.light].fuel < 99999 and not Clock.isDay() then
    p.lightFuel = (p.lightFuel or 0) - 1
    if p.lightFuel <= 0 then
      UI.toast("Your " .. ITEM[p.light].n .. " burned out!")
      p.light = nil
    end
  end
end

local function camera()
  local p = P
  local tx, ty = p.x, p.y
  Cam.x = Cam.x + (tx - Cam.x) * 0.14
  Cam.y = Cam.y + (ty - Cam.y) * 0.14
  local tz = p.z
  if p.state == "air" or p.state == "plunge" then tz = math.min(p.z, groundAt(p.x, p.y) + 20) end
  Cam.z = Cam.z + (tz - Cam.z) * 0.08
  local d = angdiff(Cam.a, Cam.ta)
  if math.abs(d) < 0.01 then Cam.a = Cam.ta else Cam.a = Cam.a + d * 0.16 end
  Cam.sx = (rnd() - 0.5) * FX.shakeA
  Cam.sy = (rnd() - 0.5) * FX.shakeA
end

function Game.darkness()
  local t = Clock.t
  if t < NIGHT - 0.05 or t > DAWN then return 0 end
  if t < NIGHT then return (t - (NIGHT - 0.05)) / 0.05 end
  if t > DAWN - 0.03 then return (DAWN - t) / 0.03 end
  return 1
end

-- static objects in visible chunks
local function drawObjects()
  local f = Frame
  for _, k in ipairs(Render.visChunks) do
    local l = OLIST[k]
    if l then
      for ci in pairs(l) do
        local o = WO[ci]
        if o > 0 then
          local d = OBJ[o]
          local name = d.spr or (d.anim and d.anim[1 + (f // 10 + ci) % #d.anim])
          local r = name and SPR[name]
          if r then
            local ox, oy = objPos(ci)
            local z = math.max(WH[ci], 0)
            if (WF[ci] & F_ROOF) ~= 0 then z = groundAt(ox, oy) end
            if d.bob then z = z + math.sin((f + ci) / 12) * 1.5 + 2 end
            if d.shadow then Render.ground(SPR.shadow, ox, oy, z + 0.3, d.shadow) end
            local flip = (ci % 2 == 0) and d.r == nil and d.hand ~= nil
            local ch = World.chop[ci]
            if ch then
              -- chopped: leans further with each hit, wobbles right after one
              local lean = 0.24 * (World.hits[ci] or 0) / ch.n
              if ch.t > 0 then lean = lean + math.sin(ch.t * 1.3) * ch.t * 0.008 end
              Render.billRot(r, ox, oy, z, flip, d.pm, 1, World.chopSide(ch) * lean, 1.5)
            else
              Render.bill(r, ox, oy, z, flip, d.pm)
            end
          end
        end
      end
    end
  end
  Render.setPM(nil)
end

local function weather()
  local reg = Game.region and REG[Game.region]
  local biome = reg and reg.biome
  local kind = nil
  if Clock.rain > 0.2 then kind = (biome == "snow") and "snow" or "rain" end
  if not kind and biome == "sakura" then kind = "petal" end
  if not kind and biome == "snow" then kind = "snow" end
  if not kind and Clock.isNight() and (biome == "plains" or biome == "marsh" or biome == "sakura") then kind = "firefly" end
  local want = 0
  if kind == "rain" then want = flr(70 * Clock.rain) elseif kind == "snow" then want = 45 elseif kind == "petal" then want = 14 elseif kind == "firefly" then want = 16 end
  while #WEATHER < want do
    WEATHER[#WEATHER + 1] = { x = rnd(0, 239), y = rnd(-10, 135), s = rndf(0.5, 1.5), k = kind, ph = rnd() * 6 }
  end
  while #WEATHER > want do table.remove(WEATHER) end
  for _, w in ipairs(WEATHER) do
    w.k = kind
    if kind == "rain" then
      w.x, w.y = w.x - 1.2, w.y + 5 * w.s
      line(w.x, w.y, w.x + 2, w.y - 5, C_GRAY)
    elseif kind == "snow" then
      w.x, w.y = w.x + math.sin(Frame / 30 + w.ph) * 0.4 - 0.2, w.y + 0.5 * w.s
      pix(w.x, w.y, C_WHITE)
    elseif kind == "petal" then
      w.x, w.y = w.x + math.sin(Frame / 25 + w.ph) * 0.6 + 0.3, w.y + 0.35 * w.s
      pix(w.x, w.y, C_PINK)
      pix(w.x + 1, w.y, C_WHITE)
    elseif kind == "firefly" then
      w.x, w.y = w.x + math.sin(Frame / 40 + w.ph) * 0.4, w.y + math.cos(Frame / 33 + w.ph) * 0.3
      if (Frame // 20 + flr(w.ph * 3)) % 3 ~= 0 then pix(w.x, w.y, C_GOLD) end
    end
    if w.y > 136 then w.y = rnd(-8, 0) w.x = rnd(0, 260) end
    if w.x < -4 then w.x = 243 elseif w.x > 244 then w.x = -3 end
    if w.y < -12 then w.y = 135 end
  end
end

-- the world frame (shared by title and play)
local function drawWorld(withPlayer)
  vbank(0)
  -- menus and the finale dim the world through its palette (bank 0 only)
  local r, g, b = Clock.tint()
  if Menu.cur or Game.state == "finale" then r, g, b = r * 0.38, g * 0.38, b * 0.45 end
  Pal.setTint(r, g, b)
  cls(C_NIGHT)
  Render.begin()
  Gfx.animTiles(Frame)
  Render.world()
  drawObjects()
  Shrine.drawOrbs()
  if P then Ent.drawAll(P.x, P.y) end
  FX.drawWorld()
  if withPlayer and P then Player.draw() end
  FX.drawTop()
  weather()
  Light.collect()
  local a = Game.darkness()
  if P and P.has.mirror then a = math.min(a, 0.7) end
  Light.overlay(a)
end

-- ---------------------------------------------------------------------------
-- title screen
-- ---------------------------------------------------------------------------
local function titleTick()
  Clock.t = 0.6 + math.sin(Frame / 600) * 0.02
  Cam.ta = Cam.ta + 0.004
  Cam.a = Cam.ta
  local t = TOWERS[1]
  Cam.x, Cam.y = t.x, t.y
  Cam.z = math.max(0, groundAt(t.x, t.y)) + 10
  drawWorld(false)
  vbank(1)
  cls(0)
  -- logo
  local y = 22
  print("KAGE", 120 - 50 + 2, y + 2, C_NIGHT, false, 4)
  print("KAGE", 120 - 50, y, C_RED, false, 4)
  print("KAGE", 120 - 50, y - 1, C_WHITE, false, 4)
  local sub = "Ninja of the Wind"
  local w = textw(sub)
  tprint(sub, 120 - w / 2, y + 26, C_GOLD)
  local opts = { "Continue", "New Game", "Controls" }
  local has = Save.exists()
  for i, o in ipairs(opts) do
    local yy = 76 + (i - 1) * 12
    local dim = (i == 1 and not has)
    local col = dim and C_GRAY or (i == Game.titleSel and C_GOLD or C_WHITE)
    local ow = textw(o)
    if i == Game.titleSel then
      rect(120 - ow / 2 - 6, yy - 2, ow + 12, 10, C_NIGHT)
      print(">", 120 - ow / 2 - 5, yy, C_RED)
    end
    tprint(o, 120 - ow / 2, yy, col)
  end
  local hint = "Z select   arrows move"
  local hw = textw(hint, true)
  rect(120 - hw // 2 - 5, 123, hw + 10, 10, C_NIGHT)
  print(hint, 120 - hw // 2, 125, C_GRAY, false, 1, true)
  if Game.help then
    panel(20, 14, 200, 110)
    local lines = { "Arrows  move          SHIFT/C  sprint", "X  jump (air: hold to glide, water: leap out)", "Z  katana, chop, mine (air: plunge)",
      "A  talk / pick up / open / cook", "S  throw shuriken    Q/E  rotate view", "Push into a wall to climb, X to leap",
      "TAB  bag + crafting   M  map   J  quests", "1-0  use hotbar slot", "", "Survive: eat, carry light at night,", "climb pagodas, recover the Treasures.", "", "Z  close" }
    for i, l in ipairs(lines) do print(l, 28, 20 + (i - 1) * 8, C_WHITE, false, 1, true) end
    if In.p.atk or In.p.jump or In.p.ok then Game.help = false Sfx.play("close") end
    return
  end
  if In.p.up then Game.titleSel = (Game.titleSel - 2) % 3 + 1 Sfx.play("menu") end
  if In.p.down then Game.titleSel = Game.titleSel % 3 + 1 Sfx.play("menu") end
  if In.p.atk or In.p.ok or In.p.use then
    Sfx.play("select")
    if Game.titleSel == 1 and has then Game.continue()
    elseif Game.titleSel == 2 then Game.newGame()
    elseif Game.titleSel == 3 then Game.help = true end
  end
end

-- ---------------------------------------------------------------------------
-- main frame
-- ---------------------------------------------------------------------------
function Game.tick()
  In.poll()
  Frame = Frame + 1
  Music.update()
  if Game.state == "title" then
    titleTick()
    return
  end
  local p = P
  -- input routing
  if Game.fade > 0 then
    Game.fade = Game.fade - 1
    if Game.fade == 30 and Game.fadeDo then Game.fadeDo() Game.fadeDo = nil end
  elseif Game.state == "dead" then
    Game.deadT = Game.deadT + 1
    if Game.deadT > 90 and (In.p.atk or In.p.ok or In.p.use) then
      local lost = flr(p.ryo / 4)
      p.ryo = p.ryo - lost
      Player.respawn()
      Game.state = "play"
      UI.toast(lost > 0 and ("You lost " .. lost .. " ryo") or "You awaken...")
      for _, e in ipairs(ENTS) do if e.alive and e.kind == "enemy" and not e.camp then e.alive = false end end
      Music.region()
    end
  elseif Game.state == "finale" then
    Game.finT = Game.finT + 1
    if Game.finT > 240 and (In.p.atk or In.p.ok) then Game.state = "play" Music.region() end
  elseif Dialog.active then
    Dialog.update()
  elseif Menu.cur then
    Menu.update()
  elseif In.p.menu then
    Menu.open("pause", { tab = 1 })
  elseif In.p.map then
    Menu.open("pause", { tab = 3 })
  elseif In.p.quest then
    Menu.open("pause", { tab = 4 })
  end
  local paused = Dialog.active or Menu.cur or Game.fade > 0 or Game.state == "finale"
  if not paused then
    if FX.stop > 0 then
      FX.stop = FX.stop - 1
    else
      Clock.update()
      Player.update()
      if p.webbed and p.webbed > 0 then
        p.webbed = p.webbed - 1
        p.vx, p.vy = p.vx * 0.5, p.vy * 0.5
      end
      Ent.updateAll(p.x, p.y)
      Enemy.director()
      Boss.update()
      Shrine.update()
      World.update()
      Clock.survival()
      lightTick()
      regionTick()
    end
    FX.update()
  end
  camera()
  drawWorld(true)
  -- overlay bank
  vbank(1)
  cls(0)
  if Game.state == "play" then
    if not Menu.cur then UI.drawHUD() end
    Menu.draw()
    Dialog.draw()
  elseif Game.state == "dead" then
    local a = math.min(1, Game.deadT / 60)
    for y = 0, 135, a > 0.5 and 1 or 2 do line(0, y, 239, y, C_NIGHT) end
    local s = "You have fallen"
    print(s, 120 - textw(s, false) * 1, 50, C_RED, false, 2)
    local why = ({ dark = "The Yami took you in the dark.", cold = "You froze on the mountain.", starve = "You starved.",
      fall = "A fatal fall.", drown = "You drowned.", lava = "Burned by lava." })[Game.deathWhy] or "Defeated in battle."
    tprint(why, 120 - textw(why) / 2, 70, C_WHITE)
    if Game.deadT > 90 then tprint("Z: rise again", 120 - textw("Z: rise again") / 2, 90, C_GOLD) end
  elseif Game.state == "finale" then
    local lines = { "Shuten-doji is defeated.", "", "The Three Sacred Treasures shine", "once more over the realm,",
      "and dawn returns to the land.", "", "Thank you for playing KAGE!", "", "The world remains yours to roam." }
    for i, l in ipairs(lines) do
      local yy = 20 + (i - 1) * 10
      if Game.finT > i * 20 then tprint(l, 120 - textw(l) / 2, yy, i == 7 and C_GOLD or C_WHITE) end
    end
    if Game.finT > 240 then tprint("Z: continue", 120 - textw("Z: continue") / 2, 118, C_GRAY) end
  end
  if Game.savedT and Game.savedT > 0 then
    Game.savedT = Game.savedT - 1
    tprint("Saved", 204, 116, C_LIME, true)
  end
  -- fade
  if Game.fade > 0 then
    local f = Game.fade > 30 and (60 - Game.fade) or Game.fade
    local step = f > 22 and 1 or (f > 12 and 2 or 4)
    for y = 0, 135, step do line(0, y, 239, y, C_NIGHT) end
  end
  vbank(0)
end

-- ============================================================================
--  80 MAIN - TIC-80 entry points (must stay the last module)
-- ============================================================================
function BOOT()
  Game.boot()
end

function TIC()
  Game.tick()
end

-- <PALETTE>
-- 000:0d0b1425213b3d43773f7cbf8288a01f4d3a3e8c439fd25c5c3a2d9b6541d6a76cf3e3c3fbf8f0cc3340f39cb6f4c94e
-- 001:0d0b1425213b3d43773f7cbf8288a01f4d3a3e8c439fd25c5c3a2d9b6541d6a76cf3e3c3fbf8f0cc3340f39cb6f4c94e
-- </PALETTE>

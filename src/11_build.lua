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

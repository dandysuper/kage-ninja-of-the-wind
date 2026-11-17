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

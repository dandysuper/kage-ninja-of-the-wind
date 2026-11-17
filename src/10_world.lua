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

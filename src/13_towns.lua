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

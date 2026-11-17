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

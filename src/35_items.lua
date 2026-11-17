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

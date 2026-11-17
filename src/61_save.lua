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

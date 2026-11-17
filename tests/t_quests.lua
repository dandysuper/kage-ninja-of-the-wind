-- ============================================================================
--  t_quests: scripted playthrough of the whole main story and every side
--  quest on the real game loop. The ninja is kept alive (i-frames, food,
--  stamina, daylight) so the boss AIs can run for a while against him; each
--  boss is then finished with Enemy.hurt from the player's position. Checks
--  spawn conditions, the sword's vertical reach on each boss, quest steps,
--  rewards, music changes and the finale. A coroutine yields once per frame.
-- ============================================================================
local co
local god = true

local function tick(n)
  for _ = 1, n or 1 do coroutine.yield() end
end

local function warp(x, y)
  P.x, P.y = x, y
  P.z = groundAt(x, y)
  P.state = "ground"
  P.vx, P.vy, P.vz = 0, 0, 0
  Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
end

-- nearest dry cell centre to (x, y) within r cells
local function landNear(x, y, r)
  local cx, cy = flr(x / 8), flr(y / 8)
  local best, bx, by = 1e9, x, y
  for yy = cy - r, cy + r do
    for xx = cx - r, cx + r do
      if inmap(xx, yy) and WH[cidx(xx, yy)] >= 0 and (WF[cidx(xx, yy)] & F_WATER) == 0 then
        local d = (xx - cx) ^ 2 + (yy - cy) ^ 2
        if d < best then best, bx, by = d, xx * 8 + 4, yy * 8 + 4 end
      end
    end
  end
  return bx, by
end

local function closeDialogs(maxF)
  local t = 0
  while (Dialog.active or Game.fade > 0) and t < (maxF or 900) do
    if t % 6 == 0 then In.fake = { atk = true } end
    tick()
    t = t + 1
  end
  return not Dialog.active
end

local function talk(id)
  local e = NPC.find(id)
  Test.ok(e ~= nil, "npc exists: " .. id)
  if not e then return end
  warp(landNear(e.x, e.y + 10, 3))
  tick(2)
  NPC.talk(e)
  Test.ok(closeDialogs(), "dialog with " .. id .. " closes")
  tick(4)
end

local function state(id) return Quest.state(id) end

local function fight(id, x, y)
  warp(x, y)
  local t = 0
  while not (Boss.cur and Boss.cur.def.id == id) and t < 120 do tick() t = t + 1 end
  local b = Boss.cur
  Test.ok(b and b.def.id == id, id .. " spawns in its arena")
  if not b then return end
  tick(2)
  Test.ok(Music.cur == "boss", id .. ": battle music")
  -- let the AI run against the ninja, sampling whether a standing or jumping
  -- katana swing could reach it (z window from swingHits)
  local seen, reach = 0, 0
  for _ = 1, 900 do
    tick()
    if not b.alive then break end
    if b.hostile and not b.hidden then
      seen = seen + 1
      local g = groundAt(b.x, b.y)
      local ez = b.z + (b.hz or 6)
      local win = 16 + (b.tall or 0)
      if ez - 6 - win < g + 28 and ez - 6 + win > g then reach = reach + 1 end
    end
  end
  Test.log(string.format("%s: visible %d/900 frames, sword-reachable %d, hp %d/%d", id, seen, reach, b.hp, b.maxhp))
  Test.ok(seen > 0 and reach / seen > 0.25, id .. " is in sword reach often enough")
  t = 0
  while b.hp > 0 and t < 4000 do
    if b.hostile and not b.hidden and (b.inv or 0) == 0 then Enemy.hurt(b, 4, P.x, P.y, 0) end
    tick()
    t = t + 1
  end
  Test.ok(b.hp <= 0, id .. " can be defeated")
  tick(150)
  Test.ok(Boss.defeated[id], id .. " recorded as defeated")
  Test.ok(Boss.cur == nil, id .. ": fight over")
end

local function killN(kind, n, opt)
  for _ = 1, n do
    local e = Enemy.spawn(kind, P.x + 30, P.y, opt)
    tick(2)
    Enemy.hurt(e, 99, P.x, P.y, 0)
    tick(3)
  end
end

local function script()
  Game.newGame()
  Test.ok(closeDialogs(), "intro dialog")
  tick(10)

  -- mq1: torch, pagoda, sensei
  Test.ok(state("mq1") == "active", "mq1 active")
  Drops.give("torch", 1)
  tick(2)
  Test.ok(QS.mq1.step == 2, "mq1: crafting the torch advances")
  local t1 = TOWERS[1]
  warp(t1.x, t1.y + 20)
  Quest.tower(t1)
  tick(4)
  Test.ok(QS.mq1.step == 3, "mq1: surveying the pagoda advances")
  talk("sensei")
  Test.ok(state("mq1") == "done" and P.has.kite, "mq1 done, kite unlocked")
  Test.ok(state("mq2") == "active", "mq2 starts by itself")

  -- bosses must not appear before Lady Sayo's briefing
  warp(landNear(POI.lair.x, POI.lair.y, 6))
  tick(30)
  Test.ok(Boss.cur == nil, "no boss before mq2 is done")

  -- mq2: Lady Sayo
  talk("lady")
  Test.ok(state("mq2") == "done", "mq2 done")
  for _, q in ipairs({ "jewel", "mirror", "sword" }) do Test.ok(state(q) == "active", q .. " starts by itself") end

  -- the three treasures
  fight("jorogumo", landNear(POI.lair.x, POI.lair.y, 6))
  Test.ok(state("jewel") == "done" and P.has.djump, "jewel done, double jump unlocked")
  fight("tengulord", landNear(POI.summit.x, POI.summit.y, 6))
  Test.ok(state("mirror") == "done" and P.has.mirror, "mirror done")
  fight("orochi", landNear(POI.lake.x, POI.lake.y, 7))
  Test.ok(state("sword") == "done" and P.weapon == "kusanagi", "sword done, Kusanagi equipped")

  -- mq4: Lady Sayo again, then Shuten-doji
  Test.ok(state("mq4") == "active", "mq4 starts once all treasures are back")
  warp(landNear(POI.onigashima.x, POI.onigashima.y, 6))
  tick(30)
  Test.ok(Boss.cur == nil, "Shuten waits for the briefing")
  talk("lady")
  Test.ok(QS.mq4 and QS.mq4.step == 2, "mq4: bridge unsealed")
  fight("shuten", landNear(POI.onigashima.x, POI.onigashima.y, 6))
  local t = 0
  while Game.state ~= "finale" and t < 300 do tick() t = t + 1 end
  Test.ok(Game.state == "finale" and state("mq4") == "done", "finale after Shuten")
  Test.ok(Music.cur == "title", "finale music")
  tick(250)
  In.fake = { atk = true }
  tick(3)
  Test.ok(Game.state == "play", "back to the world after the finale")
  Test.dump("q_after_finale")

  -- side quests (with an upgraded, emptied bag) ------------------------------
  Inv.reset()
  Inv.size = 16
  local function offer(giver, id)
    talk(giver)
    Test.ok(state(id) == "active", id .. ": offered and accepted")
  end
  local function turnIn(npc, id)
    talk(npc)
    Test.ok(state(id) == "done", id .. ": turned in")
  end

  offer("farmer", "rice")
  Drops.give("rice", 5) tick(2)
  local ryo = P.ryo
  turnIn("farmer", "rice")
  Test.ok(P.ryo == ryo + 20 and Inv.count("rice") == 0, "rice: reward paid, rice taken")

  offer("mei", "cat")
  local tama
  for _, e in ipairs(ENTS) do if e.alive and e.id == "tama" then tama = e end end
  Test.ok(tama ~= nil, "cat: Tama is out there")
  if tama then
    warp(landNear(tama.x, tama.y, 3))
    tick(2)
    tama:interact()
    closeDialogs()
  end
  Test.ok(Inv.has("cat"), "cat: Tama picked up")
  turnIn("mei", "cat")
  Test.ok(Inv.has("charm"), "cat: charm received")

  offer("captain", "bounty")
  killN("bandit", 6)
  Test.ok(QS.bounty.step == 2, "bounty: six bandits counted")
  turnIn("captain", "bounty")

  offer("teamaster", "tea")
  Drops.give("herb", 4) tick(2)
  turnIn("teamaster", "tea")

  offer("tailor", "pelts")
  Drops.give("pelt", 3) tick(2)
  turnIn("tailor", "pelts")
  Test.ok(Inv.has("cloak"), "pelts: fur cloak received")

  offer("fisher", "kappa")
  killN("kappa", 4)
  turnIn("fisher", "kappa")

  -- a full bag must not swallow the parcel: it drops at your feet instead
  for i = 1, Inv.size do if not Inv.slots[i] then Inv.slots[i] = { id = "stone", n = 1 } end end
  offer("merchant", "package")
  local parcel
  for _, e in ipairs(ENTS) do if e.alive and e.kind == "drop" and e.item == "package" then parcel = e end end
  Test.ok(not Inv.has("package") and parcel ~= nil, "package: full bag drops the parcel on the ground")
  for i = 1, Inv.size do local sl = Inv.slots[i] if sl and sl.id == "stone" then Inv.slots[i] = nil end end
  if parcel then warp(parcel.x, parcel.y) end
  tick(60)
  Test.ok(Inv.has("package"), "package: parcel picked up")
  -- talking to the innkeeper without it must not break the quest
  Inv.take("package", 1)
  talk("inn_yuki")
  Test.ok(state("package") == "active" and QS.package.step == 1, "package: turn-in without the parcel keeps the quest valid")
  tick(10)
  Drops.give("package", 1) tick(2)
  turnIn("inn_yuki", "package")

  offer("woodcutter", "silk")
  Drops.give("silk", 4) tick(2)
  turnIn("woodcutter", "silk")

  offer("abbot", "spirits")
  killN("yurei", 5)
  turnIn("abbot", "spirits")

  local done = 0
  for _, q in ipairs(QUESTS) do if state(q.id) == "done" then done = done + 1 end end
  Test.ok(done == #QUESTS, "all " .. #QUESTS .. " quests complete (" .. done .. ")")
  Test.ok(P.state ~= "dead", "survived the playthrough")
end

co = coroutine.create(script)

function TIC()
  In.fake = {}
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then
      Test.log("FAIL script error: " .. tostring(err))
      Test.finish()
      return
    end
  else
    Test.finish()
    return
  end
  if god and P then
    P.iframes = math.max(P.iframes, 2)
    P.hp = P.maxhp
    P.hunger = 85
    P.stam = P.maxstam
    P.cold, P.dark = 0, 0
    Clock.t = 0.3
  end
  Game.tick()
end

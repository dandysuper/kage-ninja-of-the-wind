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

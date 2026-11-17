-- ============================================================================
--  t_smoke: boot the real game, start a new game, drive scripted input
--  through the main systems, dump key frames, then fuzz random input.
--  Any Lua error fails the run (tools/test.sh greps the log).
-- ============================================================================
local f = 0
local phase = "start"
local held = {}
local function press(t) In.fake = t end

local SCRIPT = {
  -- frame, inputs (held for one frame unless 'hold' frames given)
  { 1, function() Game.newGame() end },
}

local function setIn(t) In.fake = t or {} end

local steps = {}
local function at(n, fn) steps[n] = fn end

-- advance the sensei intro
for k = 0, 12 do at(10 + k * 6, function() setIn({ atk = true }) end) end
at(100, function()
  Test.ok(not Dialog.active, "intro dialog closed")
  Test.dump("s01_start")
end)
-- walk east, sprint, jump
for k = 101, 160 do at(k, function() setIn({ right = true }) end) end
for k = 161, 200 do at(k, function() setIn({ up = true, run = true }) end) end
at(201, function() setIn({ jump = true }) end)
for k = 202, 214 do at(k, function() setIn({ jump = true, right = true }) end) end
at(230, function()
  Test.log(string.format("player at %.0f,%.0f z=%.1f state=%s", P.x, P.y, P.z, P.state))
  Test.dump("s02_moved")
end)
-- attack combo + throw
for k = 231, 270 do at(k, function() setIn({ atk = (k % 6 == 0) }) end) end
at(271, function() setIn({ throw = true }) end)
-- open menu, browse tabs, craft tab, close
at(280, function() setIn({ menu = true }) end)
at(284, function() Test.ok(Menu.cur == "pause", "pause menu open") Test.dump("s03_items") end)
at(286, function() setIn({ rotr = true }) end)
at(290, function() Test.dump("s04_craft") end)
at(292, function() setIn({ rotr = true }) end)
at(296, function() Test.dump("s05_map") end)
at(298, function() setIn({ rotr = true }) end)
at(302, function() Test.dump("s06_quests") end)
at(304, function() setIn({ jump = true }) end)
at(306, function() Test.ok(Menu.cur == nil, "menu closed") end)
-- give materials, craft a torch via the menu
at(310, function()
  Inv.add("bamboo", 5) Inv.add("grass", 8) Inv.add("wood", 6) Inv.add("flint", 5)
  setIn({ menu = true })
end)
at(314, function() setIn({ rotr = true }) end)
at(318, function() setIn({ throw = true }) end) -- S: next crafting tab (Light)
at(322, function() setIn({ atk = true }) end)   -- craft first recipe (torch)
at(326, function() Test.ok(Inv.has("torch"), "crafted torch") setIn({ jump = true }) end)
at(330, function() Test.log("mq1 step " .. tostring(QS.mq1 and QS.mq1.step)) end)
-- teleport near the pagoda and climb
at(340, function()
  local t = TOWERS[1]
  P.x, P.y = t.x, t.y + 16
  P.z = groundAt(P.x, P.y)
  P.state = "ground"
  Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
end)
for k = 341, 700 do at(k, function()
  local ca, sa = math.cos(Cam.a), math.sin(Cam.a)
  setIn({ up = true })
end) end
at(560, function() Test.log(string.format("climbing: state=%s z=%.1f stam=%.0f", P.state, P.z, P.stam)) Test.dump("s07_climb") end)
at(701, function() Test.log(string.format("after climb: state=%s z=%.1f top=%.1f", P.state, P.z, TOWERS[1].top)) end)
-- System tab: cycle the music volume option, then restore it
at(702, function() setIn({ menu = true }) end)
at(704, function() setIn({ rotl = true }) end)
at(706, function() setIn({ down = true }) end)
at(708, function() setIn({ down = true }) end)
at(710, function() setIn({ atk = true }) end)
at(712, function()
  Test.ok(Menu.tab == 5 and Audio.music == 2, "music volume option cycles")
  Test.dump("s06b_system")
  Audio.setLevels(3, 3)
  setIn({ jump = true })
end)
at(714, function() Test.ok(Menu.cur == nil, "system menu closed") end)
-- night with a torch
at(720, function()
  Clock.t = 0.8
  Menu.useItem((function() for i = 1, Inv.size do local s = Inv.slots[i] if s and s.id == "torch" then return i end end return 1 end)())
  P.x, P.y = POI.hanamura.x, POI.hanamura.y + 10
  P.z = groundAt(P.x, P.y) P.state = "ground"
  Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
  setIn({})
end)
at(740, function() Test.dump("s08_night") end)
-- combat: spawn enemies around
at(760, function()
  Clock.t = 0.3
  P.x, P.y = 88 * 8, 75 * 8
  P.z = groundAt(P.x, P.y) P.state = "ground"
  Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
  Enemy.spawn("bandit", P.x + 20, P.y)
  Enemy.spawn("wolf", P.x - 20, P.y + 10)
  Enemy.spawn("oni", P.x, P.y - 30)
end)
for k = 761, 900 do at(k, function() setIn({ atk = (k % 5 == 0), left = (k % 40 < 20), right = (k % 40 >= 20) }) end) end
at(830, function() Test.dump("s09_combat") end)
at(905, function() Test.log("hp " .. P.hp .. "/" .. P.maxhp .. " state " .. P.state .. " ents " .. #ENTS) end)

local fuzzEnd = 3600
function TIC()
  f = f + 1
  In.fake = {}
  if f == 1 then Game.newGame() end
  local s = steps[f]
  if s then s() end
  if f > 905 then
    -- fuzz: random inputs, occasional teleports across the world
    local keys = { "up", "down", "left", "right", "atk", "jump", "use", "throw", "run", "rotl", "rotr", "menu", "map", "quest", "ok" }
    local t = {}
    for _, k in ipairs(keys) do if math.random() < 0.18 then t[k] = true end end
    if math.random() < 0.02 then t.menu = true end
    In.fake = t
    if f % 400 == 0 then
      local x, y = math.random(10, 230) * 8, math.random(10, 100) * 8
      P.x, P.y = x, y
      P.z = groundAt(x, y)
      P.state = "ground"
      Cam.x, Cam.y, Cam.z = x, y, P.z
      Clock.t = math.random()
    end
    if P.state == "dead" and Game.deadT and Game.deadT > 95 then In.fake = { atk = true } end
  end
  local t0 = time()
  Game.tick()
  local dt = time() - t0
  Test.maxms = math.max(Test.maxms or 0, dt)
  Test.summs = (Test.summs or 0) + dt
  if f == 1500 then Test.dump("s10_fuzz") end
  if f >= fuzzEnd then
    Test.log(string.format("frames=%d avg=%.2fms max=%.2fms ents=%d", f, Test.summs / f, Test.maxms, #ENTS))
    Test.finish()
  end
end

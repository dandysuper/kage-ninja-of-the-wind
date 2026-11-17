-- ============================================================================
--  t_title: the real start-up flow, which t_smoke skips (it calls
--  Game.newGame() on frame 1): title screen with its music, the Controls
--  panel, New Game through the menu, the intro dialog, then a few seconds of
--  play. Fails on any Lua error.
-- ============================================================================
local f = 0
local steps = {}
local function at(n, fn) steps[n] = fn end
local function press(t) return function() In.fake = t end end

at(5, function()
  Test.ok(Game.state == "title", "boots to the title screen")
  Test.ok(Music.playing == "title", "title music playing")
end)
at(120, function() Test.dump("t01_title") Game.titleSel = 1 end)
at(130, press({ down = true }))
at(134, press({ down = true }))
at(140, function() Test.ok(Game.titleSel == 3, "cursor on Controls") end)
at(142, press({ atk = true }))
at(150, function() Test.ok(Game.help == true, "controls panel open") Test.dump("t02_controls") end)
at(152, press({ atk = true }))
at(158, function() Test.ok(not Game.help, "controls panel closed") end)
at(160, press({ up = true }))
at(166, function() Test.ok(Game.titleSel == 2, "cursor on New Game") end)
at(168, press({ atk = true }))
at(172, function() Test.ok(Game.state == "play" and P ~= nil, "new game started") end)
for k = 0, 14 do at(180 + k * 8, press({ atk = true })) end
at(320, function()
  Test.ok(not Dialog.active, "intro dialog done")
  Test.ok(Music.cur == "field" or Music.cur == "night" or Music.cur == "town", "gameplay music requested: " .. tostring(Music.cur))
  Test.dump("t03_play")
end)
for k = 321, 420 do at(k, press({ right = (k % 60 < 40), up = (k % 60 >= 40), jump = (k % 45 == 0) })) end
at(460, function()
  Test.ok(Music.playing ~= "title" and Music.playing ~= nil, "title music faded out: " .. tostring(Music.playing))
  Test.finish()
end)

function TIC()
  f = f + 1
  In.fake = {}
  local s = steps[f]
  if s then s() end
  Game.tick()
end

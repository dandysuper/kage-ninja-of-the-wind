-- focused physics test: walk into the pagoda's south wall, climb to the top,
-- then let go of the controls and check the ninja stays up there
local f = 0
local topF
function TIC()
  f = f + 1
  if f == 1 then
    Game.newGame()
    Dialog.active = false
    local t = TOWERS[1]
    P.x, P.y = t.x, t.y + 22
    P.z = groundAt(P.x, P.y)
    Cam.a, Cam.ta = 0, 0
    Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
    Test.log(string.format("start x=%.1f y=%.1f z=%.1f tower top=%.1f cellH south face=%d", P.x, P.y, P.z, t.top, cellH(flr(t.x / 8), flr(t.y / 8))))
  end
  local top = TOWERS[1].top
  if not topF and P.state == "ground" and P.z >= top - 3 then
    topF = f
    Test.log(string.format("standing on top at f=%d z=%.1f", f, P.z))
  end
  In.fake = topF and {} or { up = true }
  Game.tick()
  if f % 20 == 0 then
    Test.log(string.format("f=%d state=%s x=%.1f y=%.1f z=%.1f stam=%.0f pushT=%d", f, P.state, P.x, P.y, P.z, P.stam, P.pushT))
  end
  if f == 120 then Test.dump("c_climb") end
  if f == 400 then
    Test.ok(topF ~= nil, "reached the top of the pagoda")
    Test.ok(P.z > TOWERS[1].top - 3 and P.state == "ground", "still standing on top")
    Test.dump("c_top")
    Test.finish()
  end
end

-- ============================================================================
--  t_reach: can a ninja with base stats reach and collect every kodama and
--  every spire-trial orb? For each target the ninja starts on the ground
--  2.5 cells away, the camera is turned so that holding Up walks straight
--  at it (Up = Cam.fwd()), and he holds Up (jumping when stuck) until he
--  stands on top. Four approach sides are tried. Stamina starts full and is
--  not refilled during an attempt; health/hunger/daylight are pinned.
-- ============================================================================
local co

local function tick(n)
  for _ = 1, n or 1 do coroutine.yield() end
end

local function attempt(cx, cy, top, side)
  Cam.a = side * math.pi / 2
  Cam.ta = Cam.a
  local fx, fy = Cam.fwd()
  local tx, ty = cx * 8 + 4, cy * 8 + 4
  P.x, P.y = tx - fx * 20, ty - fy * 20
  P.z = groundAt(P.x, P.y)
  P.state = "ground"
  P.vx, P.vy, P.vz = 0, 0, 0
  P.stam, P.exhausted = P.maxstam, false
  Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
  for f = 1, 420 do
    local onTop = P.state == "ground" and flr(P.x / 8) == cx and flr(P.y / 8) == cy and P.z >= top - 3
    if onTop then return f end
    local near = flr(P.x / 8) == cx and flr(P.y / 8) == cy
    In.fake = { up = not near, jump = (P.state == "ground" and f % 30 == 15) }
    tick()
  end
  return nil
end

local function reach(name, cx, cy, top, after)
  for side = 0, 3 do
    local f = attempt(cx, cy, top, side)
    if f then
      Test.log(string.format("%-26s h=%3d side %d in %3d frames (stamina left %d)", name, top, side, f, flr(P.stam)))
      if after then after() end
      return true
    end
  end
  Test.ok(false, "reachable: " .. name .. string.format(" (cell %d,%d top %d)", cx, cy, top))
  return false
end

local function script()
  Game.newGame()
  while Dialog.active do In.fake = { atk = true } tick() tick() end
  tick(5)
  for _, i in ipairs(KODAMA) do
    local cx, cy = (i - 1) % 240, (i - 1) // 240
    reach("kodama " .. cx .. "," .. cy, cx, cy, math.max(WH[i], 0), function()
      In.fake = { use = true }
      tick(2)
      Test.ok(World.found[i], "kodama collected at " .. cx .. "," .. cy)
    end)
  end
  for _, s in ipairs(SHRINES) do
    if s.top then
      reach(s.name, s.top[1], s.top[2], s.top[3], function()
        tick(2)
        Test.ok(Shrine.done[s.id], s.name .. ": orb claimed")
      end)
    end
  end
  Test.log(string.format("seeds %d, orbs %d", P.seeds, P.orbs))
end

co = coroutine.create(script)

function TIC()
  In.fake = {}
  if coroutine.status(co) == "dead" then Test.finish() return end
  local ok, err = coroutine.resume(co)
  if not ok then
    Test.log("FAIL script error: " .. tostring(err))
    Test.finish()
    return
  end
  if P then
    P.iframes = math.max(P.iframes, 2)
    P.hp, P.hunger, P.cold, P.dark = P.maxhp, 85, 0, 0
    Clock.t = 0.3
  end
  Game.tick()
end

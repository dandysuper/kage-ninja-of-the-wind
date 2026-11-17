-- ============================================================================
--  t_world: water exits and tree chopping, through real inputs.
--   * swimming next to a bank one step (4) high: holding towards it walks out
--   * swimming next to a bank two steps (8) high: X leaps out onto it
--   * a tree chopped with the starting bokken (no hatchet): 6 swings, leans
--     further each hit, then falls, leaves a stump and drops wood
--   * bamboo with the bokken: 4 swings
--  Holding Up walks along Cam.fwd(), so the camera is turned to aim it.
-- ============================================================================
local co

local function tick(n)
  for _ = 1, n or 1 do coroutine.yield() end
end

-- screenshot without the region title / banner covering the scene
local function shot(tag)
  UI.regionT, UI.bannerT = 0, 0
  tick()
  Test.dump(tag)
end

local function aim(dx, dy)
  Cam.a = math.atan(dx, -dy)
  Cam.ta = Cam.a
end

local function place(x, y, z, state)
  P.x, P.y, P.z = x, y, z
  P.state = state
  P.vx, P.vy, P.vz = 0, 0, 0
  P.stam, P.exhausted = P.maxstam, false
  Cam.x, Cam.y, Cam.z = x, y, math.max(z, 0)
end

-- a water cell whose neighbour in direction (dx, dy) is dry land of height h,
-- with dry land of at least that height behind it too
local function findShore(h)
  for cy = 2, 109 do
    for cx = 2, 237 do
      local i = cidx(cx, cy)
      if (WF[i] & F_WATER) ~= 0 then
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local j, k = cidx(cx + d[1], cy + d[2]), cidx(cx + 2 * d[1], cy + 2 * d[2])
          if WH[j] == h and (WF[j] & (F_WATER | F_ROOF | F_MODEL)) == 0 and WO[j] == 0
            and WH[k] >= h and WH[k] <= h + 4 and (WF[k] & F_WATER) == 0 then
            return cx, cy, d[1], d[2]
          end
        end
      end
    end
  end
end

local function shoreTest(h, leap)
  local cx, cy, dx, dy = findShore(h)
  Test.ok(cx ~= nil, "found water beside a bank of height " .. h)
  if not cx then return end
  aim(dx, dy)
  place(cx * 8 + 4, cy * 8 + 4, -3, "swim")
  tick(2)
  Test.ok(P.state == "swim", "swimming at " .. cx .. "," .. cy)
  local out
  for f = 1, 120 do
    In.fake = { up = true, jump = leap and f == 4 }
    tick()
    if P.state == "ground" and P.z >= h - 0.5 then out = f break end
  end
  Test.log(string.format("bank %d (%s): %s", h, leap and "X leap" or "swim", out and ("out at frame " .. out .. ", z=" .. P.z) or ("still " .. P.state .. " z=" .. P.z)))
  Test.ok(out ~= nil, (leap and "X leaps onto" or "swims onto") .. " a bank " .. h .. " high")
end

-- nearest object of kind o to (x, y) with dry, flat, free ground south of it
-- (`open` cells of it, so nothing stands between the camera and the tree)
local function findObj(o, x, y, open)
  local best, bi = 1e9, nil
  for cy = 2, 104 do
    for cx = 2, 237 do
      local i = cidx(cx, cy)
      local free = WO[i] == o
      for k = 1, open or 1 do
        local s = cidx(cx, cy + k)
        free = free and WO[s] == 0 and WH[s] == WH[i] and (WF[s] & (F_WATER | F_ROOF | F_MODEL | F_TOWN)) == 0
      end
      if free then
        local ox, oy = objPos(i)
        local d = dist(ox, oy, x, y)
        if d < best then best, bi = d, i end
      end
    end
  end
  return bi
end

local function chopTest(o, name, expect, shots)
  local i = findObj(o, POI.start.x, POI.start.y, shots and 5 or 1)
  Test.ok(i ~= nil, "found a " .. name)
  if not i then return end
  local ox, oy = objPos(i)
  aim(0, -1)
  place(ox, oy + 9, groundAt(ox, oy + 9), "ground")
  P.dir = -math.pi / 2
  tick(3)
  local swings, hits, prev, leans = 0, 0, 0, {}
  while WO[i] == o and swings < 16 do
    In.fake = { atk = true }
    tick(24)
    swings = swings + 1
    local h = World.hits[i] or 0
    if WO[i] ~= o or h > prev then hits = hits + 1 end
    prev = h
    local c = World.chop[i]
    if c then leans[#leans + 1] = string.format("%.2f", 0.24 * World.hits[i] / c.n) end
    if shots and hits == 5 and h == 5 then shot("w_" .. name .. "_hit5") end
  end
  Test.log(name .. ": " .. hits .. " hits in " .. swings .. " swings, lean " .. table.concat(leans, " "))
  Test.ok(hits == expect, name .. " falls after " .. expect .. " hits (took " .. hits .. ")")
  Test.ok(WO[i] == OBJ[o].after, name .. " leaves its stump")
  local faller
  for _, e in ipairs(ENTS) do if e.alive and e.kind == "fx" then faller = e end end
  Test.ok(faller ~= nil, name .. " topples (falling entity)")
  local wood = Inv.count(OBJ[o].drop[1][1])
  if shots then
    tick(5) shot("w_" .. name .. "_falling")
    tick(8) shot("w_" .. name .. "_landed")
    tick(64)
  else
    tick(80)
  end
  Test.ok(faller == nil or not faller.alive, name .. ": falling entity cleaned up")
  Test.ok(Inv.count(OBJ[o].drop[1][1]) > wood, name .. ": drops collected")
end

local function script()
  Game.newGame()
  while Dialog.active do In.fake = { atk = true } tick() tick() end
  tick(5)
  Clock.t = 0.3
  shoreTest(4, false)
  shoreTest(8, true)
  Test.ok(not Inv.has("axe"), "no hatchet yet")
  tick(400) -- let the intro banner and region title fade before the shots
  chopTest(O_TREE, "tree", 6, true)
  chopTest(O_BAMBOO, "bamboo", 4, false)
  Inv.add("axe", 1)
  chopTest(O_TREE, "tree_axe", 4, false)
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

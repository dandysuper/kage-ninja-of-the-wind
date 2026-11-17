-- ============================================================================
--  36 WORLD INTERACTION - harvesting (Z), picking/using (A), regrowth,
--  campfires that burn out, chests, signs, kodama, jizo blessings.
-- ============================================================================
World = { hits = {}, regrow = {}, fires = {}, chests = {}, signs = {}, kodama = {}, opened = {}, found = {}, blessed = {} }

local function cellOf(i) return (i - 1) % 240, (i - 1) // 240 end

-- change an object keeping its jittered position
function World.setObj(i, o)
  WO[i] = o
  if o > 0 then
    local x, y = cellOf(i)
    local k = (y // 8) * 30 + (x // 8)
    OLIST[k] = OLIST[k] or {}
    OLIST[k][i] = true
  end
end

local TOOLNAME = { axe = "a hatchet", pick = "a pickaxe" }

-- leaves shed by tall plants when chopped and when they fall
World.chop = {}
World.LEAVES = {
  default = { C_GREEN, C_LIME, C_DKGRN },
  [O_SAKURA] = { C_PINK, C_WHITE, C_PINK }, [O_MAPLE] = { C_RED, C_GOLD, C_WOOD }, [O_DEAD] = { C_GRAY, C_BROWN },
  [O_SNOWPINE] = { C_WHITE, C_DKGRN }, [O_BAMBOO] = { C_LIME, C_GREEN },
}

-- screen side (+1 right, -1 left) a chopped plant leans and falls towards
function World.chopSide(c)
  return (c.ux * math.cos(Cam.a) + c.uy * math.sin(Cam.a)) < 0 and -1 or 1
end

-- Z on a harvestable object. Rocks need a pickaxe; every blade chops wood,
-- but without a hatchet trees take 1.5x the swings and the bokken needs twice
-- as many for bamboo. Tall plants lean further away with every hit.
function World.hit(i)
  local o = WO[i]
  local d = OBJ[o]
  if not d or not d.tool then return end
  local ox, oy = objPos(i)
  local oz = math.max(WH[i], 0)
  if d.tool == "pick" and not Inv.has("pick") then
    UI.toast("Need " .. TOOLNAME.pick .. " for that")
    Sfx.play("clank")
    FX.burst(ox, oy, oz + 6, 3, { C_WHITE, C_GRAY }, 0.8, 10)
    return
  end
  local need = d.hits or 1
  if not Inv.has("axe") then
    if d.tool == "axe" then
      need = ceil(need * 1.5)
      if not World.axeHint then
        World.axeHint = true
        UI.toast("A hatchet chops faster (Craft > Tools)")
      end
    elseif o == O_BAMBOO and P.weapon == "bokken" then
      need = need * 2
    end
  end
  World.hits[i] = (World.hits[i] or 0) + 1
  if d.tool == "pick" then
    Sfx.play("mine")
    FX.burst(ox, oy, oz + 6, 5, { C_GRAY, C_WHITE, C_INDIGO }, 1.2, 14)
  else
    Sfx.play("chop")
    FX.burst(ox, oy, oz + 6, 6, { C_WOOD, C_TAN, C_CREAM }, 1.1, 16)
  end
  if d.h and d.h >= 40 then
    local dx, dy = ox - P.x, oy - P.y
    local l = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    World.chop[i] = { n = need, t = 14, ux = dx / l, uy = dy / l }
    FX.burst(ox, oy, oz + 34, 6, World.LEAVES[o] or World.LEAVES.default, 0.9, 30)
  end
  FX.shake(1)
  if World.hits[i] >= need then World.harvest(i) end
end

-- a chopped tree topples away from the blade, lands in a shower of leaves and
-- breaks into the drops it leaves behind
function World.fell(d, o, ox, oy, oz, c)
  local spr = SPR[d.spr]
  local leaves = World.LEAVES[o] or World.LEAVES.default
  local e = Ent.add({ kind = "fx", x = ox, y = oy, z = oz, r = 0, always = true })
  Sfx.play("fall")
  e.update = function(self)
    if self.t == 16 then
      local lx, ly = ox + c.ux * 18, oy + c.uy * 18
      FX.shake(3)
      FX.burst(lx, ly, oz + 4, 14, leaves, 1.4, 30)
      FX.dust(lx, ly, oz, 6)
      for _, dr in ipairs(d.drop or {}) do
        local n = rnd(dr[2], dr[3])
        if n > 0 then Drops.spawn(ox, oy, oz + 6, dr[1], n) end
      end
    elseif self.t > 26 then
      self.alive = false
      FX.burst(ox + c.ux * 10, oy + c.uy * 10, oz + 4, 8, { C_WOOD, C_TAN, C_BROWN }, 1.0, 20)
    end
  end
  e.draw = function(self)
    local k = math.min(1, self.t / 16)
    Render.billRot(spr, ox, oy, oz, false, d.pm, 1, World.chopSide(c) * (0.24 + k * k * (math.pi / 2 - 0.24)), 1.5)
  end
end

function World.harvest(i)
  local o = WO[i]
  local d = OBJ[o]
  local ox, oy = objPos(i)
  local oz = math.max(WH[i], 0)
  local c = World.chop[i]
  World.hits[i], World.chop[i] = nil, nil
  World.setObj(i, d.after or 0)
  if d.regrow then
    World.regrow[#World.regrow + 1] = { i = i, at = Clock.total + d.regrow, o = o }
  end
  if c and d.spr and SPR[d.spr] then
    World.fell(d, o, ox, oy, oz, c)
    return
  end
  for _, dr in ipairs(d.drop or {}) do
    local n = rnd(dr[2], dr[3])
    if n > 0 then Drops.spawn(ox, oy, oz + 6, dr[1], n) end
  end
end

-- regrowth / fires burning out (call once per frame; cheap)
function World.update()
  local now = Clock.total
  for _, c in pairs(World.chop) do
    if c.t > 0 then c.t = c.t - 1 end
  end
  if now % 30 == 0 then
    local r = World.regrow
    local j = 0
    for k = 1, #r do
      local e = r[k]
      local keep = true
      if now >= e.at then
        local ox, oy = objPos(e.i)
        if dist(ox, oy, P.x, P.y) > 24 then
          World.setObj(e.i, e.o)
          keep = false
        end
      end
      if keep then j = j + 1 r[j] = e end
    end
    for k = j + 1, #r do r[k] = nil end
    local f = World.fires
    j = 0
    for k = 1, #f do
      local e = f[k]
      if now >= e.at and WO[e.i] == O_FIRE then
        World.setObj(e.i, O_LOGS)
      elseif WO[e.i] == O_FIRE then
        j = j + 1
        f[j] = e
      end
    end
    for k = j + 1, #f do f[k] = nil end
  end
end

-- place an object (campfire, pot) in front of the player
function World.place(o)
  local fx, fy = math.cos(P.dir), math.sin(P.dir)
  local x, y = P.x + fx * 10, P.y + fy * 10
  local cx, cy = flr(x / 8), flr(y / 8)
  if not inmap(cx, cy) then return false end
  local i = cidx(cx, cy)
  if WO[i] ~= 0 or (WF[i] & (F_WATER | F_ROOF | F_MODEL)) ~= 0 or math.abs(math.max(WH[i], 0) - P.z) > 4 then
    UI.toast("Can't place that here")
    return false
  end
  setObj(cx, cy, o)
  if o == O_FIRE then World.fires[#World.fires + 1] = { i = i, at = Clock.total + 60 * 150 } end
  Sfx.play("place")
  return true
end

function World.interact(i)
  local o = WO[i]
  local d = OBJ[o]
  local ox, oy = objPos(i)
  local oz = math.max(WH[i], 0)
  if d.hand then
    Sfx.play("pick")
    for _, dr in ipairs(d.drop or {}) do
      local n = rnd(dr[2], dr[3])
      if n > 0 then Drops.give(dr[1], n, ox, oy, oz) end
    end
    World.setObj(i, d.after or 0)
    if d.regrow then World.regrow[#World.regrow + 1] = { i = i, at = Clock.total + d.regrow, o = o } end
    return
  end
  local t = d.talk
  if t == "chest" then
    local c = World.chests[i] or { "ryo", rnd(10, 30) }
    World.setObj(i, O_CHESTO)
    World.opened[i] = true
    Sfx.play("chest")
    FX.burst(ox, oy, oz + 8, 12, { C_GOLD, C_WHITE }, 1.2, 30)
    Drops.give(c[1], c[2], ox, oy, oz)
    UI.banner("Found " .. (c[1] == "ryo" and (c[2] .. " ryo") or ((c[2] > 1 and (c[2] .. " ") or "") .. ITEM[c[1]].n)) .. "!")
  elseif t == "sign" then
    local s = World.signs[i] or ("Welcome to " .. REG[WR[i]].name .. ".")
    Dialog.say("Signpost", s)
  elseif t == "kodama" then
    World.setObj(i, 0)
    World.found[i] = true
    P.seeds = P.seeds + 1
    Sfx.play("kodama")
    FX.burst(ox, oy, oz + 6, 14, { C_WHITE, C_LIME, C_GREEN }, 1.4, 30)
    UI.banner("Ya-ha-ha! Kodama found! (" .. P.seeds .. " seeds)")
    Quest.event("kodama")
  elseif t == "shrine" then
    Shrine.interact(i)
  elseif t == "fire" then
    Menu.open("cook", { fire = true })
  elseif t == "pot" then
    Menu.open("cook", { pot = true })
  elseif t == "logs" then
    if Inv.has("wood") then
      Inv.take("wood", 1)
      World.setObj(i, O_FIRE)
      World.fires[#World.fires + 1] = { i = i, at = Clock.total + 60 * 150 }
      Sfx.play("fire")
      UI.toast("You rekindle the fire")
    else
      UI.toast("Needs 1 wood to rekindle")
    end
  elseif t == "statue" then
    Shrine.statue()
  elseif t == "jizo" then
    local day = Clock.day
    if World.blessed[i] ~= day then
      World.blessed[i] = day
      Player.heal(8)
      Sfx.play("heal")
      FX.burst(ox, oy, oz + 8, 10, { C_WHITE, C_GOLD }, 1, 30)
      Dialog.say("Jizo", "You bow to the little guardian. Warmth fills you. (+2 hearts)")
    else
      Dialog.say("Jizo", "The Jizo smiles silently. Come back tomorrow.")
    end
  end
end

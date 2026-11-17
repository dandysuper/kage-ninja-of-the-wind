-- ============================================================================
--  48 BOSSES & SHRINES
--  Jorogumo (spider queen), Tengu Lord, Orochi (lake serpent heads) and
--  Shuten-doji (Oni King). Each spawns when you enter its arena and resets if
--  you leave or fall. Spirit shrines hold trials that award spirit orbs.
-- ============================================================================
Boss = { defeated = {}, cur = nil }

local BOSSDEF = {
  jorogumo = { name = "Jorogumo, Spider Queen", hp = 40, spr = { "spi1", "spi2" }, sc = 3, r = 10,
    pm = { [C_INDIGO] = C_NIGHT, [C_NIGHT] = C_INDIGO, [C_RED] = C_PINK }, poi = "lair" },
  tengulord = { name = "Sojobo, Tengu Lord", hp = 46, spr = { "ten1", "ten2" }, sc = 2, r = 8, fly = true, hover = 20,
    pm = { [C_INDIGO] = C_NIGHT, [C_RED] = C_GOLD, [C_NIGHT] = C_INDIGO }, poi = "summit" },
  orochi = { name = "Yamata no Orochi", hp = 64, spr = { "oro1", "oro2" }, sc = 2, r = 8, poi = "lake" },
  shuten = { name = "Shuten-doji, Oni King", hp = 90, spr = { "oni1", "oni1" }, atk = "oni_atk", sc = 2, r = 12,
    pm = { [C_RED] = C_INDIGO, [C_WHITE] = C_GOLD, [C_GOLD] = C_RED }, poi = "onigashima" },
}
for id, b in pairs(BOSSDEF) do b.id = id end

local function bossQuestReady(id)
  if id == "shuten" then
    local s = QS.mq4
    return s and s.st == "active" and s.step >= 2
  end
  return Quest.state("mq2") == "done"
end

function Boss.update()
  local p = P
  -- the sealed bridge to Onigashima
  local br = POI.bridge
  if br and not bossQuestReady("shuten") and Quest.state("mq4") ~= "done" then
    local d = dist(p.x, p.y, br.x + 12, br.y + 12)
    if d < 14 then
      local dx, dy = p.x - (br.x + 12), p.y - (br.y + 12)
      local l = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      p.x, p.y = br.x + 12 + dx / l * 14, br.y + 12 + dy / l * 14
      if Frame % 90 == 0 then UI.toast("A sacred seal blocks the bridge.") end
    end
  end
  local b = Boss.cur
  if b then
    if not b.alive or b.hp <= 0 and b.state == "gone" then Boss.cur = nil return end
    local def = b.def
    local a = POI[def.poi]
    if p.state == "dead" or dist(p.x, p.y, a.x, a.y) > 210 then
      -- reset the fight
      for _, e in ipairs(ENTS) do if e.minion or e.bossPart then e.alive = false end end
      b.alive = false
      Boss.cur = nil
      Music.region()
    end
    return
  end
  for id, def in pairs(BOSSDEF) do
    if not Boss.defeated[id] and bossQuestReady(id) then
      local a = POI[def.poi]
      if a and dist(p.x, p.y, a.x, a.y) < 64 and p.state ~= "dead" then
        Boss.spawn(id)
        return
      end
    end
  end
end

function Boss.spawn(id)
  local def = BOSSDEF[id]
  local a = POI[def.poi]
  local e = Ent.add({ kind = "enemy", boss = true, def = def, name = def.name, x = a.x, y = a.y - 24, r = def.r, hp = def.hp, maxhp = def.hp,
    hostile = true, sc = def.sc, state = "intro", st = 0, dir = math.pi / 2, cd = 60, flash = 0, step = 8, dry = true,
    pm = def.pm and Pal.mk(def.pm) or nil, always = true, tall = 14, hz = 14, fly = def.fly, hover = def.hover })
  e.update = Boss["u_" .. id] or Boss.u_generic
  e.draw = Boss.draw
  e.onDeath = Boss.onDeath
  if id == "orochi" then
    e.x, e.y = a.x, a.y
    e.hidden = true
    e.r = 6
  end
  Boss.cur = e
  Music.play("boss")
  UI.banner(def.name)
  FX.shake(5)
  Sfx.play("roar")
  return e
end

function Boss.onDeath(e)
  local def = e.def
  Boss.defeated[def.id] = true
  Boss.cur = nil
  for _, m in ipairs(ENTS) do if m.minion or m.bossPart then m.alive = false end end
  FX.shake(8)
  for k = 1, 4 do FX.burst(e.x, e.y, e.z + 10 + k * 4, 16, { C_GOLD, C_WHITE, C_RED, C_PINK }, 2.4, 50) end
  Sfx.play("victory")
  Quest.event("boss", def.id)
  Music.region()
  Game.autosave()
end

local function shootAt(e, kind, spread, n, spd, dmg)
  local p = P
  local a0 = math.atan(p.y - e.y, p.x - e.x)
  for k = 1, n do
    local a = a0 + (k - (n + 1) / 2) * spread
    local d = dist(e.x, e.y, p.x, p.y)
    local vz = (p.z + 7 - (e.z + 14)) / math.max(d, 1) * spd
    Proj.spawn(kind, e.x + math.cos(a) * 8, e.y + math.sin(a) * 8, e.z + 14, math.cos(a) * spd, math.sin(a) * spd, vz, false, dmg)
  end
  Sfx.play("throw")
end

local function minion(kind, x, y)
  local m = Enemy.spawn(kind, x, y)
  m.minion = true
  m.always = true
  m.state = "chase"
  return m
end

local function common(e)
  if e.flash > 0 then e.flash = e.flash - 1 end
  if e.inv and e.inv > 0 then e.inv = e.inv - 1 end
  if e.state == "dead" then
    e.st = e.st + 1
    if e.st % 6 == 0 then FX.burst(e.x + rnd(-10, 10), e.y + rnd(-6, 6), e.z + rnd(4, 24), 8, { C_GOLD, C_WHITE, C_RED }, 1.5, 24) end
    if e.st > 70 then e.alive = false end
    return true
  end
  e.st = e.st + 1
  if e.cd > 0 then e.cd = e.cd - 1 end
  if e.state == "intro" then
    if e.st > 50 then e.state = "idle" e.st = 0 end
    return true
  end
  return false
end

local function contact(e, dmg, rad)
  local p = P
  if dist(e.x, e.y, p.x, p.y) < (rad or e.r + 4) and math.abs(p.z - e.z) < 18 then Player.damage(dmg, e.x, e.y, "boss") end
end

-- Jorogumo: leaps, web fans, spiderlings
function Boss.u_jorogumo(e)
  if common(e) then return end
  local p = P
  local enraged = e.hp < e.maxhp / 2
  if e.state == "idle" then
    e.dir = math.atan(p.y - e.y, p.x - e.x)
    local sp = enraged and 0.75 or 0.5
    e.vx, e.vy = math.cos(e.dir) * sp, math.sin(e.dir) * sp
    if e.cd == 0 then
      local r = rnd()
      e.st = 0
      if r < 0.4 then e.state = "leapW" Sfx.play("growl")
      elseif r < 0.8 then e.state = "web"
      else e.state = "summon" end
    end
    contact(e, 3)
  elseif e.state == "leapW" then
    e.vx, e.vy = 0, 0
    if e.st > 24 then
      e.state = "leap"
      e.st = 0
      local d = dist(e.x, e.y, p.x, p.y)
      e.vx, e.vy = (p.x - e.x) / 40, (p.y - e.y) / 40
      e.vz = 4
    end
  elseif e.state == "leap" then
    if e.ground and e.st > 4 then
      FX.shake(5)
      FX.ring(e.x, e.y, e.z, C_GRAY)
      Sfx.play("slam")
      contact(e, 4, 24)
      e.state = "idle"
      e.cd = enraged and 50 or 80
      e.vx, e.vy = 0, 0
    end
  elseif e.state == "web" then
    e.vx, e.vy = 0, 0
    if e.st == 20 or (enraged and e.st == 40) then shootAt(e, "web", 0.3, 5, 1.8, 1) end
    if e.st > 50 then e.state = "idle" e.cd = 70 end
  elseif e.state == "summon" then
    if e.st == 20 then
      minion("spider", e.x + 16, e.y)
      minion("spider", e.x - 16, e.y)
      Sfx.play("growl")
    end
    if e.st > 40 then e.state = "idle" e.cd = 90 end
  end
  Ent.physics(e)
end

-- Tengu Lord: hovers, feather volleys, dives, gusts
function Boss.u_tengulord(e)
  if common(e) then return end
  local p = P
  local a = POI.summit
  local g = groundAt(e.x, e.y)
  if e.state == "idle" then
    local ang = e.t / 90
    local tx, ty = a.x + math.cos(ang) * 40, a.y + math.sin(ang) * 26
    e.x, e.y = e.x + (tx - e.x) * 0.03, e.y + (ty - e.y) * 0.03
    e.z = e.z + ((g + 22) - e.z) * 0.05
    e.dir = math.atan(p.y - e.y, p.x - e.x)
    if e.cd == 0 then
      local r = rnd()
      e.st = 0
      if r < 0.45 then e.state = "volley" elseif r < 0.8 then e.state = "diveW" else e.state = "gust" end
      if e.hp < e.maxhp / 2 and not e.summoned then e.summoned = true e.state = "summon" end
    end
  elseif e.state == "volley" then
    if e.st % 22 == 10 then shootAt(e, "feather", 0.25, 3, 2.4, 2) end
    if e.st > 70 then e.state = "idle" e.cd = 60 end
  elseif e.state == "diveW" then
    e.flash = (e.st // 3) % 2 == 0 and 2 or 0
    if e.st > 26 then
      e.state = "dive"
      e.st = 0
      e.tx, e.ty = p.x, p.y
    end
  elseif e.state == "dive" then
    e.x, e.y = e.x + (e.tx - e.x) * 0.12, e.y + (e.ty - e.y) * 0.12
    e.z = e.z + ((g + 4) - e.z) * 0.15
    contact(e, 3, 14)
    if e.st > 24 then e.state = "idle" e.cd = 50 end
  elseif e.state == "gust" then
    if e.st > 20 and e.st < 70 then
      local dx, dy = p.x - e.x, p.y - e.y
      local l = math.max(1, math.sqrt(dx * dx + dy * dy))
      if l < 90 then
        p.x, p.y = p.x + dx / l * 0.9, p.y + dy / l * 0.9
        Ent.resolve(p)
        if e.st % 4 == 0 then FX.add(p.x - dx / l * 10, p.y - dy / l * 10, p.z + rnd(2, 14), dx / l * 2, dy / l * 2, 0, 16, C_WHITE, 0) end
      end
    end
    if e.st > 80 then e.state = "idle" e.cd = 60 end
  elseif e.state == "summon" then
    if e.st == 20 then minion("tengu", e.x + 20, e.y) minion("tengu", e.x - 20, e.y) Sfx.play("growl") end
    if e.st > 40 then e.state = "idle" e.cd = 60 end
  end
end

-- Orochi: heads surface from the lake around the island, bite or spit fire
function Boss.u_orochi(e)
  if common(e) then return end
  local p = P
  local a = POI.lake
  if e.state == "idle" then
    e.hidden = true
    e.hostile = false
    if e.st > 40 then
      -- surface at a water spot near the player
      for tries = 1, 12 do
        local ang = rnd() * TAU
        local r = rnd(18, 34)
        local x, y = p.x + math.cos(ang) * r, p.y + math.sin(ang) * r
        if isWaterAt(x, y) and dist(x, y, a.x, a.y) < 120 then
          e.x, e.y = x, y
          e.z = -3
          e.state = "rise"
          e.st = 0
          e.hidden = false
          e.hostile = true
          FX.burst(x, y, -2, 16, { C_WHITE, C_BLUE }, 1.6, 30)
          Sfx.play("splash")
          break
        end
      end
    end
  elseif e.state == "rise" then
    e.dir = math.atan(p.y - e.y, p.x - e.x)
    if e.st == 30 then
      if rnd() < 0.5 or dist(e.x, e.y, p.x, p.y) > 30 then shootAt(e, "fire", 0.35, 3, 1.6, 2)
      else e.state = "bite" e.st = 0 Sfx.play("growl") end
    end
    if e.st > 90 then
      e.state = "idle"
      e.st = 0
      FX.burst(e.x, e.y, -2, 12, { C_WHITE, C_BLUE }, 1.4, 24)
    end
  elseif e.state == "bite" then
    if e.st == 16 then
      local d = dist(e.x, e.y, p.x, p.y)
      if d < 30 then
        local nx, ny = (p.x - e.x) / d, (p.y - e.y) / d
        FX.burst(e.x + nx * 16, e.y + ny * 16, e.z + 10, 8, { C_RED, C_WHITE }, 1, 14)
        if d < 26 and math.abs(p.z - e.z) < 20 then Player.damage(3, e.x, e.y, "boss") end
      end
      Sfx.play("swing")
    end
    if e.st > 40 then e.state = "rise" e.st = 31 end
  end
end

-- Shuten-doji: smashes, fire rings, charges, summons oni
function Boss.u_shuten(e)
  if common(e) then return end
  local p = P
  local rage = e.hp < e.maxhp / 3
  if e.state == "idle" then
    e.dir = math.atan(p.y - e.y, p.x - e.x)
    local sp = rage and 0.7 or 0.45
    e.vx, e.vy = math.cos(e.dir) * sp, math.sin(e.dir) * sp
    if e.cd == 0 then
      local d = dist(e.x, e.y, p.x, p.y)
      e.st = 0
      local r = rnd()
      if d < 30 then e.state = "smashW"
      elseif r < 0.4 then e.state = "fire"
      elseif r < 0.8 then e.state = "chargeW"
      else e.state = "smashW" end
      if e.hp < e.maxhp / 2 and not e.summoned then e.summoned = true e.state = "summon" end
    end
    contact(e, 3)
  elseif e.state == "smashW" then
    e.vx, e.vy = 0, 0
    e.flash = (e.st // 3) % 2 == 0 and 2 or 0
    if e.st > (rage and 22 or 32) then
      e.state = "smash"
      e.st = 0
      local hx, hy = e.x + math.cos(e.dir) * 20, e.y + math.sin(e.dir) * 20
      FX.shake(6)
      FX.ring(hx, hy, e.z, C_RED)
      FX.burst(hx, hy, e.z, 20, { C_BROWN, C_GRAY, C_RED }, 2, 30)
      Sfx.play("slam")
      if dist(hx, hy, p.x, p.y) < 28 and math.abs(p.z - e.z) < 14 then Player.damage(5, e.x, e.y, "boss") end
    end
  elseif e.state == "smash" then
    if e.st > 24 then e.state = "idle" e.cd = rage and 30 or 50 end
  elseif e.state == "fire" then
    e.vx, e.vy = 0, 0
    if e.st == 20 or (rage and e.st == 45) then
      for k = 0, 11 do
        local a = k / 12 * TAU + e.st
        Proj.spawn("fire", e.x, e.y, e.z + 12, math.cos(a) * 1.4, math.sin(a) * 1.4, 0, false, 2)
      end
      Sfx.play("fire")
    end
    if e.st > 60 then e.state = "idle" e.cd = 50 end
  elseif e.state == "chargeW" then
    e.vx, e.vy = 0, 0
    e.dir = math.atan(p.y - e.y, p.x - e.x)
    e.flash = (e.st // 3) % 2 == 0 and 2 or 0
    if e.st > 26 then e.state = "charge" e.st = 0 e.vx, e.vy = math.cos(e.dir) * 2.6, math.sin(e.dir) * 2.6 Sfx.play("roar") end
  elseif e.state == "charge" then
    contact(e, 4, 16)
    if e.st % 5 == 0 then FX.dust(e.x, e.y, e.z, 3) end
    if e.st > 40 or e.hitWall then e.state = "idle" e.cd = 40 e.vx, e.vy = 0, 0 FX.shake(3) end
  elseif e.state == "summon" then
    e.vx, e.vy = 0, 0
    if e.st == 20 then minion("oni", e.x + 24, e.y) minion("oni", e.x - 24, e.y) Sfx.play("roar") end
    if e.st > 40 then e.state = "idle" e.cd = 60 end
  end
  local hit = Ent.physics(e)
  e.hitWall = hit
end

function Boss.draw(e)
  if e.hidden then return end
  local def = e.def
  local frames = def.spr
  local name = frames[1 + (e.t // 10) % #frames]
  if def.atk and (e.state == "smashW" or e.state == "smash" or e.state == "chargeW") then name = def.atk end
  if def.id == "orochi" and e.state == "bite" then name = "oro2" end
  local r = SPR[name]
  local _, flip = Ent.view(e.dir)
  local pm = e.pm
  if e.flash > 0 then pm = PM_WHITE end
  if e.state == "dead" and (e.st // 3) % 2 == 0 then pm = PM_WHITE end
  if e.state == "intro" and (e.st // 4) % 2 == 0 then pm = PM_RED end
  local z = e.z
  if def.id == "orochi" then
    local rise = e.state == "rise" and math.min(1, e.st / 20) or (e.state == "bite" and 1 or 0)
    z = -3 - (1 - rise) * 30
    FX.add(e.x + rnd(-6, 6), e.y + rnd(-4, 4), -2, 0, 0, 0.2, 10, C_WHITE, 0)
  else
    Ent.shadow(e, e.r)
  end
  Render.bill(r, e.x, e.y, z, flip, pm, e.sc)
  Render.setPM(nil)
end

-- ---------------------------------------------------------------------------
-- spirit shrines
-- ---------------------------------------------------------------------------
Shrine = { done = {}, trial = nil }
local TRIALFOES = { "bandit", "wolf", "bandit", "tengu", "kappa", "ronin", "snowwolf", "kappa" }

function Shrine.find(i)
  local cx, cy = (i - 1) % 240, (i - 1) // 240
  for _, s in ipairs(SHRINES) do
    if math.abs(s.cx - cx) <= 1 and math.abs(s.cy - cy) <= 1 then return s end
  end
end

function Shrine.interact(i)
  local s = Shrine.find(i)
  if not s then return end
  -- shrines are also rest points: heal and save
  P.spawnX, P.spawnY = s.x, s.y + 16
  if Shrine.done[s.id] then
    Player.heal(P.maxhp)
    Sfx.play("heal")
    Game.autosave()
    Dialog.say(s.name, "The shrine is at peace. You feel renewed. (Healed, game saved)")
    return
  end
  if s.trial == "combat" then
    if Shrine.trial then
      Dialog.say(s.name, "Defeat the spirits of the trial!")
      return
    end
    Dialog.ask(s.name, "A Trial of Strength. Defeat the shadows summoned here to earn a Spirit Orb.", { "Begin", "Later" }, function(c)
      if c ~= 1 then return end
      local kind = TRIALFOES[s.id] or "bandit"
      Shrine.trial = { s = s, foes = {} }
      for k = 1, 3 + (s.id % 2) do
        local a = k / 4 * TAU
        local e = Enemy.spawn(kind, s.x + math.cos(a) * 26, s.y + 18 + math.sin(a) * 18, { pm = Pal.mk({ [C_RED] = C_INDIGO, [C_BROWN] = C_NIGHT, [C_WOOD] = C_INDIGO, [C_GRAY] = C_INDIGO }) })
        e.state = "chase"
        e.always = true
        e.minion = true
        table.insert(Shrine.trial.foes, e)
      end
      Music.play("boss")
      Sfx.play("roar")
    end)
  else
    Dialog.say(s.name, "A Trial of Agility. Climb the stone pillars and claim the Spirit Orb at the top.")
  end
end

function Shrine.update()
  local t = Shrine.trial
  if t then
    local alive = 0
    for _, e in ipairs(t.foes) do if e.alive and e.hp > 0 then alive = alive + 1 end end
    if alive == 0 then
      Shrine.trial = nil
      Shrine.complete(t.s)
      Music.region()
    elseif dist(P.x, P.y, t.s.x, t.s.y) > 160 or P.state == "dead" then
      for _, e in ipairs(t.foes) do e.alive = false end
      Shrine.trial = nil
      UI.toast("The trial fades...")
      Music.region()
    end
  end
  -- spire trials: touch the orb on the highest pillar
  for _, s in ipairs(SHRINES) do
    if s.top and not Shrine.done[s.id] then
      local ox, oy, oz = s.top[1] * 8 + 4, s.top[2] * 8 + 4, s.top[3]
      if dist(P.x, P.y, ox, oy) < 8 and math.abs(P.z - oz) < 6 then
        Shrine.complete(s)
      end
    end
  end
end

function Shrine.complete(s)
  Shrine.done[s.id] = true
  P.orbs = P.orbs + 1
  Sfx.play("upgrade")
  FX.burst(P.x, P.y, P.z + 10, 24, { C_WHITE, C_BLUE, C_GOLD }, 2, 40)
  UI.banner("Spirit Orb obtained! (" .. P.orbs .. ")", "Offer 4 orbs at the Kannon statue in Kyo.")
  Game.autosave()
end

function Shrine.drawOrbs()
  for _, s in ipairs(SHRINES) do
    if s.top and not Shrine.done[s.id] then
      local ox, oy, oz = s.top[1] * 8 + 4, s.top[2] * 8 + 4, s.top[3]
      if dist(ox, oy, Cam.x, Cam.y) < 300 then
        Render.bill(SPR.orb, ox, oy, oz + 3 + math.sin(Frame / 12) * 2, false, nil, 1, 2)
      end
    end
  end
end

-- Kannon statue: trade 4 orbs for a heart or stamina
function Shrine.statue()
  if P.orbs < 4 then
    Dialog.say("Kannon Statue", "The goddess of mercy waits. Offer 4 Spirit Orbs for her blessing. (You have " .. P.orbs .. ")")
    return
  end
  Dialog.ask("Kannon Statue", "Offer 4 Spirit Orbs. Which blessing do you seek?", { "Heart container", "Stamina vessel" }, function(c)
    if c == 1 and P.maxhp < 48 then
      P.orbs = P.orbs - 4
      P.maxhp = P.maxhp + 4
      P.hp = P.maxhp
      UI.banner("Heart container! Max hearts " .. (P.maxhp // 4))
    elseif c == 2 and P.maxstam < 200 then
      P.orbs = P.orbs - 4
      P.maxstam = P.maxstam + 25
      P.stam = P.maxstam
      UI.banner("Stamina vessel! Stamina " .. P.maxstam)
    else
      return
    end
    Sfx.play("upgrade")
    Game.autosave()
  end)
end

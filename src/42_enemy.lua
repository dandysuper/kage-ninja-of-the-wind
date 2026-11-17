-- ============================================================================
--  42 ENEMIES - data-driven foes with a telegraphed windup before each hit.
--  idle -> chase -> windup (flashing) -> strike -> recover; hurt knocks back.
--  Enemies cannot jump: climbing a ledge is a valid escape (except flyers,
--  ghosts and ranged foes).
-- ============================================================================
Enemy = {}
ETYPE = {
  bandit = { spr = { "ban_s1", "ban_s2" }, atk = "ban_atk", hp = 4, sp = 0.72, dmg = 2, aggro = 80, reach = 13, windup = 22, cd = 46, r = 3,
    drops = { { "ryo", 2, 6 }, { "rice", 0, 1 } }, name = "Bandit" },
  ronin = { base = "bandit", pm = { [C_WOOD] = C_INDIGO, [C_BROWN] = C_NIGHT, [C_RED] = C_GRAY, [C_TAN] = C_GRAY }, hp = 10, dmg = 3, sp = 0.85,
    windup = 18, name = "Ronin", drops = { { "ryo", 10, 18 }, { "iron", 0, 1 } } },
  wolf = { spr = { "wolf1", "wolf2" }, hp = 3, sp = 1.12, dmg = 2, aggro = 90, reach = 12, windup = 14, cd = 40, r = 4, lunge = true,
    drops = { { "meat", 0, 1 }, { "pelt", 0, 1 } }, name = "Wolf", pack = true },
  snowwolf = { base = "wolf", pm = { [C_GRAY] = C_WHITE, [C_WHITE] = C_CREAM, [C_INDIGO] = C_GRAY }, hp = 5, dmg = 3, name = "Snow Wolf",
    drops = { { "meat", 1, 1 }, { "pelt", 1, 2 } } },
  boar = { spr = { "boar1", "boar2" }, hp = 5, sp = 0.62, dmg = 3, aggro = 70, reach = 13, windup = 28, cd = 70, r = 5, charge = true,
    drops = { { "meat", 1, 2 } }, name = "Boar" },
  kappa = { spr = { "kap1", "kap2" }, hp = 4, sp = 0.75, dmg = 2, aggro = 70, reach = 12, windup = 18, cd = 50, r = 3, hop = true, swims = true,
    drops = { { "cucumber", 0, 1 }, { "fish", 0, 1 }, { "ryo", 1, 4 } }, name = "Kappa" },
  tengu = { spr = { "ten1", "ten2" }, hp = 5, sp = 0.85, dmg = 2, aggro = 110, reach = 12, windup = 20, cd = 70, r = 4, fly = true, hover = 16,
    ranged = "feather", range = 70, drops = { { "feather", 1, 2 }, { "ryo", 2, 6 } }, name = "Tengu", anim = 6 },
  yurei = { spr = { "yur1", "yur2" }, hp = 4, sp = 0.5, dmg = 2, aggro = 100, reach = 12, windup = 22, cd = 60, r = 3, ghost = true, hover = 3,
    night = true, drops = { { "essence", 1, 1 } }, name = "Yurei", front = true },
  onibi = { spr = { "wisp1", "wisp2" }, hp = 2, sp = 0.55, dmg = 2, aggro = 110, reach = 0, ranged = "fire", range = 80, cd = 100, r = 3, fly = true,
    hover = 10, night = true, light = 26, drops = { { "ember", 1, 1 } }, name = "Onibi", front = true, anim = 6 },
  oni = { spr = { "oni1", "oni1" }, atk = "oni_atk", hp = 16, sp = 0.48, dmg = 4, aggro = 90, reach = 19, windup = 34, cd = 70, r = 6, smash = true,
    drops = { { "iron", 1, 2 }, { "ryo", 12, 24 } }, name = "Oni", tall = 8, heavy = true },
  spider = { spr = { "spi1", "spi2" }, hp = 3, sp = 1.0, dmg = 2, aggro = 80, reach = 11, windup = 16, cd = 50, r = 4, ranged = "web", range = 60,
    drops = { { "silk", 1, 2 } }, name = "Spider" },
  kitsune = { spr = { "fox1", "fox2" }, hp = 6, sp = 1.2, dmg = 2, aggro = 100, reach = 12, windup = 16, cd = 45, r = 4, blink = true, ranged = "fire",
    range = 60, drops = { { "ryo", 10, 25 } }, name = "Kitsune" },
}
for k, t in pairs(ETYPE) do
  if t.base then
    local b = ETYPE[t.base]
    for kk, vv in pairs(b) do if t[kk] == nil then t[kk] = vv end end
  end
  t.id = k
end

function Enemy.spawn(kind, x, y, opt)
  local T = ETYPE[kind]
  opt = opt or {}
  local e = Ent.add({ kind = "enemy", et = T, x = x, y = y, r = T.r, hp = (opt.hp or T.hp), maxhp = (opt.hp or T.hp), hostile = true,
    state = "idle", st = 0, hx = x, hy = y, dir = rnd() * TAU, cd = 0, flash = 0, sc = opt.sc or 1, step = 4.5,
    fly = T.fly, hover = T.hover, dry = not T.swims, group = opt.group, pm = opt.pm or (T.pm and Pal.mk(T.pm)) })
  e.update = Enemy.update
  e.draw = Enemy.draw
  e.light = T.light
  if T.fly then e.z = groundAt(x, y) + (T.hover or 10) end
  if T.ghost then e.z = groundAt(x, y) + (T.hover or 3) end
  return e
end

function Enemy.hurt(e, dmg, sx, sy, kb)
  if e.hp <= 0 or e.inv and e.inv > 0 then return end
  e.hp = e.hp - dmg
  e.flash = 8
  e.inv = 6
  FX.burst(e.x, e.y, e.z + 8, 6, { C_WHITE, C_RED, C_GOLD }, 1.2, 14)
  FX.text(e.x, e.y, e.z + 18, tostring(dmg), C_GOLD)
  Sfx.play("hit")
  if not e.boss then
    local dx, dy = e.x - sx, e.y - sy
    local l = math.sqrt(dx * dx + dy * dy) + 0.001
    local k = (e.et and e.et.heavy) and kb * 0.4 or kb
    e.vx, e.vy = dx / l * k, dy / l * k
    if e.state == "windup" and not (e.et and e.et.heavy) then e.state = "recover" e.st = 10 end
    if e.state == "idle" then e.state = "chase" end
    e.state = e.state == "windup" and "windup" or e.state
    e.hurtT = 10
  end
  if e.onHurt then e:onHurt(dmg) end
  if e.hp <= 0 then Enemy.kill(e) end
end

function Enemy.kill(e)
  e.hp = 0
  e.state = "dead"
  e.st = 0
  e.hostile = false
  Sfx.play("kill")
  FX.burst(e.x, e.y, e.z + 8, 16, { C_WHITE, C_GRAY, C_NIGHT, C_RED }, 1.6, 30)
  local T = e.et
  if T and T.drops then
    local luck = Inv.has("charm") and 1.5 or 1
    for _, dr in ipairs(T.drops) do
      local n = rnd(dr[2], dr[3])
      if dr[1] == "ryo" then n = flr(n * luck) end
      if n > 0 then Drops.spawn(e.x, e.y, e.z + 6, dr[1], n) end
    end
  end
  if T then
    P.kills[T.id] = (P.kills[T.id] or 0) + 1
    Quest.event("kill", T.id)
  end
  if e.onDeath then e:onDeath() end
end

local function faceTo(e, tx, ty) e.dir = math.atan(ty - e.y, tx - e.x) end

local function steer(e, tx, ty, sp)
  local dx, dy = tx - e.x, ty - e.y
  local l = math.sqrt(dx * dx + dy * dy)
  if l < 0.5 then e.vx, e.vy = e.vx * 0.7, e.vy * 0.7 return l end
  local a = math.atan(dy, dx) + (e.avoid or 0)
  e.vx = approach(e.vx, math.cos(a) * sp, 0.15)
  e.vy = approach(e.vy, math.sin(a) * sp, 0.15)
  e.dir = a
  return l
end

function Enemy.update(e)
  local T = e.et
  if e.flash > 0 then e.flash = e.flash - 1 end
  if e.inv and e.inv > 0 then e.inv = e.inv - 1 end
  if e.state == "dead" then
    e.st = e.st + 1
    if e.st > 24 then e.alive = false end
    return
  end
  if T.night and Clock.isDay() and e.t % 60 == 0 then
    FX.burst(e.x, e.y, e.z + 8, 8, { C_WHITE, C_BLUE }, 1, 20)
    e.alive = false
    return
  end
  local p = P
  local dpx, dpy = p.x - e.x, p.y - e.y
  local dp = math.sqrt(dpx * dpx + dpy * dpy)
  local pAlive = p.state ~= "dead"
  local dz = p.z - e.z
  e.st = e.st + 1
  if e.cd > 0 then e.cd = e.cd - 1 end
  if e.hurtT and e.hurtT > 0 then
    e.hurtT = e.hurtT - 1
    e.vx, e.vy = e.vx * 0.85, e.vy * 0.85
  elseif e.state == "idle" then
    if e.st > 80 + rnd(60) or not e.wx then
      e.st = 0
      local a = rnd() * TAU
      e.wx, e.wy = e.hx + math.cos(a) * rnd(8, 32), e.hy + math.sin(a) * rnd(8, 32)
    end
    steer(e, e.wx, e.wy, T.sp * 0.4)
    if pAlive and dp < T.aggro and math.abs(dz) < 40 and not Game.safe then
      e.state = "chase"
      e.st = 0
      if T.pack then
        for _, o in ipairs(ENTS) do
          if o.alive and o.et == T and o.state == "idle" and dist(o.x, o.y, e.x, e.y) < 60 then o.state = "chase" end
        end
      end
    end
  elseif e.state == "chase" then
    local leash = dist(e.x, e.y, e.hx, e.hy)
    if not pAlive or dp > T.aggro * 2.2 or leash > 260 or Game.safe then
      e.state = "home"
    elseif T.ranged and dp < (T.range or 70) and dp > (T.reach > 0 and T.reach * 2 or 20) and e.cd == 0 and math.abs(dz) < 50 then
      e.state = "shoot"
      e.st = 0
      e.vx, e.vy = 0, 0
    elseif T.reach > 0 and dp < T.reach and math.abs(dz) < 12 + (T.tall or 0) and e.cd == 0 then
      e.state = "windup"
      e.st = 0
      e.vx, e.vy = 0, 0
      faceTo(e, p.x, p.y)
      Sfx.play("growl")
    else
      local keep = (T.reach == 0) and 50 or 0
      if dp > keep then steer(e, p.x, p.y, T.sp) else e.vx, e.vy = e.vx * 0.8, e.vy * 0.8 end
      if T.blink and e.st % 120 == 60 and dp > 30 then
        -- kitsune trick: vanish and reappear beside you
        FX.burst(e.x, e.y, e.z + 6, 10, { C_GOLD, C_RED }, 1, 20)
        local a = rnd() * TAU
        e.x, e.y = p.x + math.cos(a) * 22, p.y + math.sin(a) * 22
        Ent.resolve(e)
        e.z = groundAt(e.x, e.y)
        Sfx.play("blink")
      end
    end
  elseif e.state == "home" then
    if steer(e, e.hx, e.hy, T.sp * 0.7) < 6 then e.state = "idle" e.hp = math.min(e.maxhp, e.hp + 1) end
    if pAlive and dp < T.aggro * 0.6 and not Game.safe then e.state = "chase" end
  elseif e.state == "windup" then
    e.vx, e.vy = e.vx * 0.7, e.vy * 0.7
    if e.st >= T.windup then
      e.state = "strike"
      e.st = 0
      Sfx.play("swing")
      if T.lunge then
        local a = e.dir
        e.vx, e.vy = math.cos(a) * 2.6, math.sin(a) * 2.6
      elseif T.charge then
        local a = e.dir
        e.vx, e.vy = math.cos(a) * 2.4, math.sin(a) * 2.4
        e.chargeT = 34
      end
      if T.smash then
        FX.shake(4)
        FX.ring(e.x + math.cos(e.dir) * 12, e.y + math.sin(e.dir) * 12, e.z, C_BROWN)
        Sfx.play("slam")
        local hx, hy = e.x + math.cos(e.dir) * 12, e.y + math.sin(e.dir) * 12
        if dist(hx, hy, p.x, p.y) < 20 and math.abs(dz) < 14 then Player.damage(T.dmg, e.x, e.y, T.id) end
      elseif not T.charge and not T.lunge then
        if dp < T.reach * 1.35 and math.abs(dz) < 12 + (T.tall or 0) then Player.damage(T.dmg, e.x, e.y, T.id) end
      end
    end
  elseif e.state == "strike" then
    if (T.lunge or T.charge) and dp < (e.r + 5) and math.abs(dz) < 10 and not e.struck then
      e.struck = Player.damage(T.dmg, e.x, e.y, T.id) or true
    end
    if T.charge then
      e.chargeT = e.chargeT - 1
      if e.st % 6 == 0 then FX.dust(e.x, e.y, e.z, 2) end
      if e.chargeT <= 0 or e.hitWall then e.state = "recover" e.st = 0 end
    else
      e.vx, e.vy = e.vx * 0.86, e.vy * 0.86
      if e.st > 12 then e.state = "recover" e.st = 0 end
    end
  elseif e.state == "recover" then
    e.vx, e.vy = e.vx * 0.8, e.vy * 0.8
    if e.st > 14 then
      e.state = "chase"
      e.cd = T.cd
      e.struck = nil
      e.st = 0
    end
  elseif e.state == "shoot" then
    faceTo(e, p.x, p.y)
    if e.st == 18 then
      local a = e.dir
      local spd = T.ranged == "fire" and 1.5 or 2.2
      local tz = (p.z + 7 - (e.z + 8)) / math.max(dp, 1) * spd
      Proj.spawn(T.ranged, e.x, e.y, e.z + 8, math.cos(a) * spd, math.sin(a) * spd, tz, false, T.ranged == "web" and 1 or T.dmg)
      Sfx.play("throw")
    end
    if e.st > 34 then e.state = "chase" e.cd = T.cd e.st = 0 end
  end

  -- movement
  if T.ghost then
    e.x, e.y = e.x + e.vx, e.y + e.vy
    e.z = groundAt(e.x, e.y) + (T.hover or 3) + math.sin(e.t / 15) * 2
  else
    local px0, py0 = e.x, e.y
    local hit = Ent.physics(e)
    if T.hop and e.ground and (math.abs(e.vx) + math.abs(e.vy)) > 0.3 and e.t % 24 == 0 then e.vz = 1.4 end
    e.hitWall = hit
    -- simple obstacle avoidance when stuck
    if hit and e.state == "chase" then
      e.avoid = (e.avoidT and e.avoidT > 0) and e.avoid or ((rnd() < 0.5) and 1.1 or -1.1)
      e.avoidT = 40
    end
    if e.avoidT then
      e.avoidT = e.avoidT - 1
      if e.avoidT <= 0 then e.avoid, e.avoidT = 0, nil end
    end
    if T.fly then e.z = e.z + math.sin(e.t / 10) * 0.3 end
  end
end

function Enemy.draw(e)
  local T = e.et
  local frames = T.spr
  local name = frames[1 + (e.t // (T.anim or 10)) % #frames]
  if (e.state == "windup" or e.state == "strike") and T.atk then name = T.atk end
  if math.abs(e.vx) + math.abs(e.vy) < 0.1 and e.state ~= "windup" and not T.anim then name = frames[1] end
  local r = SPR[name]
  if not r then return end
  local flip = false
  if not T.front then
    local _, f = Ent.view(e.dir)
    flip = f
  end
  local pm = e.pm
  if e.flash > 0 then pm = PM_WHITE
  elseif e.state == "windup" and (e.st // 3) % 2 == 0 then pm = PM_RED end
  if e.state == "dead" then
    if (e.st // 2) % 2 == 0 then return end
    pm = PM_WHITE
  end
  if not T.ghost then Ent.shadow(e, (e.r + 1) * e.sc) end
  local z = e.z
  if T.ghost or T.fly then z = z + math.sin(e.t / 12) * 1.5 end
  Render.bill(r, e.x, e.y, z, flip, pm, e.sc)
  Render.setPM(nil)
  -- health bar when hurt
  if e.hp < e.maxhp and e.hp > 0 and not e.boss then
    local sx, sy = proj(e.x, e.y, z)
    local w = 12
    local top = sy - r[4] * e.sc - 4
    rect(sx - w / 2, top, w, 2, C_NIGHT)
    rect(sx - w / 2, top, w * e.hp / e.maxhp, 2, C_RED)
  end
end

-- ---------------------------------------------------------------------------
-- spawning: camps (fixed, respawn), wildlife (day), yokai (night)
-- ---------------------------------------------------------------------------
CAMPS = {}
function Enemy.camp(kind, cx, cy, n, opt)
  CAMPS[#CAMPS + 1] = { kind = kind, x = cx * 8 + 4, y = cy * 8 + 4, n = n or 1, opt = opt or {}, alive = 0, next = 0, members = {} }
end

local WILD = {
  sakura = { "wolf", "boar" }, bamboo = { "wolf", "spider", "boar" }, plains = { "wolf", "boar", "bandit" },
  snow = { "snowwolf", "tengu" }, haunted = { "spider", "wolf" }, coast = { "bandit", "boar" },
  marsh = { "kappa", "spider" }, volcano = { "oni" },
}

function Enemy.director()
  local p = P
  local now = Clock.total
  -- camps
  for _, c in ipairs(CAMPS) do
    local d = dist(c.x, c.y, p.x, p.y)
    local alive = 0
    for _, m in ipairs(c.members) do if m.alive and m.hp > 0 then alive = alive + 1 end end
    c.alive = alive
    if alive == 0 and d < 230 and d > 120 and now >= c.next and not c.done then
      c.members = {}
      for k = 1, c.n do
        local a = k / c.n * TAU
        local e = Enemy.spawn(c.kind, c.x + math.cos(a) * 10, c.y + math.sin(a) * 10, c.opt)
        e.camp = c
        c.members[#c.members + 1] = e
      end
      c.next = now + OBJ_DAY * (c.opt.respawn or 1)
      if c.opt.once then c.done = true end
    end
  end
  if now % 240 ~= 0 or Game.safe then return end
  local count = 0
  for _, e in ipairs(ENTS) do
    if e.alive and e.kind == "enemy" and not e.camp and dist(e.x, e.y, p.x, p.y) < 240 then count = count + 1 end
  end
  local night = not Clock.isDay()
  local limit = night and 5 or 3
  if count >= limit then return end
  -- pick a spot 120-170 units away on dry land, not in a town
  for tries = 1, 6 do
    local a = rnd() * TAU
    local r = rnd(120, 170)
    local x, y = p.x + math.cos(a) * r, p.y + math.sin(a) * r
    local cx, cy = flr(x / 8), flr(y / 8)
    if inmap(cx, cy) then
      local i = cidx(cx, cy)
      if (WF[i] & (F_WATER | F_TOWN | F_NOSPAWN | F_ROOF | F_MODEL)) == 0 and WH[i] >= 0 then
        local biome = REG[WR[i]].biome
        local kind
        if night then
          kind = (rnd() < 0.55) and "yurei" or "onibi"
          if biome == "haunted" and rnd() < 0.3 then kind = "kitsune" end
        else
          if rnd() < 0.5 then return end
          kind = pick(WILD[biome])
        end
        local n = (ETYPE[kind].pack) and rnd(2, 3) or 1
        for k = 1, n do Enemy.spawn(kind, x + k * 6, y + k * 3) end
        return
      end
    end
  end
end

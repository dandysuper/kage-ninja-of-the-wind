-- ============================================================================
--  41 PLAYER - the ninja controller.
--  States: ground, air, climb, swim, plunge, dead. Attacks overlay ground/air.
--  Movement is camera-relative. Stamina (BotW wheel) drives sprint, climb,
--  glide and swim; running dry exhausts you until it fully refills.
-- ============================================================================
Player = {}
P = nil

local WALK, RUN, SWIM_SP, GLIDE_SP = 0.95, 1.6, 0.6, 1.55
local JUMP_V, DJUMP_V = 2.62, 2.45

function Player.new(x, y)
  local p = {
    kind = "player", x = x, y = y, r = 3, step = 4.5, dir = math.pi / 2, state = "ground",
    vx = 0, vy = 0, vz = 0, t = 0, ground = true,
    hp = 16, maxhp = 16, stam = 100, maxstam = 100, hunger = 85, ryo = 30, orbs = 0, seeds = 0,
    exhausted = false, stamDelay = 0, iframes = 0, flash = 0, jumps = 0, coyote = 0, anim = 0,
    atk = 0, combo = 0, queued = false, hitDone = false, pushT = 0, fallTop = 0, glide = false,
    weapon = "bokken", armor = nil, light = nil, lightFuel = 0, has = {}, warm = 0, cold = 0, dark = 0,
    safeX = x, safeY = y, safeZ = 0, spawnX = x, spawnY = y, kills = {},
  }
  p.z = groundAt(x, y)
  P = p
  return p
end

local function hasAbility(k) return P.has[k] end

-- world move vector from screen-space arrows
local function inputDir()
  local ix, iy = In.axis()
  if ix == 0 and iy == 0 then return 0, 0, false end
  local rx, ry = Cam.right()
  local fx, fy = Cam.fwd()
  local wx, wy = rx * ix - fx * iy, ry * ix - fy * iy
  local l = math.sqrt(wx * wx + wy * wy)
  return wx / l, wy / l, true
end

local function useStam(n)
  local p = P
  p.stam = p.stam - n
  p.stamDelay = 40
  if p.stam <= 0 then
    p.stam = 0
    p.exhausted = true
    Sfx.play("tired")
  end
end

function Player.damage(dmg, sx, sy, kind)
  local p = P
  if p.iframes > 0 or p.state == "dead" or Game.cutscene then return false end
  local def = (p.armor and ITEM[p.armor].def) or 0
  dmg = math.max(1, dmg - def)
  p.hp = p.hp - dmg
  p.iframes = 50
  p.flash = 10
  FX.shake(3)
  FX.hitstop(4)
  Sfx.play("hurt")
  if sx then
    local dx, dy = p.x - sx, p.y - sy
    local l = math.sqrt(dx * dx + dy * dy) + 0.001
    p.vx, p.vy = dx / l * 2.2, dy / l * 2.2
    if p.state == "ground" then p.vz = 1.2 p.state = "air" end
  end
  if p.state == "climb" then p.state = "air" end
  if p.hp <= 0 then
    p.hp = 0
    Player.die(kind)
  end
  return true
end

function Player.heal(q)
  P.hp = math.min(P.maxhp, P.hp + q)
end

function Player.die(why)
  local p = P
  p.state = "dead"
  p.deadT = 0
  p.vx, p.vy = 0, 0
  Sfx.play("die")
  Music.play(nil)
  Game.onDeath(why)
end

function Player.respawn()
  local p = P
  p.x, p.y = p.spawnX, p.spawnY
  p.z = groundAt(p.x, p.y)
  p.hp = p.maxhp
  p.stam = p.maxstam
  p.exhausted = false
  p.hunger = math.max(p.hunger, 50)
  p.state = "ground"
  p.vx, p.vy, p.vz = 0, 0, 0
  p.iframes = 120
  p.dark = 0
  Cam.x, Cam.y, Cam.z = p.x, p.y, p.z
end

-- ---------------------------------------------------------------------------
-- combat
-- ---------------------------------------------------------------------------
local function weaponDmg()
  local w = ITEM[P.weapon or "bokken"]
  return (w and w.dmg) or 1
end
Player.weaponDmg = weaponDmg

-- the cell in front of the player (for harvesting)
local function frontObject(reach)
  local p = P
  local best, bd = nil, 1e9
  local fx, fy = math.cos(p.dir), math.sin(p.dir)
  local cx, cy = flr(p.x / 8), flr(p.y / 8)
  for yy = cy - 2, cy + 2 do
    for xx = cx - 2, cx + 2 do
      if xx >= 0 and yy >= 0 and xx < 240 and yy < 112 then
        local i = yy * 240 + xx + 1
        local o = WO[i]
        if o > 0 then
          local ox, oy = objPos(i)
          local dx, dy = ox - p.x, oy - p.y
          local d = math.sqrt(dx * dx + dy * dy)
          local oz = (WF[i] & F_ROOF) ~= 0 and groundAt(ox, oy) or math.max(WH[i], 0)
          if d < reach and (d < 5 or (dx * fx + dy * fy) / d > 0.35) and math.abs(oz - p.z) < 14 then
            if d < bd then best, bd = i, d end
          end
        end
      end
    end
  end
  return best, bd
end
Player.frontObject = frontObject

local function swingHits()
  local p = P
  local dmg = weaponDmg()
  if p.combo == 3 then dmg = dmg + 1 end
  local fx, fy = math.cos(p.dir), math.sin(p.dir)
  local hitAny = false
  for _, e in ipairs(ENTS) do
    if e.alive and e.hostile and e.hp and e.hp > 0 then
      local dx, dy = e.x - p.x, e.y - p.y
      local d = math.sqrt(dx * dx + dy * dy)
      local reach = 17 + (e.r or 3)
      if d < reach and math.abs((e.z + (e.hz or 6)) - (p.z + 6)) < 16 + (e.tall or 0) and (d < 6 or (dx * fx + dy * fy) / d > 0.2) then
        Enemy.hurt(e, dmg, p.x, p.y, p.combo == 3 and 2.6 or 1.6)
        hitAny = true
      end
    end
  end
  if not hitAny then
    local i = frontObject(14)
    if i then World.hit(i) end
  end
  if hitAny then FX.hitstop(3) end
end

local function startAttack()
  local p = P
  if p.atk > 0 then
    if p.atk < 9 then p.queued = true end
    return
  end
  p.combo = (p.comboT and p.comboT > 0) and (p.combo % 3) + 1 or 1
  p.atk = p.combo == 3 and 22 or 16
  p.hitDone = false
  p.queued = false
  Sfx.play("swing")
end

local function throwShuriken()
  local p = P
  if Inv.count("shuriken") <= 0 then
    UI.toast("No shuriken")
    return
  end
  Inv.take("shuriken", 1)
  local fx, fy = math.cos(p.dir), math.sin(p.dir)
  Proj.spawn("shuriken", p.x + fx * 4, p.y + fy * 4, p.z + 8, fx * 3.6, fy * 3.6, 0, true, 2)
  Sfx.play("throw")
end

-- ---------------------------------------------------------------------------
-- interaction (A)
-- ---------------------------------------------------------------------------
function Player.findInteract()
  local p = P
  local fx, fy = math.cos(p.dir), math.sin(p.dir)
  -- NPCs and interactive entities first
  local best, bd = nil, 20
  for _, e in ipairs(ENTS) do
    if e.alive and e.interact then
      local dx, dy = e.x - p.x, e.y - p.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < (e.ireach or 16) and math.abs(e.z - p.z) < 16 and d < bd then best, bd = e, d end
    end
  end
  if best then return "ent", best end
  local i = frontObject(13)
  if i then
    local d = OBJ[WO[i]]
    if d.hand or d.talk then return "obj", i end
  end
  -- pagoda summit
  for _, t in ipairs(TOWERS) do
    if dist(p.x, p.y, t.x, t.y) < 16 and p.z >= t.top - 2 then return "tower", t end
  end
  return nil
end

local function interact()
  local kind, tgt = Player.findInteract()
  if kind == "ent" then
    tgt:interact()
  elseif kind == "obj" then
    World.interact(tgt)
  elseif kind == "tower" then
    Quest.tower(tgt)
  end
end

-- ---------------------------------------------------------------------------
-- update
-- ---------------------------------------------------------------------------
function Player.update()
  local p = P
  p.anim = p.anim + 1
  if p.iframes > 0 then p.iframes = p.iframes - 1 end
  if p.flash > 0 then p.flash = p.flash - 1 end
  if p.comboT and p.comboT > 0 then p.comboT = p.comboT - 1 end

  if p.state == "dead" then
    p.deadT = p.deadT + 1
    return
  end

  -- hotkeys
  if In.p.rotl then Cam.ta = Cam.ta + math.pi / 4 Sfx.play("menu") end
  if In.p.rotr then Cam.ta = Cam.ta - math.pi / 4 Sfx.play("menu") end
  for k = 1, 10 do
    if In.p["s" .. k] then UI.useSlot(k) end
  end

  local mx, my, moving = inputDir()
  local st = p.state
  local f = flagsAt(p.x, p.y)
  local inWater = (f & F_WATER) ~= 0 and p.z <= -2.5

  -- stamina regen
  if p.stamDelay > 0 then p.stamDelay = p.stamDelay - 1
  elseif st == "ground" and p.stam < p.maxstam then
    p.stam = math.min(p.maxstam, p.stam + (p.exhausted and 0.45 or 0.75))
    if p.stam >= p.maxstam then p.exhausted = false end
  end

  if st == "ground" then
    local sp = WALK
    local running = In.h.run and moving and not p.exhausted and p.atk == 0
    if running then sp = RUN useStam(0.32) end
    if (f & F_SHALLOW) ~= 0 then sp = sp * 0.65 end
    if p.atk > 0 then sp = p.atk > (p.combo == 3 and 16 or 11) and 0.9 or 0.15 end
    local tx, ty = mx * sp, my * sp
    if p.atk > 0 and not moving then
      tx, ty = math.cos(p.dir) * sp * 0.6, math.sin(p.dir) * sp * 0.6
    end
    p.vx = approach(p.vx, tx, 0.28)
    p.vy = approach(p.vy, ty, 0.28)
    if moving and p.atk == 0 then p.dir = math.atan(my, mx) end
    p.running = running
    if In.p.jump then
      p.vz = JUMP_V
      p.state = "air"
      p.jumps = 1
      p.fallTop = p.z
      Sfx.play("jump")
      FX.dust(p.x, p.y, p.z, 3)
    end
    if In.p.atk then startAttack() end
    if In.p.throw then throwShuriken() end
    if In.p.use then interact() end
    if In.p.ok then interact() end
    if inWater then p.state = "swim" end
  elseif st == "air" then
    local sp = p.glide and GLIDE_SP or (p.running and RUN or WALK * 1.05)
    p.vx = approach(p.vx, mx * sp, p.glide and 0.1 or 0.14)
    p.vy = approach(p.vy, my * sp, p.glide and 0.1 or 0.14)
    if moving then p.dir = math.atan(my, mx) end
    if In.p.jump then
      if p.coyote > 0 then
        p.vz = JUMP_V
        p.jumps = 1
        p.coyote = 0
        p.fallTop = p.z
        Sfx.play("jump")
      elseif hasAbility("djump") and p.jumps < 2 then
        p.vz = DJUMP_V
        p.jumps = 2
        p.fallTop = p.z
        Sfx.play("djump")
        FX.ring(p.x, p.y, p.z, C_GREEN)
      end
    end
    p.glide = false
    if In.h.jump and p.vz < -0.3 and hasAbility("kite") and not p.exhausted and p.stam > 0 then
      p.glide = true
      if p.vz < -0.42 then p.vz = -0.42 end
      useStam(0.2)
      p.fallTop = p.z
    end
    if In.p.atk then
      if p.z - groundAt(p.x, p.y) > 10 then
        p.state = "plunge"
        p.vz = -4.2
        p.vx, p.vy = 0, 0
        Sfx.play("swing")
      else
        startAttack()
      end
    end
    if In.p.throw then throwShuriken() end
    if p.coyote > 0 then p.coyote = p.coyote - 1 end
  elseif st == "climb" then
    p.vx, p.vy = 0, 0
    local ix, iy = In.axis()
    local nx, ny = p.wnx, p.wny
    -- tangent oriented so that "right" on screen moves right
    local tx, ty = -ny, nx
    local ca, sa = math.cos(Cam.a), math.sin(Cam.a)
    if tx * ca + ty * sa < 0 then tx, ty = -tx, -ty end
    local climbing = (iy ~= 0 or ix ~= 0)
    if p.leap and p.leap > 0 then
      p.leap = p.leap - 1
      p.z = p.z + 1.6
    elseif iy < 0 then
      p.z = p.z + 0.55
    elseif iy > 0 then
      p.z = p.z - 0.7
    end
    if ix ~= 0 then
      p.x = p.x + tx * ix * 0.5
      p.y = p.y + ty * ix * 0.5
    end
    useStam(climbing and 0.3 or 0.08)
    p.stamDelay = 40
    if In.p.jump then
      if iy > 0 then
        -- push away from the wall
        p.state = "air"
        p.vz = 1.6
        p.vx, p.vy = nx * 1.4, ny * 1.4
        p.dir = math.atan(ny, nx)
      elseif p.stam > 10 then
        p.leap = 12
        useStam(14)
        Sfx.play("jump")
      end
    end
    -- still on a wall? probe one unit into it
    local qx, qy = p.x - nx * (p.r + 1.5), p.y - ny * (p.r + 1.5)
    local wallTop = groundAt(qx, qy)
    local g = groundAt(p.x, p.y)
    if p.z <= g then
      p.z = g
      p.state = "ground"
    elseif wallTop <= p.z + 3 then
      -- mantle over the top
      p.x, p.y = qx - nx * 2, qy - ny * 2
      p.z = groundAt(p.x, p.y)
      p.state = "ground"
      p.vz = 0
      Sfx.play("land")
    elseif p.exhausted then
      p.state = "air"
      p.vz = 0
      p.fallTop = p.z
    end
    p.dir = math.atan(-ny, -nx)
  elseif st == "swim" then
    local sp = SWIM_SP
    if In.h.run and moving and not p.exhausted then sp = 0.95 useStam(0.25) else useStam(moving and 0.09 or 0.05) end
    p.vx = approach(p.vx, mx * sp, 0.12)
    p.vy = approach(p.vy, my * sp, 0.12)
    if moving then p.dir = math.atan(my, mx) end
    if p.anim % 30 == 0 and moving then FX.ripple(p.x, p.y, -3) end
    if p.exhausted then
      -- too tired: sink and wash ashore at the last safe spot
      Player.damage(4, nil, nil, "drown")
      if p.state ~= "dead" then
        p.x, p.y, p.z = p.safeX, p.safeY, p.safeZ
        p.state = "ground"
        p.stam = p.maxstam * 0.5
        p.exhausted = false
        UI.toast("You washed ashore...")
      end
      return
    end
    -- X: leap out of the water onto a bank (or at a cliff, then climb it)
    if In.p.jump then
      p.state = "air"
      p.vz = JUMP_V * 1.1
      p.jumps = 1
      p.fallTop = p.z
      p.vx, p.vy = p.vx + math.cos(p.dir) * 0.6, p.vy + math.sin(p.dir) * 0.6
      useStam(6)
      Sfx.play("splash")
      FX.burst(p.x, p.y, -2, 10, { C_WHITE, C_BLUE }, 1.2, 20)
    end
  elseif st == "plunge" then
    p.vx, p.vy = 0, 0
  end

  -- attack timing
  if p.atk > 0 then
    p.atk = p.atk - 1
    local activeAt = (p.combo == 3) and 14 or 11
    if not p.hitDone and p.atk <= activeAt then
      p.hitDone = true
      swingHits()
      local fx, fy = math.cos(p.dir), math.sin(p.dir)
      FX.slash(p.x + fx * 9, p.y + fy * 9, p.z + 6, p.combo)
    end
    if p.atk == 0 then
      p.comboT = 14
      if p.queued then
        p.queued = false
        startAttack()
      end
    end
  end

  -- physics
  local wasGround = p.ground
  local preZ = p.z
  if p.state == "climb" then
    Ent.resolve(p)
  elseif p.state == "swim" then
    p.x, p.y = p.x + p.vx, p.y + p.vy
    -- banks up to one terrain step (4) above the water can be swum onto
    p.step = 7.5
    Ent.resolve(p)
    p.step = 4.5
    p.z = -3
    local g = groundAt(p.x, p.y)
    if not isWaterAt(p.x, p.y) and g <= p.z + 7.5 then
      p.z = g
      p.state = "ground"
      FX.burst(p.x, p.y, g, 6, { C_WHITE, C_BLUE }, 0.8, 14)
    end
  else
    local hit, wh, nx, ny = Ent.physics(p)
    -- climbing: pushing into a wall that is too tall to step on
    if hit and wh and wh > p.z + 4.5 and moving and (mx * nx + my * ny) < -0.6 and not p.exhausted and p.atk == 0 and p.state ~= "plunge" then
      p.pushT = p.pushT + 1
      local need = p.state == "air" and 2 or 7
      if p.pushT > need and wh < 400 then
        p.state = "climb"
        p.wnx, p.wny = nx, ny
        p.vz = 0
        p.glide = false
        p.pushT = 0
      end
    else
      p.pushT = 0
    end
    if p.state == "ground" and not p.ground then
      p.state = "air"
      p.coyote = 7
      p.fallTop = p.z
    elseif (p.state == "air" or p.state == "plunge") and p.ground then
      local fall = p.fallTop - p.z
      if p.state == "plunge" then
        FX.shake(4)
        Sfx.play("slam")
        FX.ring(p.x, p.y, p.z, C_WHITE)
        for _, e in ipairs(ENTS) do
          if e.alive and e.hostile and e.hp and e.hp > 0 and dist(e.x, e.y, p.x, p.y) < 22 then
            Enemy.hurt(e, weaponDmg() * 2, p.x, p.y, 3)
          end
        end
        p.atk = 0
      else
        Sfx.play("land")
      end
      FX.dust(p.x, p.y, p.z, 4)
      p.state = "ground"
      p.glide = false
      p.jumps = 0
      if fall > 46 then
        Player.damage(math.min(16, flr((fall - 46) / 10) + 2), nil, nil, "fall")
      end
    end
    if p.state == "air" and p.vz > 0 then p.fallTop = math.max(p.fallTop, p.z) end
    if inWater and p.state ~= "swim" and p.z <= -2.5 then p.state = "swim" p.glide = false end
  end

  -- remember safe ground for respawn after drowning/falling into hazards
  if p.state == "ground" and not isWaterAt(p.x, p.y) and (flagsAt(p.x, p.y) & F_HAZ) == 0 and p.anim % 20 == 0 then
    p.safeX, p.safeY, p.safeZ = p.x, p.y, p.z
  end
  if (flagsAt(p.x, p.y) & F_HAZ) ~= 0 and p.state == "ground" then
    if Player.damage(4, nil, nil, "lava") and p.state ~= "dead" then
      p.x, p.y, p.z = p.safeX, p.safeY, p.safeZ
    end
  end
  p.moving = moving
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------
function Player.sprite()
  local p = P
  local view, flip = Ent.view(p.dir)
  local walkF = (p.anim // 8) % 2
  local moving = (math.abs(p.vx) + math.abs(p.vy)) > 0.15
  local name
  if p.state == "climb" then
    name = "n_climb"
    flip = (p.anim // 12) % 2 == 0
    return name, flip
  elseif p.state == "swim" then
    return "n_swim", flip
  elseif p.state == "air" and p.glide then
    return "n_glide", flip
  end
  if p.atk > 0 then
    view = "s"
    name = (p.combo == 2) and "n_s_slash2" or "n_s_slash1"
    if p.combo == 3 then name = (p.atk > 11) and "n_s_slash1" or "n_s_slash2" end
    return name, flip
  end
  if p.state == "air" or p.state == "plunge" then
    return p.vz > 0 and "n_s_jump" or "n_s_fall", flip
  end
  if view == "s" then
    if moving then
      local k = (p.anim // (p.running and 5 or 7)) % 4
      name = (k == 0 or k == 2) and "n_s_idle" or (k == 1 and "n_s_walk1" or "n_s_walk2")
    else
      name = "n_s_idle"
    end
  elseif view == "f" then
    name = moving and "n_f_walk1" or "n_f_idle"
    if moving then flip = walkF == 1 end
  else
    name = moving and "n_b_walk1" or "n_b_idle"
    if moving then flip = walkF == 1 end
  end
  return name, flip
end

function Player.draw()
  local p = P
  if p.state == "dead" and p.deadT > 40 then return end
  if p.iframes > 0 and (p.anim // 3) % 2 == 0 and p.flash == 0 then
    Ent.shadow(p, 4)
    return
  end
  Ent.shadow(p, 4)
  local name, flip = Player.sprite()
  local r = SPR[name]
  local z = p.z
  if p.state == "swim" then z = -3 end
  -- x-ray silhouette when hidden behind terrain: draw flat silhouette first,
  -- then the real sprite depth-tested on top
  Pal.solid(C_INDIGO)
  Render.billFlat(r, p.x, p.y, z, flip)
  Render.setPM(nil)
  Pal.reset()
  local pm = nil
  if p.flash > 0 then pm = PM_WHITE end
  Render.bill(r, p.x, p.y, z, flip, pm)
  Render.setPM(nil)
end

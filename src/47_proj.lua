-- ============================================================================
--  47 PROJECTILES & DROPS
-- ============================================================================
Proj = {}
local PSPR = { shuriken = "shuriken", arrow = "arrow", feather = "feather", fire = "fireball", web = "web" }

-- friendly = thrown by the player (hits enemies), else hits the player
function Proj.spawn(kind, x, y, z, vx, vy, vz, friendly, dmg)
  local e = Ent.add({ kind = "proj", pk = kind, x = x, y = y, z = z, vx = vx, vy = vy, vz = vz or 0, r = 2,
    friendly = friendly, dmg = dmg or 1, life = 80, always = true })
  e.update = Proj.update
  e.draw = Proj.draw
  return e
end

function Proj.update(e)
  e.life = e.life - 1
  e.x, e.y, e.z = e.x + e.vx, e.y + e.vy, e.z + e.vz
  if e.pk == "fire" then e.vz = e.vz - 0.02 end
  if e.life <= 0 then e.alive = false return end
  local g = groundAt(e.x, e.y)
  if g > e.z then
    e.alive = false
    FX.burst(e.x, e.y, e.z, 4, { C_GRAY, C_WHITE }, 0.8, 10)
    Sfx.play("clank")
    return
  end
  if e.friendly then
    for _, t in ipairs(ENTS) do
      if t.alive and t.hostile and t.hp and t.hp > 0 and dist(e.x, e.y, t.x, t.y) < (t.r or 3) + 4 and math.abs(e.z - (t.z + (t.hz or 6))) < 12 + (t.tall or 0) then
        Enemy.hurt(t, e.dmg, e.x - e.vx * 3, e.y - e.vy * 3, 1.2)
        e.alive = false
        return
      end
    end
  else
    local p = P
    if p.state ~= "dead" and dist(e.x, e.y, p.x, p.y) < 6 and math.abs(e.z - (p.z + 7)) < 10 then
      Player.damage(e.dmg, e.x - e.vx * 3, e.y - e.vy * 3, e.pk)
      if e.pk == "web" then P.webbed = 90 end
      e.alive = false
    end
  end
end

function Proj.draw(e)
  local r = SPR[PSPR[e.pk]]
  if not r then return end
  local flip = (e.t // 3) % 2 == 0
  Render.bill(r, e.x, e.y, e.z - r[4] / 2, flip, nil, 1, 3)
end

-- ---------------------------------------------------------------------------
-- dropped items: pop out, then fly to the player
-- ---------------------------------------------------------------------------
Drops = {}
function Drops.spawn(x, y, z, id, n)
  local a = rnd() * TAU
  local e = Ent.add({ kind = "drop", item = id, n = n, x = x, y = y, z = z, vx = math.cos(a) * 0.7, vy = math.sin(a) * 0.7,
    vz = 1.6, r = 2, step = 6, life = 60 * 120 })
  e.update = Drops.update
  e.draw = Drops.draw
  return e
end

-- straight to inventory with a small fly-up icon
function Drops.give(id, n, x, y, z)
  if id == "ryo" then
    P.ryo = P.ryo + n
    FX.text(x or P.x, y or P.y, (z or P.z) + 14, "+" .. n .. " ryo", C_GOLD)
    Sfx.play("coin")
    return
  end
  local left = Inv.add(id, n)
  local got = n - left
  if got > 0 then
    FX.text(x or P.x, y or P.y, (z or P.z) + 14, "+" .. got .. " " .. ITEM[id].n, C_WHITE)
    Quest.event("item", id)
  end
  if left > 0 then
    UI.toast("Inventory full!")
    Drops.spawn(P.x, P.y, P.z + 4, id, left)
  end
end

function Drops.update(e)
  e.life = e.life - 1
  if e.life <= 0 then e.alive = false return end
  local p = P
  local d = dist(e.x, e.y, p.x, p.y)
  if e.t > 24 and d < 28 and p.state ~= "dead" then
    local full = e.item ~= "ryo" and Inv.free() == 0 and Inv.count(e.item) % (ITEM[e.item].s) == 0
    if not full then
      local k = 0.12 + (28 - d) * 0.01
      e.x = e.x + (p.x - e.x) * k
      e.y = e.y + (p.y - e.y) * k
      e.z = e.z + (p.z + 4 - e.z) * k
      if d < 5 then
        e.alive = false
        Drops.give(e.item, e.n, e.x, e.y, e.z)
        if e.item ~= "ryo" then Sfx.play("pick") end
      end
      return
    end
  end
  e.vx, e.vy = e.vx * 0.92, e.vy * 0.92
  Ent.physics(e)
end

function Drops.draw(e)
  local r = e.item == "ryo" and SPR.ryo or SPR["i_" .. e.item]
  if not r then return end
  local bob = math.sin(e.t / 8) * 1.5
  if e.life < 300 and (e.t // 4) % 2 == 0 then return end
  Ent.shadow(e, 3)
  Render.bill(r, e.x, e.y, e.z + 2 + bob, false, nil, 1, 3)
end

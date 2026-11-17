-- ============================================================================
--  46 FX - particles, slash arcs, floating text, screen shake, hit-stop.
--  Particles live in world space and are projected each frame (no depth).
-- ============================================================================
FX = { parts = {}, texts = {}, shakeA = 0, stop = 0, sprites = {} }
PM_WHITE = nil

function FX.init()
  PM_WHITE = {}
  for i = 0, 15 do PM_WHITE[i] = C_WHITE end
  PM_RED = {}
  for i = 0, 15 do PM_RED[i] = C_RED end
  PM_RED[0] = 0
  PM_GOLD = Pal.mk { [C_WHITE] = C_GOLD, [C_CREAM] = C_GOLD }
end

function FX.shake(a) if a > FX.shakeA then FX.shakeA = a end end
function FX.hitstop(n) if n > FX.stop then FX.stop = n end end

function FX.add(x, y, z, vx, vy, vz, life, c, g, size)
  local ps = FX.parts
  if #ps > 240 then return end
  ps[#ps + 1] = { x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, life = life, max = life, c = c, g = g or 0.08, s = size or 1 }
end

function FX.dust(x, y, z, n)
  for i = 1, n do
    local a = rnd() * TAU
    FX.add(x, y, z + 1, math.cos(a) * 0.5, math.sin(a) * 0.5, rndf(0.2, 0.6), rnd(10, 18), (i % 2 == 0) and C_CREAM or C_TAN, 0.03)
  end
end

function FX.burst(x, y, z, n, cols, sp, life)
  for i = 1, n do
    local a = rnd() * TAU
    local s = rndf(0.4, sp or 1.4)
    FX.add(x, y, z, math.cos(a) * s, math.sin(a) * s, rndf(0.5, 1.8), rnd(math.min(10, life or 26), life or 26), cols[rnd(#cols)], 0.12)
  end
end

function FX.ring(x, y, z, c)
  for i = 0, 15 do
    local a = i / 16 * TAU
    FX.add(x, y, z + 1, math.cos(a) * 1.3, math.sin(a) * 1.3, 0.1, 14, c, 0)
  end
end

function FX.ripple(x, y, z)
  FX.sprites[#FX.sprites + 1] = { spr = "ripple", x = x, y = y, z = z, life = 24, max = 24 }
end

function FX.slash(x, y, z, combo)
  local _, f = Ent.view(P.dir)
  FX.sprites[#FX.sprites + 1] = { spr = "slash", x = x, y = y, z = z - 6, life = 7, max = 7, flip = f,
    sc = combo == 3 and 2 or 1, pm = combo == 3 and PM_GOLD or nil }
end

function FX.sprite(name, x, y, z, life, sc, flip, pm)
  FX.sprites[#FX.sprites + 1] = { spr = name, x = x, y = y, z = z, life = life, max = life, sc = sc, flip = flip, pm = pm }
end

function FX.text(x, y, z, str, c)
  local t = FX.texts
  if #t > 12 then table.remove(t, 1) end
  t[#t + 1] = { x = x, y = y, z = z, s = str, c = c or C_WHITE, life = 50 }
end

function FX.update()
  if FX.shakeA > 0 then
    FX.shakeA = FX.shakeA * 0.85
    if FX.shakeA < 0.3 then FX.shakeA = 0 end
  end
  local ps = FX.parts
  local j = 0
  for i = 1, #ps do
    local p = ps[i]
    p.life = p.life - 1
    if p.life > 0 then
      p.x, p.y, p.z = p.x + p.vx, p.y + p.vy, p.z + p.vz
      p.vz = p.vz - p.g
      p.vx, p.vy = p.vx * 0.96, p.vy * 0.96
      j = j + 1
      ps[j] = p
    end
  end
  for i = j + 1, #ps do ps[i] = nil end
  local ss = FX.sprites
  j = 0
  for i = 1, #ss do
    local s = ss[i]
    s.life = s.life - 1
    if s.life > 0 then j = j + 1 ss[j] = s end
  end
  for i = j + 1, #ss do ss[i] = nil end
  local ts = FX.texts
  j = 0
  for i = 1, #ts do
    local t = ts[i]
    t.life = t.life - 1
    t.z = t.z + 0.35
    if t.life > 0 then j = j + 1 ts[j] = t end
  end
  for i = j + 1, #ts do ts[i] = nil end
end

-- depth-tested sprite effects (drawn with the world)
function FX.drawWorld()
  for _, s in ipairs(FX.sprites) do
    local r = SPR[s.spr]
    if r then Render.bill(r, s.x, s.y, s.z, s.flip, s.pm, s.sc, 4) end
  end
  Render.setPM(nil)
end

-- particles and texts (screen space, over the world)
function FX.drawTop()
  for _, p in ipairs(FX.parts) do
    local sx, sy = proj(p.x, p.y, p.z)
    if p.s > 1 or p.life > p.max * 0.6 then
      rect(sx, sy, p.s + 1, p.s + 1, p.c)
    else
      pix(sx, sy, p.c)
    end
  end
  for _, t in ipairs(FX.texts) do
    local sx, sy = proj(t.x, t.y, t.z)
    local w = print(t.s, 0, -20, 0, false, 1, true)
    print(t.s, sx - w / 2 + 1, sy + 1, C_NIGHT, false, 1, true)
    print(t.s, sx - w / 2, sy, t.c, false, 1, true)
  end
end

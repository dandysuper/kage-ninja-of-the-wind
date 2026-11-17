-- ============================================================================
--  40 ENTITIES & PHYSICS
--  Terrain is a heightfield of 8x8 cells; anything taller than z+step is a
--  solid square, objects with r/h are solid cylinders. Movement integrates
--  velocity then pushes the body's circle out of solids (robust sliding, no
--  sticking on ledges). Ground height includes object tops and sloped roofs,
--  so you can stand on boulders, stumps and rooftops.
-- ============================================================================
ENTS = {}
Ent = {}
GRAV = 0.22

-- height of a cell's walkable top (water surface for water cells)
local function cellTop(cx, cy)
  if cx < 0 or cy < 0 or cx >= 240 or cy >= 112 then return -3 end
  local h = WH[cy * 240 + cx + 1]
  if h < 0 then return h + 1 end
  return h
end
Ent.cellTop = cellTop

-- ground height at a point (centre sample): roofs + object tops
function groundAt(x, y)
  local cx, cy = flr(x / 8), flr(y / 8)
  if cx < 0 or cy < 0 or cx >= 240 or cy >= 112 then return -3 end
  local i = cy * 240 + cx + 1
  local h = WH[i]
  if h < 0 then h = h + 1 end
  if (WF[i] & F_ROOF) ~= 0 then
    local b = BLD[WB[i]]
    if b and b.roof > 0 then h = Build_roofH(b, x, y) end
  end
  for dy = -1, 1 do
    for dx = -1, 1 do
      local j = i + dy * 240 + dx
      local o = WO[j]
      if o and o > 0 then
        local d = OBJ[o]
        if d.r then
          local ox, oy = objPos(j)
          local ex, ey = x - ox, y - oy
          if ex * ex + ey * ey < d.r * d.r then
            local top = math.max(WH[j], 0) + d.h
            if top > h then h = top end
          end
        end
      end
    end
  end
  return h
end

function isWaterAt(x, y)
  local cx, cy = flr(x / 8), flr(y / 8)
  if cx < 0 or cy < 0 or cx >= 240 or cy >= 112 then return true end
  return (WF[cy * 240 + cx + 1] & F_WATER) ~= 0
end
function flagsAt(x, y)
  local cx, cy = flr(x / 8), flr(y / 8)
  if cx < 0 or cy < 0 or cx >= 240 or cy >= 112 then return F_WATER end
  return WF[cy * 240 + cx + 1]
end

-- push a body out of solid cells/cylinders; returns hit flag and wall height
function Ent.resolve(e)
  local r = e.r
  local x, y = e.x, e.y
  local lim = e.z + (e.step or 4.5)
  local hit, wallH, wnx, wny = false, nil, 0, 0
  local avoidWater = e.dry
  for pass = 1, 2 do
    local cx0, cy0, cx1, cy1 = flr((x - r) / 8), flr((y - r) / 8), flr((x + r) / 8), flr((y + r) / 8)
    for cy = cy0, cy1 do
      for cx = cx0, cx1 do
        local h = cellTop(cx, cy)
        local solid = h > lim
        if not solid and avoidWater then
          solid = (cx < 0 or cy < 0 or cx >= 240 or cy >= 112) or (WF[cy * 240 + cx + 1] & F_WATER) ~= 0
          if solid then h = lim + 99 end
        end
        if solid then
          local qx0, qy0 = cx * 8, cy * 8
          local px = x < qx0 and qx0 or (x > qx0 + 8 and qx0 + 8 or x)
          local py = y < qy0 and qy0 or (y > qy0 + 8 and qy0 + 8 or y)
          local dx, dy = x - px, y - py
          local d2 = dx * dx + dy * dy
          if d2 < r * r then
            local nx, ny
            if d2 > 1e-6 then
              local d = math.sqrt(d2)
              nx, ny = dx / d, dy / d
              x, y = px + nx * r, py + ny * r
            else
              -- centre inside the square: leave by the nearest side
              local l, rr, t, b = x - qx0, qx0 + 8 - x, y - qy0, qy0 + 8 - y
              local m = math.min(l, rr, t, b)
              if m == l then nx, ny = -1, 0 x = qx0 - r
              elseif m == rr then nx, ny = 1, 0 x = qx0 + 8 + r
              elseif m == t then nx, ny = 0, -1 y = qy0 - r
              else nx, ny = 0, 1 y = qy0 + 8 + r end
            end
            hit = true
            if not wallH or h > wallH then wallH, wnx, wny = h, nx, ny end
          end
        end
      end
    end
    -- object cylinders
    local ccx, ccy = flr(x / 8), flr(y / 8)
    for yy = ccy - 1, ccy + 1 do
      for xx = ccx - 1, ccx + 1 do
        if xx >= 0 and yy >= 0 and xx < 240 and yy < 112 then
          local j = yy * 240 + xx + 1
          local o = WO[j]
          if o > 0 then
            local d = OBJ[o]
            if d.r then
              local top = math.max(WH[j], 0) + d.h
              if top > lim then
                local ox, oy = objPos(j)
                local dx, dy = x - ox, y - oy
                local rr = r + d.r
                local d2 = dx * dx + dy * dy
                if d2 < rr * rr then
                  local dd = math.sqrt(d2)
                  if dd < 0.001 then dx, dy, dd = 1, 0, 1 end
                  x, y = ox + dx / dd * rr, oy + dy / dd * rr
                  hit = true
                  if not wallH or top > wallH then wallH, wnx, wny = top, dx / dd, dy / dd end
                end
              end
            end
          end
        end
      end
    end
  end
  e.x, e.y = x, y
  return hit, wallH, wnx, wny
end

-- standard walker physics: horizontal velocity + gravity + ground snap
function Ent.physics(e)
  e.x = e.x + e.vx
  e.y = e.y + e.vy
  local hit, wh, nx, ny = Ent.resolve(e)
  local g = groundAt(e.x, e.y)
  if e.fly then
    -- flyers hover at their own height above ground
    local target = g + (e.hover or 10)
    e.z = e.z + (target - e.z) * 0.08
    e.ground = false
  elseif e.z > g + 0.05 or e.vz > 0 then
    e.vz = e.vz - (e.grav or GRAV)
    if e.vz < -5 then e.vz = -5 end
    e.z = e.z + e.vz
    e.ground = false
    if e.z <= g then
      e.z = g
      e.landV = e.vz
      e.vz = 0
      e.ground = true
    end
  else
    -- walking down small steps snaps, bigger drops fall
    if g < e.z - 4.6 then
      e.ground = false
    else
      e.z = g
      e.ground = true
    end
  end
  return hit, wh, nx, ny
end

function Ent.add(e)
  e.t = e.t or 0
  e.vx, e.vy, e.vz = e.vx or 0, e.vy or 0, e.vz or 0
  e.z = e.z or groundAt(e.x, e.y)
  e.r = e.r or 3
  e.alive = true
  ENTS[#ENTS + 1] = e
  return e
end

-- update all live entities near the player; compact dead ones
function Ent.updateAll(px, py)
  local n = #ENTS
  local j = 0
  for i = 1, n do
    local e = ENTS[i]
    if e.alive then
      local dx, dy = e.x - px, e.y - py
      if e.always or (dx * dx + dy * dy < 260 * 260) then
        e.t = e.t + 1
        if e.update then e:update() end
      elseif e.far then
        e:far()
      end
    end
    if e.alive then
      j = j + 1
      ENTS[j] = e
    end
  end
  for i = j + 1, n do ENTS[i] = nil end
end

function Ent.drawAll(px, py)
  for i = 1, #ENTS do
    local e = ENTS[i]
    if e.alive and e.draw then
      local dx, dy = e.x - px, e.y - py
      if dx * dx + dy * dy < 320 * 320 then e:draw() end
    end
  end
end

-- nearest entity matching pred within radius
function Ent.nearest(x, y, rad, pred)
  local best, bd = nil, rad * rad
  for i = 1, #ENTS do
    local e = ENTS[i]
    if e.alive and pred(e) then
      local d = dist2(x, y, e.x, e.y)
      if d < bd then best, bd = e, d end
    end
  end
  return best, best and math.sqrt(bd)
end

-- screen-relative facing: returns view ("s","f","b") and flip
function Ent.view(dir)
  local wx, wy = math.cos(dir), math.sin(dir)
  local ca, sa = math.cos(Cam.a), math.sin(Cam.a)
  local sx = wx * ca + wy * sa
  local up = wx * sa - wy * ca
  if math.abs(sx) >= math.abs(up) * 0.75 then
    return "s", sx < 0
  elseif up > 0 then
    return "b", sx < 0
  end
  return "f", sx < 0
end

-- shadow under an entity, on the ground below it
function Ent.shadow(e, rad)
  local g = groundAt(e.x, e.y)
  local s = rad or 4
  local hgt = e.z - g
  if hgt > 0 then s = s * math.max(0.5, 1 - hgt / 80) end
  Render.ground(SPR.shadow, e.x, e.y, g + 0.4, s)
end


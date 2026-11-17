-- ============================================================================
--  20 RENDER - orthographic, rotatable isometric camera over a z-buffered
--  ttri pipeline.
--
--  Projection (yaw a, pitch p, ortho scale 1):
--    lx = dx*cos a + dy*sin a        (screen right)
--    lf = dx*sin a - dy*cos a        (into the screen, along the ground)
--    sx = SCX + lx
--    sy = SCY - (lf*sin p + dz*cos p)
--    depth = DOFF + lf*cos p - dz*sin p    (smaller = closer; ttri z-test is <)
--  DOFF is large so ttri's perspective correction is effectively affine.
--  Terrain is meshed per 8x8-cell chunk (greedy top rectangles + merged cliff
--  runs) and cached; walls sample texture bands in map rows 112+.
-- ============================================================================
Cam = { x = 960, y = 700, z = 0, a = math.pi / 4, ta = math.pi / 4, sx = 0, sy = 0,
  SCX = 120, SCY = 76, shake = 0 }
function Cam.setPitch(p) Cam.pitch, Cam.sp, Cam.cp = p, math.sin(p), math.cos(p) end
Cam.setPitch(0.66)

Render = { stats = {} }
MESH = {}
CHMIN, CHMAX = {}, {}
OLIST = {}       -- chunk -> list of cell indices that hold objects
OX, OY = {}, {}  -- object world positions (jittered)

local DOFF = 100000
local CA, SA, SP, CP, CX, CY, CZ, SCX, SCY = 1, 0, 0.6, 0.8, 0, 0, 0, 120, 76
local ttri = ttri
local curPM = nil

local function setPM(p)
  if p == curPM then return end
  if p then Pal.remap(p) else Pal.reset() end
  curPM = p
end
Render.setPM = setPM

function proj(x, y, z)
  local dx, dy = x - CX, y - CY
  local lf = dx * SA - dy * CA
  local dz = z - CZ
  return SCX + dx * CA + dy * SA, SCY - (lf * SP + dz * CP), DOFF + lf * CP - dz * SP
end
local PRJ = proj

function Render.begin()
  CA, SA = math.cos(Cam.a), math.sin(Cam.a)
  SP, CP = Cam.sp, Cam.cp
  CX, CY, CZ = Cam.x + Cam.sx, Cam.y + Cam.sy, Cam.z
  SCX, SCY = Cam.SCX, Cam.SCY
  curPM = nil
  Pal.reset()
end

-- world forward/right vectors for input mapping
function Cam.fwd() return math.sin(Cam.a), -math.cos(Cam.a) end
function Cam.right() return math.cos(Cam.a), math.sin(Cam.a) end

-- ---------------------------------------------------------------------------
-- chunk meshing
-- ---------------------------------------------------------------------------
function Render.chunkBounds()
  for cy = 0, 13 do
    for cx = 0, 29 do
      local lo, hi = 999, -999
      for y = cy * 8, cy * 8 + 7 do
        for x = cx * 8, cx * 8 + 7 do
          local h = WH[y * 240 + x + 1]
          if h < lo then lo = h end
          if h > hi then hi = h end
        end
      end
      local k = cy * 30 + cx
      CHMIN[k], CHMAX[k] = lo, hi
    end
  end
end

local function cellMat(i)
  return WM[i] or TMAT[WT[i]] or M_EARTH
end

local function buildMesh(k)
  local cx, cy = k % 30, k // 30
  local x0, y0 = cx * 8, cy * 8
  local tops, sides = {}, {}
  local used = {}
  -- greedy top rectangles
  for ly = 0, 7 do
    for lx = 0, 7 do
      local li = ly * 8 + lx
      if not used[li] then
        local i = (y0 + ly) * 240 + x0 + lx + 1
        local h = WH[i]
        local skip = (WF[i] & (F_ROOF | F_MODEL)) ~= 0
        local w = 1
        while lx + w < 8 do
          local j = i + w
          if used[li + w] or WH[j] ~= h or ((WF[j] & (F_ROOF | F_MODEL)) ~= 0) ~= skip then break end
          w = w + 1
        end
        local d = 1
        while ly + d < 8 do
          local ok = true
          for q = 0, w - 1 do
            local j = i + d * 240 + q
            if used[li + d * 8 + q] or WH[j] ~= h or ((WF[j] & (F_ROOF | F_MODEL)) ~= 0) ~= skip then ok = false break end
          end
          if not ok then break end
          d = d + 1
        end
        for yy = 0, d - 1 do for xx = 0, w - 1 do used[li + yy * 8 + xx] = true end end
        if not skip then
          local z = h < 0 and h + 1 or h
          tops[#tops + 1] = { (x0 + lx) * 8, (y0 + ly) * 8, (x0 + lx + w) * 8, (y0 + ly + d) * 8, z }
        end
      end
    end
  end
  -- side faces, merged along the edge direction
  -- dir: 1=S(+y) 2=N(-y) 3=E(+x) 4=W(-x)
  local function emit(dir, ax, ay, bx, by, lo, hi, mat)
    local last = sides[#sides]
    if last and last[1] == dir and last[6] == lo and last[7] == hi and last[8] == mat and last[4] == ax and last[5] == ay then
      last[4], last[5] = bx, by
    else
      sides[#sides + 1] = { dir, ax, ay, bx, by, lo, hi, mat }
    end
  end
  local function top(i, h) return h < 0 and h + 1 or h end
  for pass = 1, 4 do
    for a = 0, 7 do
      for b = 0, 7 do
        local lx, ly
        if pass <= 2 then lx, ly = b, a else lx, ly = a, b end
        local x, y = x0 + lx, y0 + ly
        local i = y * 240 + x + 1
        if (WF[i] & F_MODEL) == 0 then
          local h = top(i, WH[i])
          local nx, ny = x, y
          if pass == 1 then ny = y + 1 elseif pass == 2 then ny = y - 1 elseif pass == 3 then nx = x + 1 else nx = x - 1 end
          local hn = cellH(nx, ny)
          hn = hn < 0 and hn + 1 or hn
          if inmap(nx, ny) and (WF[ny * 240 + nx + 1] & F_MODEL) ~= 0 then hn = h end
          if h > hn then
            local m = cellMat(i)
            if pass == 1 then emit(1, x * 8, (y + 1) * 8, (x + 1) * 8, (y + 1) * 8, hn, h, m)
            elseif pass == 2 then emit(2, x * 8, y * 8, (x + 1) * 8, y * 8, hn, h, m)
            elseif pass == 3 then emit(3, (x + 1) * 8, y * 8, (x + 1) * 8, (y + 1) * 8, hn, h, m)
            else emit(4, x * 8, y * 8, x * 8, (y + 1) * 8, hn, h, m) end
          end
        end
      end
    end
  end
  local m = { tops = tops, sides = sides }
  MESH[k] = m
  return m
end

function Render.invalidate(x, y)
  local k = (y // 8) * 30 + (x // 8)
  MESH[k] = nil
  -- neighbours may expose new faces
  if x % 8 == 0 and x > 0 then MESH[k - 1] = nil end
  if x % 8 == 7 and x < 239 then MESH[k + 1] = nil end
  if y % 8 == 0 and y > 0 then MESH[k - 30] = nil end
  if y % 8 == 7 and y < 111 then MESH[k + 30] = nil end
end

-- ---------------------------------------------------------------------------
-- drawing primitives
-- ---------------------------------------------------------------------------
local function onScreen(a, b, c, d, e, f, g, h)
  local mnx = math.min(a, c, e, g)
  if mnx > 240 then return false end
  local mxx = math.max(a, c, e, g)
  if mxx < 0 then return false end
  local mny = math.min(b, d, f, h)
  if mny > 136 then return false end
  local mxy = math.max(b, d, f, h)
  return mxy >= 0
end

local function drawTop(t)
  local x0, y0, x1, y1, z = t[1], t[2], t[3], t[4], t[5]
  local ax, ay, ad = PRJ(x0, y0, z)
  local bx, by, bd = PRJ(x1, y0, z)
  local cx, cy, cd = PRJ(x1, y1, z)
  local dx, dy, dd = PRJ(x0, y1, z)
  if not onScreen(ax, ay, bx, by, cx, cy, dx, dy) then return end
  ttri(ax, ay, bx, by, dx, dy, x0, y0, x1, y0, x0, y1, 1, -1, ad, bd, dd)
  ttri(bx, by, cx, cy, dx, dy, x1, y0, x1, y1, x0, y1, 1, -1, bd, cd, dd)
  Render.stats.tris = Render.stats.tris + 2
end

local VIS = { false, false, false, false }
local function drawSide(s)
  local dir = s[1]
  if not VIS[dir] then return end
  local ax, ay, bx, by, lo, hi = s[2], s[3], s[4], s[5], s[6], s[7]
  -- orient so the quad's left edge is on the viewer's left
  local ua, ub
  if dir == 1 then ua, ub = ax, bx
  elseif dir == 2 then ax, ay, bx, by = bx, by, ax, ay ua, ub = ax, bx
  elseif dir == 3 then ax, ay, bx, by = bx, by, ax, ay ua, ub = ay, by
  else ua, ub = ay, by end
  local mat = MAT[s[8]]
  local band = mat.band
  local topz = hi
  local first = true
  local p1x, p1y, p1d = PRJ(ax, ay, topz)
  local p2x, p2y, p2d = PRJ(bx, by, topz)
  local p3x, p3y, p3d = PRJ(bx, by, lo)
  local p4x, p4y, p4d = PRJ(ax, ay, lo)
  if not onScreen(p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y) then return end
  setPM(mat.pm)
  while topz > lo do
    local vs, avail
    if first or band.h <= 8 then vs, avail = band.v, band.h
    else vs, avail = band.v + 8, band.h - 8 end
    local seg = math.min(avail, topz - lo)
    local bz = topz - seg
    local ax1, ay1, ad1 = PRJ(ax, ay, topz)
    local bx1, by1, bd1 = PRJ(bx, by, topz)
    local bx2, by2, bd2 = PRJ(bx, by, bz)
    local ax2, ay2, ad2 = PRJ(ax, ay, bz)
    ttri(ax1, ay1, bx1, by1, ax2, ay2, ua, vs, ub, vs, ua, vs + seg, 1, -1, ad1, bd1, ad2)
    ttri(bx1, by1, bx2, by2, ax2, ay2, ub, vs, ub, vs + seg, ua, vs + seg, 1, -1, bd1, bd2, ad2)
    Render.stats.tris = Render.stats.tris + 2
    topz = bz
    first = false
  end
end

-- draw a model polygon list
local function drawModel(m)
  local ps = m.polys
  for i = 1, #ps do
    local q = ps[i]
    if q[1] == 4 then
      local ax, ay, ad = PRJ(q[2], q[3], q[4])
      local bx, by, bd = PRJ(q[5], q[6], q[7])
      local cx, cy, cd = PRJ(q[8], q[9], q[10])
      local dx, dy, dd = PRJ(q[11], q[12], q[13])
      -- winding cull (clockwise on screen = front); test both tris for degenerate quads
      local area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay) + (cx - ax) * (dy - ay) - (dx - ax) * (cy - ay)
      if area > 0 and onScreen(ax, ay, bx, by, cx, cy, dx, dy) then
        setPM(q[23])
        local src = q[22]
        local ck = src == 0 and 0 or -1
        ttri(ax, ay, bx, by, dx, dy, q[14], q[15], q[16], q[17], q[20], q[21], src, ck, ad, bd, dd)
        ttri(bx, by, cx, cy, dx, dy, q[16], q[17], q[18], q[19], q[20], q[21], src, ck, bd, cd, dd)
        Render.stats.tris = Render.stats.tris + 2
      end
    else
      local ax, ay, ad = PRJ(q[2], q[3], q[4])
      local bx, by, bd = PRJ(q[5], q[6], q[7])
      local cx, cy, cd = PRJ(q[8], q[9], q[10])
      local area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
      if area > 0 then
        setPM(q[18])
        local src = q[17]
        ttri(ax, ay, bx, by, cx, cy, q[11], q[12], q[13], q[14], q[15], q[16], src, src == 0 and 0 or -1, ad, bd, cd)
        Render.stats.tris = Render.stats.tris + 1
      end
    end
  end
end
Render.drawModel = drawModel

-- billboard: rect drawn upright, feet at world (x,y,z); bias pulls it forward
function Render.bill(r, x, y, z, flip, pm, sc, bias)
  sc = sc or 1
  local sx, sy, d = PRJ(x, y, z)
  local w, h = r[3] * sc, r[4] * sc
  local x0 = flr(sx - w / 2 + 0.5)
  local y1 = flr(sy + 0.5)
  local y0 = y1 - h
  if x0 > 240 or x0 + w < 0 or y0 > 136 or y1 < 0 then return false end
  d = d - (bias or 1.5)
  local dt = d - (h / CP) * SP
  local u, v = r[1], r[2]
  local u0, u1 = u, u + r[3]
  if flip then u0, u1 = u1, u0 end
  if pm ~= curPM then setPM(pm) end
  local x1 = x0 + w
  ttri(x0, y0, x1, y0, x0, y1, u0, v, u1, v, u0, v + r[4], 0, 0, dt, dt, d)
  ttri(x1, y0, x1, y1, x0, y1, u1, v, u1, v + r[4], u0, v + r[4], 0, 0, dt, d, d)
  Render.stats.bills = Render.stats.bills + 1
  return true, x0, y0
end

-- billboard rotated about its base centre by ang (screen space, + = clockwise):
-- chopped trees lean and fall with it. The top keeps the depth of the height
-- it still reaches.
function Render.billRot(r, x, y, z, flip, pm, sc, ang, bias)
  sc = sc or 1
  local sx, sy, d = PRJ(x, y, z)
  local w, h = r[3] * sc, r[4] * sc
  if sx + w + h < 0 or sx - w - h > 240 or sy - h > 136 or sy + h < 0 then return false end
  d = d - (bias or 1.5)
  local c, s = math.cos(ang), math.sin(ang)
  local dt = d - (h * math.max(c, 0) / CP) * SP
  local hw = w / 2
  local tlx, tly = sx - hw * c + h * s, sy - hw * s - h * c
  local trx, try = sx + hw * c + h * s, sy + hw * s - h * c
  local blx, bly = sx - hw * c, sy - hw * s
  local brx, bry = sx + hw * c, sy + hw * s
  local u, v = r[1], r[2]
  local u0, u1 = u, u + r[3]
  if flip then u0, u1 = u1, u0 end
  if pm ~= curPM then setPM(pm) end
  ttri(tlx, tly, trx, try, blx, bly, u0, v, u1, v, u0, v + r[4], 0, 0, dt, dt, d)
  ttri(trx, try, brx, bry, blx, bly, u1, v, u1, v + r[4], u0, v + r[4], 0, 0, dt, d, d)
  Render.stats.bills = Render.stats.bills + 1
  return true
end

-- billboard without depth test (always on top) - used for the x-ray silhouette
function Render.billFlat(r, x, y, z, flip, sc)
  sc = sc or 1
  local sx, sy = PRJ(x, y, z)
  local w, h = r[3] * sc, r[4] * sc
  local x0 = flr(sx - w / 2 + 0.5)
  local y1 = flr(sy + 0.5)
  local y0 = y1 - h
  local u, v = r[1], r[2]
  local u0, u1 = u, u + r[3]
  if flip then u0, u1 = u1, u0 end
  local x1 = x0 + w
  ttri(x0, y0, x1, y0, x0, y1, u0, v, u1, v, u0, v + r[4], 0, 0)
  ttri(x1, y0, x1, y1, x0, y1, u1, v, u1, v + r[4], u0, v + r[4], 0, 0)
end

-- flat ground decal (shadow etc): rect mapped onto a square of radius rad
function Render.ground(r, x, y, z, rad, pm)
  local ax, ay, ad = PRJ(x - rad, y - rad, z)
  local bx, by, bd = PRJ(x + rad, y - rad, z)
  local cx, cy, cd = PRJ(x + rad, y + rad, z)
  local dx, dy, dd = PRJ(x - rad, y + rad, z)
  if not onScreen(ax, ay, bx, by, cx, cy, dx, dy) then return end
  if pm ~= curPM then setPM(pm) end
  local u, v, w, h = r[1], r[2], r[3], r[4]
  ttri(ax, ay, bx, by, dx, dy, u, v, u + w, v, u, v + h, 0, 0, ad, bd, dd)
  ttri(bx, by, cx, cy, dx, dy, u + w, v, u + w, v + h, u, v + h, 0, 0, bd, cd, dd)
end

-- ---------------------------------------------------------------------------
-- world pass
-- ---------------------------------------------------------------------------
-- world-space chunk range covering the screen
function Render.range()
  local m = 40
  local lxa, lxb = -SCX - m, 240 - SCX + m
  local zlo, zhi = -4 - CZ, 140 - CZ
  local lfa = (SCY - 136 - zhi * CP) / SP - m
  local lfb = (SCY - zlo * CP) / SP + 60 / SP
  local xs, ys = {}, {}
  for _, lx in ipairs({ lxa, lxb }) do
    for _, lf in ipairs({ lfa, lfb }) do
      xs[#xs + 1] = CX + lx * CA + lf * SA
      ys[#ys + 1] = CY + lx * SA - lf * CA
    end
  end
  local x0, x1 = math.min(table.unpack(xs)), math.max(table.unpack(xs))
  local y0, y1 = math.min(table.unpack(ys)), math.max(table.unpack(ys))
  return flr(x0 / 64), flr(y0 / 64), flr(x1 / 64), flr(y1 / 64)
end

local function chunkVisible(k, cx, cy)
  local lo, hi = CHMIN[k], CHMAX[k]
  local x0, y0, x1, y1 = cx * 64, cy * 64, cx * 64 + 64, cy * 64 + 64
  local mnx, mny, mxx, mxy = 1e9, 1e9, -1e9, -1e9
  for _, z in ipairs({ lo, hi }) do
    for _, p in ipairs({ { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }) do
      local sx, sy = PRJ(p[1], p[2], z)
      if sx < mnx then mnx = sx end
      if sx > mxx then mxx = sx end
      if sy < mny then mny = sy end
      if sy > mxy then mxy = sy end
    end
  end
  return mxx >= 0 and mnx <= 240 and mxy >= -50 and mny <= 136
end

local OCEAN_T = { 0, 0, 64, 64, -3 }
function Render.world(drawObjects)
  local st = Render.stats
  st.tris, st.bills, st.chunks = 0, 0, 0
  VIS[1] = CA > 0.01
  VIS[2] = CA < -0.01
  VIS[3] = SA < -0.01
  VIS[4] = SA > 0.01
  local cx0, cy0, cx1, cy1 = Render.range()
  local vis = {}
  for cy = cy0, cy1 do
    for cx = cx0, cx1 do
      if cx < 0 or cy < 0 or cx >= 30 or cy >= 14 then
        -- open ocean beyond the map edge
        local x0, y0 = cx * 64, cy * 64
        local ax, ay, ad = PRJ(x0, y0, -3)
        local bx, by, bd = PRJ(x0 + 64, y0, -3)
        local qx, qy, qd = PRJ(x0 + 64, y0 + 64, -3)
        local dx, dy, dd = PRJ(x0, y0 + 64, -3)
        if onScreen(ax, ay, bx, by, qx, qy, dx, dy) then
          setPM(nil)
          ttri(ax, ay, bx, by, dx, dy, 0, 0, 64, 0, 0, 64, 1, -1, ad, bd, dd)
          ttri(bx, by, qx, qy, dx, dy, 64, 0, 64, 64, 0, 64, 1, -1, bd, qd, dd)
        end
      else
        local k = cy * 30 + cx
        if chunkVisible(k, cx, cy) then
          st.chunks = st.chunks + 1
          vis[#vis + 1] = k
          local m = MESH[k] or buildMesh(k)
          setPM(nil)
          local tops = m.tops
          for i = 1, #tops do drawTop(tops[i]) end
          local sides = m.sides
          for i = 1, #sides do drawSide(sides[i]) end
        end
      end
    end
  end
  -- models (registered by centre chunk; scan one chunk wider)
  for cy = cy0 - 1, cy1 + 1 do
    for cx = cx0 - 1, cx1 + 1 do
      local list = MCHUNK[cy * 30 + cx]
      if list and cx >= 0 and cx < 30 then
        for i = 1, #list do drawModel(list[i]) end
      end
    end
  end
  setPM(nil)
  Render.visChunks = vis
  return vis
end

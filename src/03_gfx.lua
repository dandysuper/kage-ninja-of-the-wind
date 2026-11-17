-- ============================================================================
--  03 GFX - sprite-sheet painting and a texture atlas.
--
--  ttri() treats the tile+sprite banks as one 128x256 texture (u=x, v=y), so
--  billboards do not need 8x8 alignment. Map tiles (ground + wall textures)
--  live in tiles 0..127 (y 0..63); every other sprite is packed by a skyline
--  packer into y 64..255 and addressed by name: SPR[name] = {u,v,w,h}.
-- ============================================================================
Gfx = { sky = {} }
SPR = {}

function sset(x, y, c)
  poke4(0x8000 + ((y >> 3) * 16 + (x >> 3)) * 64 + (y & 7) * 8 + (x & 7), c)
end
function sget(x, y)
  return peek4(0x8000 + ((y >> 3) * 16 + (x >> 3)) * 64 + (y & 7) * 8 + (x & 7))
end

-- paint one 8x8 map tile from fn(x,y)->colour
function Gfx.tile(id, fn)
  local bx, by = (id % 16) * 8, (id // 16) * 8
  for y = 0, 7 do
    for x = 0, 7 do sset(bx + x, by + y, fn(x, y) or 0) end
  end
end

-- skyline packer over the sprite region
local SKY_TOP = 64
for i = 0, 127 do Gfx.sky[i] = SKY_TOP end

function Gfx.alloc(w, h)
  local sky = Gfx.sky
  local bestx, besty = -1, 1e9
  for x = 0, 128 - w do
    local y = 0
    for k = x, x + w - 1 do if sky[k] > y then y = sky[k] end end
    if y < besty then besty, bestx = y, x end
  end
  if bestx < 0 or besty + h > 256 then
    trace("ATLAS FULL for " .. w .. "x" .. h .. "\n")
    return 0, 0
  end
  for k = bestx, bestx + w - 1 do sky[k] = besty + h end
  return bestx, besty
end

-- parse an art string: rows separated by newlines or '|'; '.'=0, hex digit=colour
function Gfx.parse(s)
  local rows = {}
  for line in s:gmatch("[^\n|]+") do
    line = line:gsub("%s", "")
    if #line > 0 then rows[#rows + 1] = line end
  end
  return rows
end

-- sprites are queued, then packed tallest-first by Gfx.flush() (dense packing)
Gfx.queue = {}
function Gfx.add(name, art)
  local rows = type(art) == "string" and Gfx.parse(art) or art
  local h, w = #rows, 0
  for i = 1, h do if #rows[i] > w then w = #rows[i] end end
  Gfx.queue[#Gfx.queue + 1] = { name = name, w = w, h = h, rows = rows }
end

function Gfx.addfn(name, w, h, fn)
  Gfx.queue[#Gfx.queue + 1] = { name = name, w = w, h = h, fn = fn }
end

function Gfx.flush()
  local q = Gfx.queue
  table.sort(q, function(a, b)
    if a.h ~= b.h then return a.h > b.h end
    if a.w ~= b.w then return a.w > b.w end
    return a.name < b.name
  end)
  for _, s in ipairs(q) do
    local u, v = Gfx.alloc(s.w, s.h)
    if s.rows then
      for y = 1, s.h do
        local r = s.rows[y]
        for x = 1, #r do
          local ch = r:sub(x, x)
          sset(u + x - 1, v + y - 1, ch == "." and 0 or (tonumber(ch, 16) or 0))
        end
      end
    else
      for y = 0, s.h - 1 do
        for x = 0, s.w - 1 do sset(u + x, v + y, s.fn(x, y) or 0) end
      end
    end
    SPR[s.name] = { u, v, s.w, s.h }
  end
  Gfx.queue = {}
end

-- 8x8 icons go into unused map-tile slots first (saves sprite-region space)
Gfx.freeTiles = {}
for id = 30, 39 do Gfx.freeTiles[#Gfx.freeTiles + 1] = id end
for id = 69, 127 do Gfx.freeTiles[#Gfx.freeTiles + 1] = id end
function Gfx.icon(name, art)
  local rows = Gfx.parse(art)
  local id = table.remove(Gfx.freeTiles, 1)
  if not id then return Gfx.add(name, rows) end
  local u, v = (id % 16) * 8, (id // 16) * 8
  for y = 1, 8 do
    local r = rows[y] or ""
    for x = 1, 8 do
      local ch = r:sub(x, x)
      sset(u + x - 1, v + y - 1, (ch == "" or ch == ".") and 0 or (tonumber(ch, 16) or 0))
    end
  end
  SPR[name] = { u, v, 8, 8 }
end

-- row-array helpers for composing art
function Gfx.rows(s) return Gfx.parse(s) end
function Gfx.stack(a, b)
  local r = {}
  for i = 1, #a do r[#r + 1] = a[i] end
  for i = 1, #b do r[#r + 1] = b[i] end
  return r
end
function Gfx.mirror(rows)
  local r = {}
  for i = 1, #rows do r[i] = rows[i]:reverse() end
  return r
end

-- blit a sheet rect to the screen (no depth), optional flip and scale
function blit(rect, x, y, flip, sc)
  sc = sc or 1
  local u, v, w, h = rect[1], rect[2], rect[3], rect[4]
  local x1, y1 = x + w * sc, y + h * sc
  local u0, u1 = u, u + w
  if flip then u0, u1 = u1, u0 end
  ttri(x, y, x1, y, x, y1, u0, v, u1, v, u0, v + h, 0, 0)
  ttri(x1, y, x1, y1, x, y1, u1, v, u1, v + h, u0, v + h, 0, 0)
end

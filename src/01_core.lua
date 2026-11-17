-- ============================================================================
--  01 CORE - math, hashing/noise, input, small utilities
--  Chunk-level locals are kept few (Lua allows 200 per function and the whole
--  cart is one chunk); modules expose tables instead.
-- ============================================================================
local flr, ceil, abs, sqrt = math.floor, math.ceil, math.abs, math.sqrt
local sin, cos, atan, min, max = math.sin, math.cos, math.atan, math.min, math.max
local PI, TAU = math.pi, math.pi * 2
local rnd = math.random
local fmt = string.format

function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function lerp(a, b, t) return a + (b - a) * t end
function sgn(v) if v > 0 then return 1 elseif v < 0 then return -1 end return 0 end
function approach(v, t, d) if v < t then return min(v + d, t) end return max(v - d, t) end
function angdiff(a, b) local d = (b - a) % TAU if d > PI then d = d - TAU end return d end
function dist2(ax, ay, bx, by) local dx, dy = bx - ax, by - ay return dx * dx + dy * dy end
function dist(ax, ay, bx, by) local dx, dy = bx - ax, by - ay return sqrt(dx * dx + dy * dy) end
function rndf(a, b) return a + rnd() * (b - a) end
function pick(t) return t[rnd(#t)] end
function chance(p) return rnd() < p end

-- deterministic integer hash -> [0,1)
function hash2(x, y, s)
  local h = (flr(x) * 374761393 + flr(y) * 668265263 + flr(s or 0) * 1442695041) & 0xffffffff
  h = ((h ~ (h >> 13)) * 1274126177) & 0xffffffff
  h = h ~ (h >> 16)
  return (h & 0xffffff) / 16777216
end

function vnoise(x, y, s)
  local xi, yi = flr(x), flr(y)
  local xf, yf = x - xi, y - yi
  local u, v = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
  local a, b = hash2(xi, yi, s), hash2(xi + 1, yi, s)
  local c, d = hash2(xi, yi + 1, s), hash2(xi + 1, yi + 1, s)
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
end

function fbm(x, y, s, oct)
  local t, amp, f, n = 0, 1, 1, 0
  for i = 1, oct do
    t = t + vnoise(x * f, y * f, s + i * 31) * amp
    n = n + amp
    amp = amp * 0.5
    f = f * 2
  end
  return t / n
end

-- ---------------------------------------------------------------------------
-- Input: logical actions built from gamepad buttons + keyboard keys.
-- In.h[a] held, In.p[a] pressed this frame. Tests set In.fake = {a=true...}.
-- ---------------------------------------------------------------------------
In = { h = {}, p = {}, fake = nil, any = false }
local ACTIONS = {
  up = { b = 0, k = { 58 } }, down = { b = 1, k = { 59 } },
  left = { b = 2, k = { 60 } }, right = { b = 3, k = { 61 } },
  atk = { b = 4 }, jump = { b = 5 }, use = { b = 6 }, throw = { b = 7 },
  run = { k = { 64, 3 } }, rotl = { k = { 17 } }, rotr = { k = { 5 } },
  menu = { k = { 49, 9 } }, map = { k = { 13 } }, quest = { k = { 10 } },
  ok = { k = { 50, 48 } },
  s1 = { k = { 28 } }, s2 = { k = { 29 } }, s3 = { k = { 30 } }, s4 = { k = { 31 } },
  s5 = { k = { 32 } }, s6 = { k = { 33 } }, s7 = { k = { 34 } }, s8 = { k = { 35 } },
  s9 = { k = { 36 } }, s10 = { k = { 27 } },
}
In.names = {}
for n in pairs(ACTIONS) do In.names[#In.names + 1] = n end
table.sort(In.names)

function In.poll()
  local f, h, p = In.fake, In.h, In.p
  local any = false
  for i = 1, #In.names do
    local n = In.names[i]
    local v = false
    if f then
      v = f[n] and true or false
    else
      local d = ACTIONS[n]
      if d.b and btn(d.b) then v = true end
      if not v and d.k then
        for j = 1, #d.k do if key(d.k[j]) then v = true break end end
      end
    end
    p[n] = v and not h[n]
    h[n] = v
    if p[n] then any = true end
  end
  In.any = any
end

-- direction from arrows, screen space (-1..1)
function In.axis()
  local h = In.h
  local x = (h.right and 1 or 0) - (h.left and 1 or 0)
  local y = (h.down and 1 or 0) - (h.up and 1 or 0)
  return x, y
end

-- ---------------------------------------------------------------------------
-- Misc
-- ---------------------------------------------------------------------------
Frame = 0
function wrapText(s, w)
  -- greedy wrap for the 6px system font (approx 6px/char, 5 for small)
  local lines, line = {}, ""
  for word in s:gmatch("%S+") do
    local test = line == "" and word or (line .. " " .. word)
    if #test * 6 > w and line ~= "" then
      lines[#lines + 1] = line
      line = word
    else
      line = test
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

-- ============================================================================
--  45 CLOCK & SURVIVAL - day/night cycle (DS-style clock), palette tint,
--  hunger, cold, warmth buffs, darkness danger ("the Yami") and weather.
-- ============================================================================
Clock = { total = 0, t = 0.08, day = 1, len = 60 * 60 * 6, rain = 0, rainT = 0, snow = false }
-- phases on the 0..1 dial
DUSK, NIGHT, DAWN = 0.58, 0.72, 0.96

function Clock.isDay() return Clock.t < DUSK + 0.04 or Clock.t > DAWN end
function Clock.isNight() return Clock.t >= NIGHT and Clock.t < DAWN end
function Clock.phase()
  local t = Clock.t
  if t < DUSK then return "day" elseif t < NIGHT then return "dusk" elseif t < DAWN then return "night" end
  return "dawn"
end

-- palette multipliers through the day
local KEYS = {
  { 0.00, 1.00, 1.00, 1.00 },
  { 0.50, 1.00, 1.00, 1.00 },
  { 0.62, 1.05, 0.80, 0.66 },
  { 0.72, 0.50, 0.50, 0.85 },
  { 0.80, 0.36, 0.40, 0.72 },
  { 0.92, 0.36, 0.40, 0.72 },
  { 0.97, 0.90, 0.80, 0.85 },
  { 1.00, 1.00, 1.00, 1.00 },
}
function Clock.tint()
  local t = Clock.t
  for k = 1, #KEYS - 1 do
    local a, b = KEYS[k], KEYS[k + 1]
    if t >= a[1] and t <= b[1] then
      local u = (t - a[1]) / (b[1] - a[1])
      local r, g, bl = lerp(a[2], b[2], u), lerp(a[3], b[3], u), lerp(a[4], b[4], u)
      if Clock.rain > 0 then
        local w = Clock.rain * 0.25
        r, g, bl = r * (1 - w), g * (1 - w), bl * (1 - w * 0.6)
      end
      return r, g, bl
    end
  end
  return 1, 1, 1
end

function Clock.update()
  Clock.total = Clock.total + 1
  Clock.t = Clock.t + 1 / Clock.len
  if Clock.t >= 1 then
    Clock.t = Clock.t - 1
    Clock.day = Clock.day + 1
    UI.banner("Day " .. Clock.day)
    Game.autosave()
  end
  -- weather: occasional rain showers (snow in the north)
  Clock.rainT = Clock.rainT - 1
  if Clock.rainT <= 0 then
    Clock.rainT = rnd(60 * 60, 60 * 150)
    Clock.raining = (rnd() < 0.3)
  end
  Clock.rain = approach(Clock.rain, Clock.raining and 1 or 0, 0.004)
end

-- survival tick for the player
function Clock.survival()
  local p = P
  if p.state == "dead" or Game.safeTime then return end
  -- hunger
  if Clock.total % 300 == 0 then
    p.hunger = math.max(0, p.hunger - 1)
  end
  if p.hunger <= 0 and Clock.total % 240 == 0 then
    Player.damage(1, nil, nil, "starve")
    UI.toast("You are starving!")
  end
  -- warmth buffs and cold
  if p.warm > 0 then p.warm = p.warm - 1 end
  local reg = REG[WR[cidx(clamp(flr(p.x / 8), 0, 239), clamp(flr(p.y / 8), 0, 111))]]
  local cold = reg and reg.biome == "snow" and p.z > 20 and not (p.armor == "cloak") and p.warm <= 0 and not Light.nearFire(p.x, p.y)
  if cold then
    p.cold = p.cold + 1
    if p.cold == 1 then UI.toast("It's freezing! Find warmth.") end
    if p.cold > 240 and Clock.total % 200 == 0 then Player.damage(1, nil, nil, "cold") end
  else
    p.cold = 0
  end
  -- darkness: at night, outside any light, the Yami strikes
  if Clock.isNight() and not P.has.mirror then
    if Light.level(p.x, p.y) <= 0 then
      p.dark = p.dark + 1
      if p.dark == 60 then UI.toast("It's too dark... something is watching.") Sfx.play("whisper") end
      if p.dark > 240 and p.dark % 90 == 0 then
        Player.damage(3, nil, nil, "dark")
        FX.burst(p.x, p.y, p.z + 8, 12, { C_NIGHT, C_INDIGO }, 1.5, 20)
        UI.toast("The Yami claws at you! Light a torch or fire!")
      end
    else
      p.dark = 0
    end
  else
    p.dark = 0
  end
end

-- ---------------------------------------------------------------------------
-- light sources and the DS-style darkness overlay
-- ---------------------------------------------------------------------------
Light = { list = {} }

function Light.collect()
  local L = {}
  local p = P
  -- the player's torch/lantern or the sacred mirror (no player on the title screen)
  if p then
    local pr = 0
    if p.light and ITEM[p.light] then pr = ITEM[p.light].light end
    if p.has.mirror then pr = math.max(pr, 50) end
    if pr > 0 then L[#L + 1] = { p.x, p.y, p.z + 6, pr + math.sin(Clock.total / 6) * 1.5 } end
    L[#L + 1] = { p.x, p.y, p.z, 14 } -- faint night vision
  end
  -- objects with light (lanterns, fires) in visible chunks
  for _, k in ipairs(Render.visChunks or {}) do
    local l = OLIST[k]
    if l then
      for ci in pairs(l) do
        local o = WO[ci]
        if o > 0 then
          local d = OBJ[o]
          if d.light and (o ~= O_TORO or (WF[ci] & F_NOSPAWN) ~= 0 or true) then
            local ox, oy = objPos(ci)
            local fl = (o == O_FIRE) and math.sin(Clock.total / 4 + ci) * 2 or 0
            L[#L + 1] = { ox, oy, math.max(WH[ci], 0) + 6, d.light + fl }
          end
        end
      end
    end
  end
  for _, e in ipairs(ENTS) do
    if e.alive and e.light then L[#L + 1] = { e.x, e.y, e.z + 4, e.light } end
  end
  Light.list = L
  return L
end

function Light.level(x, y)
  for _, l in ipairs(Light.list) do
    if l[4] > 16 then
      local dx, dy = x - l[1], y - l[2]
      if dx * dx + dy * dy < (l[4] * 0.8) ^ 2 then return 1 end
    end
  end
  return 0
end

function Light.nearFire(x, y)
  local cx, cy = flr(x / 8), flr(y / 8)
  for yy = cy - 3, cy + 3 do
    for xx = cx - 3, cx + 3 do
      if inmap(xx, yy) and WO[cidx(xx, yy)] == O_FIRE then return true end
    end
  end
  return false
end

-- per-row spans: everything outside the light ellipses goes black, with
-- dithered rims for a soft edge. a = darkness amount 0..1 (fades in at dusk
-- by darkening every 4th/2nd row first).
function Light.overlay(a)
  if a <= 0 then return end
  local sl = {}
  local sp = Cam.sp * 1.15
  for _, l in ipairs(Light.list) do
    local sx, sy = proj(l[1], l[2], l[3])
    sl[#sl + 1] = { sx, sy, l[4], l[4] * sp }
  end
  local R1, R2 = 0.8, 0.92
  local rowMask = a >= 0.85 and 1 or (a >= 0.5 and 2 or 4)
  local function dark(x0, x1, y)
    if x1 > x0 then rect(x0, y, x1 - x0, 1, C_INK) end
  end
  local spans = {}
  for y = 0, 135 do
    local n = 0
    for k = 1, #sl do
      local s = sl[k]
      local dy = (y - s[2]) / s[4]
      if dy > -1 and dy < 1 then
        local hw = s[3] * math.sqrt(1 - dy * dy)
        n = n + 1
        local sp2 = spans[n]
        if not sp2 then sp2 = {} spans[n] = sp2 end
        sp2[1], sp2[2], sp2[3], sp2[4] = s[1] - hw, s[1] + hw, s[1], hw
      end
    end
    for k = n + 1, #spans do spans[k] = nil end
    if y % rowMask == 0 then
      if n == 0 then
        dark(0, 240, y)
      else
        table.sort(spans, function(p, q) return p[1] < q[1] end)
        local x = 0
        for k = 1, n do
          local s = spans[k]
          local l = flr(s[1])
          if l > x then dark(x, math.min(l, 240), y) end
          local r = ceil(s[2])
          if r > x then x = r end
        end
        if x < 240 then dark(x, 240, y) end
        -- soft rims
        if a >= 0.85 then
          for k = 1, n do
            local s = spans[k]
            local cx, hw = s[3], s[4]
            local rim = hw * (1 - R1) + 1
            for side = -1, 1, 2 do
              local xa = side < 0 and flr(cx - hw) or ceil(cx + hw * R1)
              local xb = side < 0 and flr(cx - hw * R1) or ceil(cx + hw)
              for xx = math.max(0, xa), math.min(239, xb) do
                local d = math.abs(xx - cx) / hw
                local covered = false
                for j = 1, n do
                  if j ~= k then
                    local o = spans[j]
                    if math.abs(xx - o[3]) < o[4] * R1 then covered = true break end
                  end
                end
                if not covered then
                  if d > R2 then
                    if (xx + y) % 2 == 0 then pix(xx, y, C_INK) end
                  elseif d > R1 then
                    if (xx + y) % 4 == 0 and y % 2 == 0 then pix(xx, y, C_INK) end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

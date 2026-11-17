-- ============================================================================
--  50 UI - dialog box, toasts, banners and the in-game HUD (drawn on VRAM
--  bank 1 so the day/night tint of bank 0 never touches it).
--  Layout (Don't Starve x BotW): hearts top-left with the tracked quest
--  under them; day clock + hunger badge + ryo top-right; hotbar + equipment
--  bottom-centre; crafting tabs on the left edge; stamina wheel by the ninja.
-- ============================================================================
UI = { toasts = {}, bannerT = 0, regionT = 0 }
Dialog = { active = false, pages = {}, page = 1, chars = 0 }

function textw(s, small) return print(s, 0, -40, 0, false, 1, small) end

-- wrap to a pixel width using real glyph widths
function wrap(s, w, small)
  local lines, line = {}, ""
  for word in s:gmatch("%S+") do
    local test = line == "" and word or (line .. " " .. word)
    if textw(test, small) > w and line ~= "" then
      lines[#lines + 1] = line
      line = word
    else
      line = test
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

-- shadowed text
function tprint(s, x, y, c, small, sh)
  print(s, x + 1, y + 1, sh or C_NIGHT, false, 1, small)
  return print(s, x, y, c or C_WHITE, false, 1, small)
end

-- framed panel
function panel(x, y, w, h, bg)
  rect(x, y, w, h, bg or C_NIGHT)
  rectb(x, y, w, h, C_TAN)
  pix(x, y, 0) pix(x + w - 1, y, 0) pix(x, y + h - 1, 0) pix(x + w - 1, y + h - 1, 0)
end

-- ---------------------------------------------------------------------------
-- toasts & banners
-- ---------------------------------------------------------------------------
function UI.toast(s)
  local t = UI.toasts
  if t[#t] and t[#t].s == s then t[#t].life = 150 return end
  t[#t + 1] = { s = s, life = 150 }
  if #t > 3 then table.remove(t, 1) end
end
function UI.banner(s, sub)
  UI.bannerS, UI.bannerSub, UI.bannerT = s, sub, 200
end

-- ---------------------------------------------------------------------------
-- dialog
-- ---------------------------------------------------------------------------
function Dialog.lines(name, list, onDone, who)
  Dialog.active = true
  Dialog.name = name
  Dialog.pages = {}
  -- the box shows 4 lines: longer texts continue on further pages
  for _, s in ipairs(list) do
    local ls = wrap(s, 220)
    for k = 1, math.max(1, #ls), 4 do
      Dialog.pages[#Dialog.pages + 1] = table.concat(ls, " ", k, math.min(k + 3, #ls))
    end
  end
  Dialog.page = 1
  Dialog.chars = 0
  Dialog.onDone = onDone
  Dialog.opts = nil
  Dialog.who = who
end
function Dialog.say(name, s, onDone, who) Dialog.lines(name, { s }, onDone, who) end
function Dialog.ask(name, s, opts, onChoice, who)
  Dialog.lines(name, { s }, nil, who)
  Dialog.opts = opts
  Dialog.sel = 1
  Dialog.onChoice = onChoice
end

function Dialog.update()
  if not Dialog.active then return end
  local text = Dialog.pages[Dialog.page]
  local full = Dialog.chars >= #text
  Dialog.chars = Dialog.chars + 1.5
  if Frame % 4 == 0 and not full then Sfx.play("blip") end
  local adv = In.p.atk or In.p.use or In.p.ok or In.p.jump
  if Dialog.opts and full and Dialog.page == #Dialog.pages then
    if In.p.up then Dialog.sel = (Dialog.sel - 2) % #Dialog.opts + 1 Sfx.play("menu") end
    if In.p.down then Dialog.sel = Dialog.sel % #Dialog.opts + 1 Sfx.play("menu") end
    if In.p.atk or In.p.use or In.p.ok then
      local f, c = Dialog.onChoice, Dialog.sel
      Dialog.active = false
      Sfx.play("select")
      if f then f(c) end
    elseif In.p.jump then
      local f = Dialog.onChoice
      Dialog.active = false
      if f then f(#Dialog.opts) end
    end
    return
  end
  if adv then
    if not full then
      Dialog.chars = #text
    elseif Dialog.page < #Dialog.pages then
      Dialog.page = Dialog.page + 1
      Dialog.chars = 0
    else
      Dialog.active = false
      local f = Dialog.onDone
      Dialog.onDone = nil
      if f then f() end
    end
  end
end

function Dialog.draw()
  if not Dialog.active then return end
  local x, y, w, h = 4, 92, 232, 42
  panel(x, y, w, h)
  local text = Dialog.pages[Dialog.page]
  local shown = text:sub(1, flr(Dialog.chars))
  local lines = wrap(shown, w - 12)
  for i, l in ipairs(lines) do
    if i <= 4 then print(l, x + 6, y + 6 + (i - 1) * 8, C_WHITE) end
  end
  -- name tag
  if Dialog.name then
    local nw = textw(Dialog.name) + 8
    panel(x + 4, y - 9, nw, 11, C_RED)
    print(Dialog.name, x + 8, y - 7, C_WHITE)
  end
  if Dialog.opts and Dialog.chars >= #text and Dialog.page == #Dialog.pages then
    local ow = 0
    for _, o in ipairs(Dialog.opts) do ow = math.max(ow, textw(o)) end
    local oh = #Dialog.opts * 9 + 4
    panel(236 - ow - 18, y - oh - 2, ow + 16, oh)
    for i, o in ipairs(Dialog.opts) do
      local yy = y - oh + 1 + (i - 1) * 9
      if i == Dialog.sel then print(">", 236 - ow - 14, yy, C_GOLD) end
      print(o, 236 - ow - 8, yy, i == Dialog.sel and C_GOLD or C_WHITE)
    end
  elseif Dialog.chars >= #text and (Frame // 15) % 2 == 0 then
    tri(x + w - 10, y + h - 8, x + w - 4, y + h - 8, x + w - 7, y + h - 4, C_GOLD)
  end
end

-- ---------------------------------------------------------------------------
-- HUD pieces
-- ---------------------------------------------------------------------------
local function drawHearts(x, y)
  local p = P
  local n = p.maxhp // 4
  for i = 0, n - 1 do
    local hx = x + (i % 10) * 8
    local hy = y + (i // 10) * 8
    local q = clamp(p.hp - i * 4, 0, 4)
    blit(SPR.heart0, hx, hy)
    if q > 0 then
      clip(hx, hy, q == 4 and 8 or (q * 2 + 1), 8)
      blit(SPR.heart, hx, hy)
      clip()
    end
  end
  -- low health pulse
  if p.hp <= 4 and (Frame // 10) % 2 == 0 then
    local hx = x + ((p.hp - 1) // 4 % 10) * 8
    rectb(hx - 1, y - 1, 9, 9, C_RED)
  end
  return y + ((n - 1) // 10 + 1) * 8
end

local function drawClock(cx, cy, r)
  -- DS dial: day gold, dusk red, night indigo
  circ(cx, cy, r + 1, C_NIGHT)
  local segs = 24
  for k = 0, segs - 1 do
    local t0 = k / segs
    local col = (t0 < DUSK and C_GOLD) or (t0 < NIGHT and C_RED) or (t0 < DAWN and C_INDIGO) or C_PINK
    local a0, a1 = t0 * TAU - math.pi / 2, (k + 1) / segs * TAU - math.pi / 2
    tri(cx, cy, cx + math.cos(a0) * r, cy + math.sin(a0) * r, cx + math.cos(a1) * r, cy + math.sin(a1) * r, col)
  end
  circ(cx, cy, r - 4, C_NIGHT)
  circb(cx, cy, r + 1, C_TAN)
  local a = Clock.t * TAU - math.pi / 2
  line(cx, cy, cx + math.cos(a) * (r + 1), cy + math.sin(a) * (r + 1), C_WHITE)
  circ(cx, cy, 1, C_WHITE)
  local s = tostring(Clock.day)
  local w = textw(s, true)
  print(s, cx - w / 2 + 1, cy - 2, C_WHITE, false, 1, true)
end

local function drawBadge(cx, cy, r, frac, col, icon, label)
  circ(cx, cy, r + 1, C_NIGHT)
  circ(cx, cy, r, C_INDIGO)
  local fill = clamp(frac, 0, 1)
  local top = flr(cy + r - fill * 2 * r)
  clip(cx - r, top, 2 * r + 1, 2 * r + 2)
  circ(cx, cy, r, col)
  clip()
  circb(cx, cy, r + 1, C_TAN)
  if icon then blit(icon, cx - 4, cy - 4) end
  if label then
    local w = textw(label, true)
    print(label, cx - w / 2 + 1, cy + r + 3, C_NIGHT, false, 1, true)
    print(label, cx - w / 2, cy + r + 2, C_WHITE, false, 1, true)
  end
end

local function drawStamina()
  local p = P
  if p.stam >= p.maxstam and not p.exhausted then
    UI.stamShow = math.max(0, (UI.stamShow or 0) - 1)
    if UI.stamShow <= 0 then return end
  else
    UI.stamShow = 40
  end
  local sx, sy = proj(p.x, p.y, p.z)
  local cx, cy = flr(sx + 12), flr(sy - 22)
  local vessels = math.ceil(p.maxstam / 100)
  local frac = p.stam / p.maxstam
  local r = 6
  circ(cx, cy, r + 1, C_NIGHT)
  local col = p.exhausted and ((Frame // 6) % 2 == 0 and C_RED or C_GOLD) or C_LIME
  local n = 20
  local fillN = flr(frac * n + 0.5)
  for k = 0, n - 1 do
    local a0, a1 = k / n * TAU - math.pi / 2, (k + 1) / n * TAU - math.pi / 2
    tri(cx, cy, cx + math.cos(a0) * r, cy + math.sin(a0) * r, cx + math.cos(a1) * r, cy + math.sin(a1) * r, k < fillN and col or C_DKGRN)
  end
  circ(cx, cy, 2, C_NIGHT)
end

local function slot(x, y, s, sel, num)
  rect(x, y, 12, 12, sel and C_TAN or C_NIGHT)
  rectb(x, y, 12, 12, sel and C_GOLD or C_INDIGO)
  if s then
    local r = SPR[s.id == "ryo" and "ryo" or ("i_" .. s.id)]
    if r then blit(r, x + 2, y + 2) end
    if s.n > 1 then
      local t = tostring(s.n)
      local w = textw(t, true)
      print(t, x + 11 - w, y + 7, C_NIGHT, false, 1, true)
      print(t, x + 10 - w, y + 6, C_WHITE, false, 1, true)
    end
  end
end
UI.slot = slot

local function drawHotbar()
  local n = Inv.size
  local w = n * 12 + 4 + 3 * 12
  local x0 = flr((240 - w) / 2)
  local y = 123
  rect(x0 - 2, y - 2, w + 4, 15, C_NIGHT)
  for i = 1, n do slot(x0 + (i - 1) * 12, y, Inv.slots[i], false, i) end
  local ex = x0 + n * 12 + 4
  local eq = { P.weapon, P.armor, P.light }
  for k = 1, 3 do
    slot(ex + (k - 1) * 12, y, eq[k] and { id = eq[k], n = 1 } or nil, false)
    if not eq[k] then
      local lab = ({ "W", "A", "L" })[k]
      print(lab, ex + (k - 1) * 12 + 4, y + 3, C_INDIGO, false, 1, true)
    end
  end
  -- light fuel bar
  if P.light and P.lightFuel and ITEM[P.light].fuel < 99999 then
    local f = P.lightFuel / ITEM[P.light].fuel
    rect(ex + 24, y + 12, flr(12 * f), 1, C_GOLD)
  end
end

local function drawCraftTabs()
  local icons = { "tab_tools", "tab_light", "tab_surv", "tab_combat", "tab_dress" }
  for k, ic in ipairs(icons) do
    local y = 34 + (k - 1) * 12
    rect(0, y, 11, 11, C_NIGHT)
    rectb(-1, y, 12, 11, C_INDIGO)
    blit(SPR[ic], 1, y + 1)
  end
  print("TAB", 0, 96, C_GRAY, false, 1, true)
end

local function drawObjective()
  local tx, ty = Quest.target()
  if not tx then return end
  local tz = groundAt(tx, ty)
  local sx, sy = proj(tx, ty, tz)
  local onScreen = sx > 8 and sx < 232 and sy > 30 and sy < 118
  if onScreen then
    local y = sy - 24 + math.sin(Frame / 8) * 2
    if dist(tx, ty, P.x, P.y) > 20 then blit(SPR.pin, flr(sx - 4), flr(y)) end
  else
    -- arrow at the screen edge, kept clear of the HUD corners and hotbar
    local cx, cy = 120, 78
    local dx, dy = sx - cx, sy - cy
    local l = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx / l, dy / l
    local t = math.min(96 / math.max(math.abs(dx), 0.01), 32 / math.max(math.abs(dy), 0.01))
    local ax, ay = cx + dx * t, cy + dy * t
    local px, py = -dy, dx
    local c = (Frame // 8) % 2 == 0 and C_GOLD or C_RED
    tri(ax + dx * 6, ay + dy * 6, ax + px * 4, ay + py * 4, ax - px * 4, ay - py * 4, C_NIGHT)
    tri(ax + dx * 5, ay + dy * 5, ax + px * 3, ay + py * 3, ax - px * 3, ay - py * 3, c)
    local d = flr(dist(tx, ty, P.x, P.y) / 8)
    local s = d .. "m"
    local w = textw(s, true)
    tprint(s, ax - dx * 9 - w / 2, ay - dy * 9 - 2, C_WHITE, true)
  end
end

local function drawPrompt()
  if Dialog.active or Menu.cur then return end
  local kind, tgt = Player.findInteract()
  local label, x, y, z
  if kind == "ent" then
    label = tgt.prompt or (tgt.kind == "npc" and ("Talk: " .. tgt.name) or "Use")
    x, y, z = tgt.x, tgt.y, tgt.z + 22
  elseif kind == "obj" then
    local d = OBJ[WO[tgt]]
    local verbs = { chest = "Open", sign = "Read", kodama = "Take seed", shrine = "Pray", fire = "Cook", pot = "Cook", logs = "Rekindle",
      statue = "Offer orbs", jizo = "Bow" }
    label = (d.talk and verbs[d.talk] or "Pick up") .. ": " .. (d.name or "")
    x, y = objPos(tgt)
    z = math.max(WH[tgt], 0) + 16
  elseif kind == "tower" then
    label = "Survey the land"
    x, y, z = tgt.x, tgt.y, tgt.top + 20
  else
    -- harvesting hint
    local i = Player.frontObject(13)
    if i then
      local d = OBJ[WO[i]]
      if d.tool and d.name then
        local verb = d.tool == "axe" and "Chop" or (d.tool == "pick" and "Mine" or "Cut")
        local sx, sy = proj(P.x, P.y, P.z)
        local s = verb .. " " .. d.name
        local w = textw(s, true) + 12
        rect(sx - w / 2, sy + 4, w, 9, C_NIGHT)
        blit(SPR.key_z, flr(sx - w / 2), flr(sy + 4))
        print(s, sx - w / 2 + 10, sy + 6, C_WHITE, false, 1, true)
      end
    end
    return
  end
  local sx, sy = proj(x, y, z)
  local w = textw(label, true) + 12
  local bx = clamp(flr(sx - w / 2), 1, 239 - w)
  local by = clamp(flr(sy - 6), 14, 112)
  rect(bx, by, w, 9, C_NIGHT)
  blit(SPR.key_a, bx, by)
  print(label, bx + 10, by + 2, C_WHITE, false, 1, true)
end

function UI.drawHUD()
  local p = P
  local y = drawHearts(2, 2)
  -- tracked quest
  local qt = Quest.tracked and Quest.text(Quest.tracked)
  if qt then
    local q = QBYID[Quest.tracked]
    local col = q.main and C_GOLD or C_WHITE
    tprint(Menu.fit((q.main and "* " or "- ") .. qt, 166, true), 2, y + 2, col, true)
  end
  -- top right: clock, hunger, ryo
  drawClock(226, 13, 11)
  drawBadge(203, 12, 8, p.hunger / 100, (p.hunger < 25) and ((Frame // 10) % 2 == 0 and C_RED or C_GOLD) or C_GOLD, SPR.bowl, tostring(flr(p.hunger)))
  local rs = tostring(p.ryo)
  local rw = textw(rs, true)
  blit(SPR.ryo, 230 - rw - 10, 29)
  tprint(rs, 230 - rw, 31, C_GOLD, true)
  if p.orbs > 0 then
    blit(SPR.orbi, 230 - rw - 30, 29)
    tprint(tostring(p.orbs), 230 - rw - 20, 31, C_BLUE, true)
  end
  -- status icons
  local sxx = 182
  if p.cold > 0 then tprint("COLD", sxx - 6, 4, (Frame // 10) % 2 == 0 and C_BLUE or C_WHITE, true) end
  if p.dark > 60 then tprint("DARK", sxx - 6, 12, C_RED, true) end
  if p.warm > 0 then tprint("WARM", sxx - 6, 20, C_GOLD, true) end
  drawCraftTabs()
  drawHotbar()
  drawStamina()
  drawObjective()
  drawPrompt()
  -- boss bar
  local b = Boss.cur
  if b and b.alive and not b.hidden or (b and b.def and b.def.id == "orochi" and b.alive) then
    local w = 120
    local x = 60
    rect(x - 1, 18, w + 2, 6, C_NIGHT)
    rect(x, 19, flr(w * math.max(0, b.hp) / b.maxhp), 4, C_RED)
    rectb(x - 1, 18, w + 2, 6, C_GOLD)
    local nw = textw(b.def.name, true)
    tprint(b.def.name, 120 - nw / 2, 26, C_WHITE, true)
  end
  -- toasts
  local ty = 113
  for i = #UI.toasts, 1, -1 do
    local t = UI.toasts[i]
    t.life = t.life - 1
    if t.life > 0 then
      local s = Menu.fit(t.s, 216, true)
      local w = textw(s, true)
      rect(14, ty - 1, w + 4, 8, C_NIGHT)
      print(s, 16, ty, C_CREAM, false, 1, true)
      ty = ty - 9
    else
      table.remove(UI.toasts, i)
    end
  end
  -- banner
  if UI.bannerT > 0 then
    UI.bannerT = UI.bannerT - 1
    local a = math.min(1, UI.bannerT / 20, (200 - UI.bannerT) / 10)
    if a > 0.3 then
      local small = textw(UI.bannerS) > 216
      local w = textw(UI.bannerS, small)
      local bw = math.min(236, math.max(w, UI.bannerSub and textw(UI.bannerSub, true) or 0) + 16)
      local h = UI.bannerSub and 20 or 13
      panel(120 - bw / 2, 38, bw, h, C_NIGHT)
      print(UI.bannerS, 120 - w / 2, small and 42 or 41, C_GOLD, false, 1, small)
      if UI.bannerSub then
        local sw = textw(UI.bannerSub, true)
        print(UI.bannerSub, 120 - sw / 2, 50, C_WHITE, false, 1, true)
      end
    end
  end
  -- region name
  if UI.regionT > 0 then
    UI.regionT = UI.regionT - 1
    if UI.regionT < 150 then
      local s = UI.regionS
      local w = textw(s) * 1
      local x = 120 - w / 2
      local y = 64
      if (UI.regionT > 10) or (Frame % 2 == 0) then
        print(s, x + 1, y + 1, C_NIGHT)
        print(s, x, y, C_WHITE)
        line(x - 10, y + 9, x + w + 10, y + 9, C_GOLD)
      end
    end
  end
end

function UI.region(name)
  UI.regionS = name
  UI.regionT = 170
end

-- hotkey use of a hotbar slot
function UI.useSlot(k)
  local s = Inv.slots[k]
  if s then Menu.useItem(k) end
end

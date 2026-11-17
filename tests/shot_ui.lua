-- ============================================================================
--  shot_ui: renders every UI screen with worst-case content (full bag, long
--  names, all quests, toasts, banners, dialogs) and lints the overlay bank:
--  every print/rectb/divider drawn on vbank 1 during the frame is recorded and
--  a FAIL is reported for text that leaves the screen, overlaps other text,
--  or crosses a box border or a divider line. Screens -> build/shots/ui_*.png
-- ============================================================================
local co
local bank = 0
local REC
local _print, _rect, _rectb, _line, _vbank = print, rect, rectb, line, vbank

-- wrappers forward the caller's exact arguments: TIC-80 counts an explicit
-- nil as an argument (a nil scale prints at scale 0, i.e. invisibly)
vbank = function(...)
  local b = ...
  if b then bank = b end
  return _vbank(...)
end
print = function(...)
  local w = _print(...)
  local s, x, y, _, _, scale, small = ...
  if REC and bank == 1 and y and y > -30 and s ~= "" then
    REC.n = REC.n + 1
    REC.texts[#REC.texts + 1] = { s = tostring(s), x = x, y = y, w = w, h = (small and 5 or 6) * (scale or 1), seq = REC.n }
  end
  return w
end
rect = function(x, y, w, h, c)
  if REC and bank == 1 and c ~= 0 then
    REC.n = REC.n + 1
    REC.fills[#REC.fills + 1] = { x = x, y = y, w = w, h = h, seq = REC.n }
  end
  return _rect(x, y, w, h, c)
end
rectb = function(x, y, w, h, c)
  if REC and bank == 1 then
    REC.n = REC.n + 1
    REC.boxes[#REC.boxes + 1] = { x = x, y = y, w = w, h = h, seq = REC.n }
  end
  return _rectb(x, y, w, h, c)
end
line = function(x0, y0, x1, y1, c)
  if REC and bank == 1 and flr(x0) == flr(x1) and math.abs(y1 - y0) > 10 then
    REC.n = REC.n + 1
    REC.vlines[#REC.vlines + 1] = { x = flr(x0), y0 = math.min(y0, y1), y1 = math.max(y0, y1), seq = REC.n }
  end
  return _line(x0, y0, x1, y1, c)
end

-- is the rectangle x0..x1, y0..y1 painted over by an opaque fill drawn after seq?
local function covered(x0, y0, x1, y1, seq)
  for _, f in ipairs(REC.fills) do
    if f.seq > seq and f.x <= x0 and f.y <= y0 and f.x + f.w - 1 >= x1 and f.y + f.h - 1 >= y1 then return true end
  end
  return false
end

local function tick(n)
  for _ = 1, n or 1 do coroutine.yield() end
end

local issues = 0
local function lint(tag)
  local R = REC
  local found = {}
  local function bad(msg)
    if not found[msg] then
      found[msg] = true
      issues = issues + 1
      Test.log("FAIL " .. tag .. ": " .. msg)
    end
  end
  local live = {}
  for _, t in ipairs(R.texts) do
    if not covered(t.x, t.y, t.x + t.w - 1, t.y + t.h - 1, t.seq) then live[#live + 1] = t end
  end
  R.texts = live
  for _, t in ipairs(R.texts) do
    local x0, y0, x1, y1 = t.x, t.y, t.x + t.w - 1, t.y + t.h - 1
    if x0 < 0 or x1 > 239 or y0 < 0 or y1 > 135 then
      bad(string.format("'%s' off screen at %d,%d (w %d)", t.s, t.x, t.y, t.w))
    end
    for _, b in ipairs(R.boxes) do
      local bx0, by0, bx1, by1 = b.x, b.y, b.x + b.w - 1, b.y + b.h - 1
      local vin = y0 >= by0 and y1 <= by1
      local startsIn = x0 > bx0 and x0 < bx1 and vin
      if startsIn and x1 >= bx1 and not covered(bx1, y0, bx1, y1, math.max(b.seq, t.seq)) then
        bad(string.format("'%s' runs past the box at x %d..%d (ends %d)", t.s, bx0, bx1, x1))
      end
    end
    for _, l in ipairs(R.vlines) do
      if x0 < l.x and x1 > l.x and y1 >= l.y0 and y0 <= l.y1 and not covered(l.x, y0, l.x, y1, math.max(l.seq, t.seq)) then
        bad(string.format("'%s' crosses the divider at x %d", t.s, l.x))
      end
    end
  end
  for i = 1, #R.texts do
    local a = R.texts[i]
    for j = i + 1, #R.texts do
      local b = R.texts[j]
      local ix0, iy0 = math.max(a.x, b.x), math.max(a.y, b.y)
      local ix1, iy1 = math.min(a.x + a.w, b.x + b.w) - 2, math.min(a.y + a.h, b.y + b.h) - 2
      if a.s ~= b.s and ix0 <= ix1 and iy0 <= iy1 and not covered(ix0, iy0, ix1, iy1, math.min(a.seq, b.seq)) then
        bad(string.format("'%s' overlaps '%s'", a.s, b.s))
      end
    end
  end
end

-- draw one frame of the current state, lint it, save it
local function shot(tag)
  REC = { texts = {}, boxes = {}, vlines = {}, fills = {}, n = 0 }
  tick()
  lint(tag)
  REC = nil
  Test.dump("ui_" .. tag)
end

local function press(k)
  In.fake = { [k] = true }
  tick()
  tick()
end

local function script()
  Game.newGame()
  while Dialog.active do In.fake = { atk = true } tick() tick() end
  tick(220)
  UI.regionT, UI.bannerT = 0, 0
  -- worst-case player state
  P.ryo, P.orbs, P.seeds, P.hunger = 99999, 12, 19, 64
  P.maxhp, P.hp = 48, 23
  Clock.day = 128
  Inv.size = 16
  for i, id in ipairs({ "steel", "sarmor", "lantern", "stew", "onigiri", "sushi", "tea", "shuriken", "wood", "bamboo",
    "flint", "grass", "pelt", "silk", "magatama", "mirror" }) do
    Inv.slots[i] = ITEM[id] and { id = id, n = math.min(ITEM[id].s, 99) } or nil
  end
  P.weapon, P.armor, P.light = "steel", "sarmor", "lantern"
  for _, q in ipairs(QUESTS) do
    if not QS[q.id] then QS[q.id] = { st = "active", step = 1, count = 0 } end
  end
  QS.mq1.st, QS.rice.st, QS.cat.st = "done", "done", "done"
  Quest.tracked = "mq4"
  QS.mq4.step = 2

  -- HUD
  shot("hud")
  UI.toast("A hatchet chops faster (Craft > Tools)")
  UI.toast("Need a pickaxe for that")
  UI.toast("The Yami claws at you! Light a torch or fire!")
  UI.banner("Quest complete: The Sword in the Serpent", "Kusanagi, the grass-cutting sword, is yours!")
  P.cold, P.dark, P.warm = 5, 90, 30
  shot("hud_busy")
  UI.toasts, UI.bannerT = {}, 0
  P.cold, P.dark, P.warm = 0, 0, 0
  UI.region("Whispering Bamboo")
  UI.regionT = 120
  shot("hud_region")
  UI.regionT = 0

  -- pause menu, every tab
  Menu.open("pause", { tab = 1 })
  for sel = 1, 16, 5 do
    Menu.sel = sel
    shot("items_" .. sel)
  end
  Menu.tab = 2
  for c = 1, 5 do
    Menu.ctab, Menu.sel = c, 1
    shot("craft_" .. c)
  end
  Menu.tab, Menu.sel = 3, 1
  shot("map")
  Menu.tab = 4
  for sel = 1, 16, 5 do
    Menu.sel = sel
    shot("quests_" .. sel)
  end
  Menu.tab, Menu.sel = 5, 3
  shot("system")
  Menu.sub = "help"
  shot("system_help")
  Menu.sub = nil
  Menu.close()
  tick(2)

  -- cooking and shops
  Inv.slots[11] = { id = "meat", n = 5 }
  Inv.slots[12] = { id = "rice", n = 5 }
  Inv.slots[13] = { id = "fish", n = 5 }
  Menu.open("cook", { fire = true })
  shot("cook_fire")
  Menu.close()
  Menu.open("cook", { pot = true })
  Menu.pick = { "meat", "rice", "fish", "rice" }
  shot("cook_pot")
  Menu.close()
  for name in pairs(SHOPS) do
    Menu.open("shop", { shop = name, who = { name = "Merchant Daikoku-ya" } })
    Menu.buy, Menu.sel = true, 1
    shot("shop_" .. name)
    Menu.close()
  end
  Menu.open("shop", { shop = "hanamura", who = { name = "Merchant" } })
  Menu.buy, Menu.sel = false, 1
  shot("shop_sell")
  Menu.close()
  tick(2)

  -- dialogs
  Dialog.lines("Lady Sayo", { "Shuten-doji, the Oni King, stole the Three Sacred Treasures. Without them the nights lengthen and yokai roam freely across the whole realm of the rising sun." })
  Dialog.chars = 999
  shot("dialog")
  Dialog.active = false
  Dialog.ask("Kannon Statue", "Offer 4 Spirit Orbs. Which blessing do you seek?", { "Heart container", "Stamina vessel" })
  Dialog.chars = 999
  shot("dialog_ask")
  Dialog.active = false
  tick(2)

  -- death and finale
  Game.state, Game.deadT, Game.deathWhy = "dead", 120, "dark"
  shot("dead")
  Game.state, Game.finT = "finale", 400
  shot("finale")
  Game.state = "play"
  tick(2)

  -- title and its controls panel
  Game.state, Game.titleSel = "title", 1
  shot("title")
  Game.help = true
  shot("title_help")
  Test.ok(issues == 0, "UI lint: " .. issues .. " issue(s)")
end

co = coroutine.create(script)

function TIC()
  In.fake = In.fake or {}
  if coroutine.status(co) == "dead" then Test.finish() return end
  local ok, err = coroutine.resume(co)
  if not ok then
    Test.log("FAIL script error: " .. tostring(err))
    Test.finish()
    return
  end
  if P then
    P.iframes = math.max(P.iframes, 2)
    Clock.t = 0.3
  end
  Game.tick()
  In.fake = {}
end

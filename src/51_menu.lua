-- ============================================================================
--  51 MENUS - pause menu (Items / Craft / Map / Quests / System), cooking,
--  shops, world map with fog of war and pagoda fast travel.
-- ============================================================================
Menu = { cur = nil, tab = 1, sel = 1, ctab = 1, csel = 1 }
MapUI = { seen = {} }
local TABN = { "Items", "Craft", "Map", "Quests", "System" }

function Menu.open(kind, opt)
  Menu.cur = kind
  Menu.opt = opt or {}
  Menu.sel = 1
  Menu.sub = nil
  if kind == "pause" then Menu.tab = Menu.opt.tab or Menu.tab end
  if kind == "cook" then Menu.pick = {} end
  if kind == "shop" then Menu.buy = true end
  Sfx.play("open")
end
function Menu.close()
  Menu.cur = nil
  Sfx.play("close")
end

-- ---------------------------------------------------------------------------
-- using items
-- ---------------------------------------------------------------------------
function Menu.useItem(k)
  local s = Inv.slots[k]
  if not s then return end
  local it = ITEM[s.id]
  local p = P
  if it.k == "food" then
    if it.hun then p.hunger = math.min(100, p.hunger + it.hun) end
    if it.hp then
      if it.hp > 0 then Player.heal(it.hp) else Player.damage(-it.hp, nil, nil, "food") UI.toast("Ugh... that was bad.") end
    end
    if it.stam then
      p.stam = math.min(p.maxstam, p.stam + it.stam)
      if p.stam > 0 then p.exhausted = false end
    end
    if it.warm then p.warm = math.max(p.warm, it.warm) UI.toast("You feel warm inside.") end
    Inv.take(s.id, 1)
    Sfx.play("eat")
    FX.text(p.x, p.y, p.z + 18, "Yum!", C_GOLD)
  elseif it.k == "weapon" then
    p.weapon = s.id
    UI.toast("Equipped " .. it.n)
    Sfx.play("equip")
  elseif it.k == "armor" then
    p.armor = (p.armor == s.id) and nil or s.id
    UI.toast(p.armor and ("Wearing " .. it.n) or "Unequipped")
    Sfx.play("equip")
  elseif it.k == "light" then
    if p.light == s.id then
      p.light = nil
      UI.toast("Light put away")
    else
      p.light = s.id
      p.lightFuel = it.fuel
      if s.id == "torch" then Inv.take("torch", 1) end
      UI.toast("Lit the " .. it.n)
    end
    Sfx.play("fire")
  elseif it.k == "place" then
    local o = it.obj == "fire" and O_FIRE or O_POT
    if World.place(o) then Inv.take(s.id, 1) end
  elseif it.k == "bed" then
    if Clock.isNight() or Clock.t > DUSK then
      if Game.safeToSleep() then Game.sleep() else UI.toast("Too dangerous to sleep here!") end
    else
      UI.toast("You can only sleep at dusk or night.")
    end
  elseif it.k == "tool" then
    UI.toast(it.d)
  else
    UI.toast(it.n .. ": " .. it.d)
  end
end

local function dropItem(k)
  local s = Inv.slots[k]
  if not s or ITEM[s.id].key then return end
  Inv.slots[k] = nil
  local e = Drops.spawn(P.x + math.cos(P.dir) * 8, P.y + math.sin(P.dir) * 8, P.z + 6, s.id, s.n)
  e.t = -60
  if P.weapon == s.id then P.weapon = "bokken" end
  if P.armor == s.id then P.armor = nil end
end

-- ---------------------------------------------------------------------------
-- update
-- ---------------------------------------------------------------------------
local function nav(n, cols)
  cols = cols or 1
  local s = Menu.sel
  if In.p.up then s = s - cols end
  if In.p.down then s = s + cols end
  if cols > 1 then
    if In.p.left then s = s - 1 end
    if In.p.right then s = s + 1 end
  end
  if s ~= Menu.sel then Sfx.play("menu") end
  Menu.sel = clamp(s, 1, math.max(1, n))
end

local function recipesIn(tab)
  local l = {}
  for _, r in ipairs(RECIPES) do if r.tab == TABS[tab] then l[#l + 1] = r end end
  return l
end

local function cookables(pot)
  local l = {}
  for i = 1, Inv.size do
    local s = Inv.slots[i]
    if s and ITEM[s.id].k == "food" then
      if pot or ITEM[s.id].cook then
        local dup = false
        for _, x in ipairs(l) do if x == s.id then dup = true end end
        if not dup then l[#l + 1] = s.id end
      end
    end
  end
  return l
end

local function potResult(pick)
  local have = {}
  for _, id in ipairs(pick) do have[id] = (have[id] or 0) + 1 end
  for _, r in ipairs(POT) do
    local ok = true
    local n = 0
    for _, nd in ipairs(r.need) do
      if (have[nd[1]] or 0) ~= nd[2] then ok = false end
      n = n + nd[2]
    end
    if ok and n == #pick then return r.out end
  end
  return nil
end

function Menu.update()
  local k = Menu.cur
  if In.p.menu and k == "pause" then Menu.close() return end
  if k == "pause" then
    if not Menu.sub then
      if In.p.left and Menu.tab ~= 1 or In.p.rotl then Menu.tab = (Menu.tab - 2) % 5 + 1 Menu.sel = 1 Sfx.play("menu") return end
      if In.p.right and Menu.tab ~= 1 or In.p.rotr then Menu.tab = Menu.tab % 5 + 1 Menu.sel = 1 Sfx.play("menu") return end
    end
    if In.p.jump then
      if Menu.sub then Menu.sub = nil Sfx.play("close") else Menu.close() end
      return
    end
    local t = Menu.tab
    if t == 1 then
      if In.p.left and Menu.sel % 4 == 1 then Menu.tab = 5 Menu.sel = 1 Sfx.play("menu") return end
      if In.p.right and Menu.sel % 4 == 0 then Menu.tab = 2 Menu.sel = 1 Sfx.play("menu") return end
      nav(Inv.size, 4)
      if In.p.atk or In.p.ok then Menu.useItem(Menu.sel) end
      if In.p.use then dropItem(Menu.sel) Sfx.play("place") end
    elseif t == 2 then
      local list = recipesIn(Menu.ctab)
      if In.p.throw then Menu.ctab = Menu.ctab % #TABS + 1 Menu.sel = 1 Sfx.play("menu") end
      nav(#list)
      local r = list[Menu.sel]
      if r and (In.p.atk or In.p.ok) then
        if Craft.make(r) then
          Sfx.play("craft")
          UI.toast("Crafted " .. ITEM[r.out].n .. (r.n > 1 and (" x" .. r.n) or ""))
          Quest.event("craft", r.out)
        else
          Sfx.play("error")
          UI.toast("Missing ingredients")
        end
      end
    elseif t == 3 then
      local on = {}
      for _, tw in ipairs(TOWERS) do if Quest.towersOn[tw.id] then on[#on + 1] = tw end end
      nav(#on)
      local tw = on[Menu.sel]
      if tw and (In.p.atk or In.p.ok) then
        if Boss.cur or Shrine.trial then
          UI.toast("Can't travel during a battle!")
        else
          Menu.close()
          Game.travel(tw)
        end
      end
    elseif t == 4 then
      local list = Menu.questList()
      nav(#list)
      if list[Menu.sel] and (In.p.atk or In.p.ok) and Quest.state(list[Menu.sel].id) == "active" then
        Quest.tracked = list[Menu.sel].id
        Sfx.play("select")
      end
    elseif t == 5 then
      nav(5)
      if In.p.atk or In.p.ok then
        if Menu.sel == 1 then
          Game.save()
          UI.toast("Game saved")
          Sfx.play("select")
        elseif Menu.sel == 2 then
          Menu.sub = "help"
        elseif Menu.sel == 3 then
          Audio.setLevels((Audio.music + 3) % 4, Audio.sfx)
          Sfx.play("select")
        elseif Menu.sel == 4 then
          Audio.setLevels(Audio.music, (Audio.sfx + 3) % 4)
          Sfx.play("select")
        elseif Menu.sel == 5 then
          Game.save()
          Menu.close()
          Game.toTitle()
        end
      end
    end
  elseif k == "cook" then
    if In.p.jump or In.p.menu then Menu.close() return end
    local pot = Menu.opt.pot
    local list = cookables(pot)
    nav(#list + (pot and 1 or 0))
    if In.p.atk or In.p.ok then
      if pot then
        if Menu.sel == #list + 1 then
          local out = potResult(Menu.pick)
          if out then
            for _, id in ipairs(Menu.pick) do Inv.take(id, 1) end
            Drops.give(out, 1)
            Sfx.play("craft")
            UI.toast("Cooked " .. ITEM[out].n .. "!")
          else
            Sfx.play("error")
            UI.toast("That combination makes nothing...")
          end
          Menu.pick = {}
        else
          local id = list[Menu.sel]
          if id and #Menu.pick < 3 then
            local used = 0
            for _, x in ipairs(Menu.pick) do if x == id then used = used + 1 end end
            if Inv.count(id) > used then Menu.pick[#Menu.pick + 1] = id Sfx.play("menu") end
          end
        end
      else
        local id = list[Menu.sel]
        if id then
          Inv.take(id, 1)
          Drops.give(ITEM[id].cook, 1)
          Sfx.play("craft")
        end
      end
    end
    if In.p.use and pot then Menu.pick = {} end
  elseif k == "shop" then
    if In.p.jump or In.p.menu then Menu.close() return end
    if In.p.left or In.p.right then Menu.buy = not Menu.buy Menu.sel = 1 Sfx.play("menu") end
    local stock = SHOPS[Menu.opt.shop]
    if Menu.buy then
      nav(#stock // 2)
      if In.p.atk or In.p.ok then
        local id, price = stock[Menu.sel * 2 - 1], stock[Menu.sel * 2]
        if P.ryo < price then Sfx.play("error") UI.toast("Not enough ryo")
        elseif Inv.add(id, 1) > 0 then Sfx.play("error") UI.toast("Bag is full")
        else
          P.ryo = P.ryo - price
          Sfx.play("coin")
          Quest.event("item", id)
        end
      end
    else
      nav(Inv.size)
      if In.p.atk or In.p.ok then
        local s = Inv.slots[Menu.sel]
        if s and not ITEM[s.id].key and ITEM[s.id].sell then
          Inv.take(s.id, 1)
          P.ryo = P.ryo + ITEM[s.id].sell
          if P.weapon == s.id and not Inv.has(s.id) then P.weapon = "bokken" end
          if P.armor == s.id and not Inv.has(s.id) then P.armor = nil end
          Sfx.play("coin")
        end
      end
    end
  end
end

function Menu.questList()
  local l = {}
  for _, q in ipairs(QUESTS) do if Quest.state(q.id) == "active" then l[#l + 1] = q end end
  for _, q in ipairs(QUESTS) do if Quest.state(q.id) == "done" then l[#l + 1] = q end end
  return l
end

-- ---------------------------------------------------------------------------
-- drawing. Panels keep a key-hint footer row on their last 10 pixels: content
-- ends above the divider. The world behind menus is dimmed through the bank-0
-- palette (Game.tick), not with scanlines.
-- ---------------------------------------------------------------------------
-- key cap: the Z/X/A/S sprites, else a drawn cap with the letter(s)
function Menu.key(k, x, y)
  local r = SPR["key_" .. k]
  if r then blit(r, x, y) return 8 end
  local w = textw(k:upper(), true) + 3
  rect(x, y, w, 7, C_NIGHT)
  rect(x + 1, y, w - 2, 7, C_WHITE)
  print(k:upper(), x + 2, y + 1, C_NIGHT, false, 1, true)
  return w
end

-- hints from the left ({key, label} pairs), the close key on the right
local function footer(items, x0, x1, y, back)
  line(x0, y - 3, x1, y - 3, C_INDIGO)
  local x = x0 + 2
  for _, it in ipairs(items) do
    x = x + Menu.key(it[1], x, y) + 2
    x = x + print(it[2], x, y + 1, C_WHITE, false, 1, true) + 6
  end
  local s = back or "Close"
  local w = textw(s, true)
  Menu.key("x", x1 - w - 11, y)
  print(s, x1 - w - 1, y + 1, C_WHITE, false, 1, true)
end

-- text cut to a pixel width with an ellipsis
function Menu.fit(s, w, small)
  if textw(s, small) <= w then return s end
  while #s > 1 and textw(s .. "..", small) > w do s = s:sub(1, -2) end
  return s .. ".."
end

local function itemInfo(id, x, y, w)
  local it = ITEM[id]
  if not it then return end
  tprint(Menu.fit(it.n, w), x, y, C_GOLD)
  local yy = y + 10
  for _, l in ipairs(wrap(it.d or "", w, true)) do print(l, x, yy, C_WHITE, false, 1, true) yy = yy + 7 end
  local stats = {}
  if it.hun then stats[#stats + 1] = "Hunger +" .. it.hun end
  if it.hp then stats[#stats + 1] = (it.hp > 0 and "Hearts +" or "Hearts ") .. (it.hp / 4) end
  if it.stam then stats[#stats + 1] = "Stamina +" .. math.min(it.stam, 100) end
  if it.dmg then stats[#stats + 1] = "Attack " .. it.dmg end
  if it.def then stats[#stats + 1] = "Defense " .. it.def end
  for _, s in ipairs(stats) do print(s, x, yy + 2, C_LIME, false, 1, true) yy = yy + 7 end
  return yy
end

-- equal tabs centred between the Q and E caps
local function drawTabs()
  local n, w, gap = #TABN, 41, 2
  local x0 = (240 - (n * w + (n - 1) * gap)) // 2
  Menu.key("q", x0 - 11, 5)
  Menu.key("e", x0 + n * w + (n - 1) * gap + 4, 5)
  for i, name in ipairs(TABN) do
    local x = x0 + (i - 1) * (w + gap)
    local sel = i == Menu.tab
    rect(x, 3, w, 12, sel and C_RED or C_NIGHT)
    rectb(x, 3, w, 12, sel and C_GOLD or C_TAN)
    print(name, x + (w - textw(name)) // 2 + 1, 6, sel and C_WHITE or C_GRAY)
  end
end

-- first visible row of a scrolling list of n rows showing `rows` at a time
function Menu.scroll(n, rows)
  return clamp(Menu.sel - rows // 2, 1, math.max(1, n - rows + 1))
end
function Menu.scrollMarks(x, y0, y1, first, rows, n)
  if first > 1 then tri(x, y0 + 3, x + 4, y0 + 3, x + 2, y0, C_GOLD) end
  if first + rows - 1 < n then tri(x, y1 - 3, x + 4, y1 - 3, x + 2, y1, C_GOLD) end
end

function Menu.draw()
  local k = Menu.cur
  if not k then return end
  if k == "pause" then
    drawTabs()
    local t = Menu.tab
    if t == 1 then
      panel(4, 17, 232, 115)
      for i = 1, Inv.size do
        local cx = 10 + ((i - 1) % 4) * 16
        local cy = 21 + ((i - 1) // 4) * 16
        UI.slot(cx, cy, Inv.slots[i], i == Menu.sel)
        if i <= 10 then print(tostring(i % 10), cx - 4, cy, C_GRAY, false, 1, true) end
      end
      print("Equipped", 10, 84, C_TAN, false, 1, true)
      local eq = { P.weapon, P.armor, P.light }
      for j = 1, 3 do
        UI.slot(10 + (j - 1) * 16, 91, eq[j] and { id = eq[j], n = 1 } or nil, false)
      end
      print("Bag " .. Inv.size .. "/16", 10, 107, C_GRAY, false, 1, true)
      line(76, 20, 76, 116, C_INDIGO)
      blit(SPR.seed, 82, 106)
      print(P.seeds .. " seeds", 92, 108, C_WHITE, false, 1, true)
      blit(SPR.orbi, 136, 106)
      print(P.orbs .. " orbs", 146, 108, C_WHITE, false, 1, true)
      local s = Inv.slots[Menu.sel]
      local hints = {}
      if s then
        itemInfo(s.id, 82, 22, 148)
        local it = ITEM[s.id]
        local act = ({ food = "Eat", weapon = "Equip", armor = "Wear", light = "Light", place = "Place", bed = "Sleep" })[it.k]
        if act then hints[#hints + 1] = { "z", act } end
        if not it.key then hints[#hints + 1] = { "a", "Drop" } end
      else
        print("Empty slot", 82, 22, C_GRAY)
      end
      footer(hints, 8, 231, 122)
    elseif t == 2 then
      panel(4, 17, 232, 115)
      local icons = { "tab_tools", "tab_light", "tab_surv", "tab_combat", "tab_dress" }
      for i, ic in ipairs(icons) do
        local y = 21 + (i - 1) * 19
        rect(8, y, 16, 16, i == Menu.ctab and C_RED or C_NIGHT)
        rectb(8, y, 16, 16, i == Menu.ctab and C_GOLD or C_INDIGO)
        blit(SPR[ic], 12, y + 4)
      end
      tprint(TABS[Menu.ctab], 30, 21, C_GOLD)
      local list = recipesIn(Menu.ctab)
      for i, r in ipairs(list) do
        local y = 32 + (i - 1) * 12
        local can = Craft.can(r)
        if i == Menu.sel then rect(29, y - 2, 82, 12, C_INDIGO) end
        blit(SPR["i_" .. r.out], 31, y)
        print(Menu.fit(ITEM[r.out].n .. (r.n > 1 and (" x" .. r.n) or ""), 66, true), 42, y + 1, can and C_WHITE or C_GRAY, false, 1, true)
      end
      line(114, 20, 114, 116, C_INDIGO)
      local r = list[Menu.sel]
      if r then
        local yy = itemInfo(r.out, 120, 22, 110)
        yy = math.max(yy + 4, 66)
        print("Needs:", 120, yy, C_TAN, false, 1, true)
        for j, nd in ipairs(r.need) do
          local have = Inv.count(nd[1])
          local y2 = yy + 8 + (j - 1) * 10
          blit(SPR["i_" .. nd[1]], 120, y2)
          print(Menu.fit(ITEM[nd[1]].n, 64, true) .. " " .. have .. "/" .. nd[2], 131, y2 + 2, have >= nd[2] and C_LIME or C_RED, false, 1, true)
        end
      end
      footer({ { "z", "Craft" }, { "s", "Category" } }, 8, 231, 122)
    elseif t == 3 then
      MapUI.draw()
    elseif t == 4 then
      panel(4, 17, 232, 115)
      local list = Menu.questList()
      local rows = 12
      local first = Menu.scroll(#list, rows)
      for i = first, math.min(#list, first + rows - 1) do
        local q = list[i]
        local y = 21 + (i - first) * 8
        local done = Quest.state(q.id) == "done"
        local col = done and C_GRAY or (q.main and C_GOLD or C_WHITE)
        if i == Menu.sel then rect(7, y - 1, 100, 8, C_INDIGO) end
        print(Menu.fit((Quest.tracked == q.id and ">" or " ") .. q.name, 96, true), 8, y, col, false, 1, true)
      end
      Menu.scrollMarks(107, 19, 115, first, rows, #list)
      line(114, 20, 114, 116, C_INDIGO)
      local q = list[Menu.sel]
      local hints = {}
      if q then
        local yy = 22
        for _, l in ipairs(wrap(q.name, 110, true)) do tprint(l, 120, yy, q.main and C_GOLD or C_WHITE, true) yy = yy + 7 end
        yy = yy + 3
        local s = QS[q.id]
        for j, st in ipairs(q.steps) do
          local done = s.st == "done" or j < s.step
          local cur = s.st == "active" and j == s.step
          if done or cur then
            local txt = cur and Quest.text(q.id) or st.text
            for _, l in ipairs(wrap((done and "v " or "> ") .. txt, 110, true)) do
              if yy <= 110 then print(l, 120, yy, done and C_GRAY or C_WHITE, false, 1, true) end
              yy = yy + 7
            end
            yy = yy + 2
          end
        end
        if s.st == "active" then hints[1] = { "z", Quest.tracked == q.id and "Tracking" or "Track" } end
      end
      footer(hints, 8, 231, 122)
    elseif t == 5 then
      panel(4, 17, 232, 115)
      if Menu.sub == "help" then
        local lines = { "Arrows  move      SHIFT/C  sprint", "X  jump, hold in air: glide, in water: leap", "Z  katana / chop / mine, in air: plunge",
          "A  talk, pick up, open, cook", "S  throw shuriken   Q/E  rotate camera", "Push into walls to climb, X to leap",
          "TAB menu   M map   J quests   1-0 use slot", "Eat to stay fed. At night carry light,", "or the Yami will find you." }
        for i, l in ipairs(lines) do print(l, 12, 23 + (i - 1) * 10, C_WHITE, false, 1, true) end
        footer({}, 8, 231, 122, "Back")
      else
        local lv = Audio.LEVELS
        local opts = { "Save game", "Controls", "Music volume: " .. lv[Audio.music], "Sound volume: " .. lv[Audio.sfx], "Save & quit to title" }
        for i, o in ipairs(opts) do
          local y = 23 + (i - 1) * 13
          if i == Menu.sel then rect(10, y - 3, 150, 12, C_INDIGO) end
          print(o, 16, y, i == Menu.sel and C_GOLD or C_WHITE)
        end
        print("Day " .. Clock.day .. "   Kills " .. Menu.totalKills(), 16, 92, C_GRAY, false, 1, true)
        print("Towers " .. Quest.towerCount() .. "/" .. #TOWERS .. "   Shrines " .. Menu.count(Shrine.done) .. "/" .. #SHRINES, 16, 100, C_GRAY, false, 1, true)
        print("Kodama found " .. Menu.count(World.found) .. "/" .. #KODAMA, 16, 108, C_GRAY, false, 1, true)
        footer({ { "z", Menu.sel >= 3 and Menu.sel <= 4 and "Change" or "Select" } }, 8, 231, 122)
      end
    end
  elseif k == "cook" then
    local pot = Menu.opt.pot
    panel(30, 16, 180, 104)
    tprint(pot and "Cooking Pot" or "Campfire", 36, 20, C_GOLD)
    local list = cookables(pot)
    local n = #list + (pot and 1 or 0)
    local rows = 6
    local first = Menu.scroll(n, rows)
    for i = first, math.min(n, first + rows - 1) do
      local y = 32 + (i - first) * 11
      if i == Menu.sel then rect(34, y - 2, 90, 11, C_INDIGO) end
      local id = list[i]
      if id then
        blit(SPR["i_" .. id], 36, y)
        print(Menu.fit(ITEM[id].n .. " x" .. Inv.count(id), 76, true), 47, y + 1, C_WHITE, false, 1, true)
      else
        print("> Cook!", 38, y + 1, C_GOLD, false, 1, true)
      end
    end
    Menu.scrollMarks(118, 30, 96, first, rows, n)
    if #list == 0 then print(pot and "No ingredients" or "Nothing to cook", 36, 34, C_GRAY, false, 1, true) end
    if pot then
      print("In the pot:", 130, 32, C_TAN, false, 1, true)
      for j, id in ipairs(Menu.pick) do blit(SPR["i_" .. id], 130 + (j - 1) * 11, 42) end
      local out = potResult(Menu.pick)
      if out then
        print("Makes:", 130, 58, C_TAN, false, 1, true)
        blit(SPR["i_" .. out], 130, 66)
        print(Menu.fit(ITEM[out].n, 64, true), 141, 68, C_LIME, false, 1, true)
      end
      footer({ { "z", "Add" }, { "a", "Clear" } }, 34, 205, 108)
    else
      local id = list[Menu.sel]
      if id then
        print("Cooks into:", 130, 32, C_TAN, false, 1, true)
        local out = ITEM[id].cook
        blit(SPR["i_" .. out], 130, 42)
        print(Menu.fit(ITEM[out].n, 64, true), 141, 44, C_LIME, false, 1, true)
      end
      footer({ { "z", "Cook" } }, 34, 205, 108)
    end
  elseif k == "shop" then
    local stock = SHOPS[Menu.opt.shop]
    panel(16, 8, 208, 122)
    local rs = tostring(P.ryo)
    local rw = textw(rs, true)
    blit(SPR.ryo, 216 - rw - 10, 12)
    print(rs, 216 - rw, 14, C_GOLD, false, 1, true)
    local who = Menu.opt.who and Menu.opt.who.name or "Shop"
    tprint(Menu.fit(who, 216 - rw - 10 - 28), 22, 13, C_GOLD)
    for j, lab in ipairs({ "Buy", "Sell" }) do
      local x = 22 + (j - 1) * 32
      local on = (j == 1) == (Menu.buy == true)
      rect(x, 24, 30, 9, on and C_RED or C_NIGHT)
      rectb(x, 24, 30, 9, on and C_GOLD or C_INDIGO)
      print(lab, x + (30 - textw(lab, true)) // 2 + 1, 26, on and C_WHITE or C_GRAY, false, 1, true)
    end
    if Menu.buy then
      for i = 1, #stock // 2 do
        local id, price = stock[i * 2 - 1], stock[i * 2]
        local y = 38 + (i - 1) * 10
        if i == Menu.sel then rect(20, y - 2, 114, 10, C_INDIGO) end
        blit(SPR["i_" .. id], 22, y - 1)
        print(Menu.fit(ITEM[id].n, 70, true), 33, y, P.ryo >= price and C_WHITE or C_GRAY, false, 1, true)
        local ps = price .. "r"
        print(ps, 132 - textw(ps, true), y, C_GOLD, false, 1, true)
      end
      line(137, 36, 137, 116, C_INDIGO)
      local id = stock[Menu.sel * 2 - 1]
      if id then itemInfo(id, 142, 38, 76) end
    else
      for i = 1, Inv.size do
        local s = Inv.slots[i]
        local y = 38 + ((i - 1) % 8) * 10
        local x = 20 + ((i - 1) // 8) * 100
        if i == Menu.sel then rect(x, y - 2, 98, 10, C_INDIGO) end
        if s then
          blit(SPR["i_" .. s.id], x + 2, y - 1)
          local it = ITEM[s.id]
          local ps = it.key and "-" or (it.sell .. "r")
          print(Menu.fit(it.n, 82 - textw(ps, true), true), x + 13, y, it.key and C_GRAY or C_WHITE, false, 1, true)
          print(ps, x + 96 - textw(ps, true), y, it.key and C_GRAY or C_GOLD, false, 1, true)
        end
      end
    end
    footer({ { "z", Menu.buy and "Buy" or "Sell" }, { "<>", "Switch" } }, 20, 219, 120, "Leave")
  end
end

function Menu.count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function Menu.totalKills() local n = 0 for _, v in pairs(P.kills) do n = n + v end return n end

-- ---------------------------------------------------------------------------
-- world map: map texture minified to 1px/cell + fog of war (4x4 cell blocks)
-- ---------------------------------------------------------------------------
function MapUI.reveal(x, y, r)
  local bx, by = flr(x / 32), flr(y / 32)
  local rb = math.ceil(r / 4)
  for yy = by - rb, by + rb do
    for xx = bx - rb, bx + rb do
      if xx >= 0 and yy >= 0 and xx < 60 and yy < 28 and (xx - bx) ^ 2 + (yy - by) ^ 2 <= rb * rb then
        MapUI.seen[yy * 60 + xx] = true
      end
    end
  end
end

function MapUI.draw()
  local ox, oy = 0, 18
  rect(0, 16, 240, 116, C_INDIGO)
  ttri(ox, oy, ox + 240, oy, ox, oy + 112, 4, 4, 1924, 4, 4, 900, 1)
  ttri(ox + 240, oy, ox + 240, oy + 112, ox, oy + 112, 1924, 4, 1924, 900, 4, 900, 1)
  -- fog
  for by = 0, 27 do
    for bx = 0, 59 do
      if not MapUI.seen[by * 60 + bx] then
        rect(ox + bx * 4, oy + by * 4, 4, 4, ((bx + by) % 2 == 0) and C_NIGHT or C_INDIGO)
      end
    end
  end
  local function mark(x, y, icon)
    local mx, my = ox + x / 8, oy + y / 8
    if MapUI.seen[flr(y / 32) * 60 + flr(x / 32)] then blit(SPR[icon], flr(mx - 4), flr(my - 4)) end
  end
  for _, t in ipairs(TOWNS) do mark(t.x, t.y, "townico") end
  for _, s in ipairs(SHRINES) do
    if MapUI.seen[flr(s.y / 32) * 60 + flr(s.x / 32)] then
      local mx, my = ox + s.x / 8, oy + s.y / 8
      circ(mx, my, 2, Shrine.done[s.id] and C_BLUE or C_WHITE)
      circb(mx, my, 2, C_NIGHT)
    end
  end
  local on = {}
  for _, tw in ipairs(TOWERS) do
    mark(tw.x, tw.y, "towerico")
    if Quest.towersOn[tw.id] then on[#on + 1] = tw end
  end
  for id, b in pairs({ jorogumo = "lair", tengulord = "summit", orochi = "lake", shuten = "onigashima" }) do
    if not Boss.defeated[id] and Quest.state("mq2") == "done" then
      local p = POI[b]
      blit(SPR.bossico, flr(ox + p.x / 8 - 4), flr(oy + p.y / 8 - 4))
    end
  end
  local tx, ty = Quest.target()
  if tx and (Frame // 10) % 2 == 0 then blit(SPR.pin, flr(ox + tx / 8 - 4), flr(oy + ty / 8 - 8)) end
  -- player
  local px, py = ox + P.x / 8, oy + P.y / 8
  if (Frame // 8) % 2 == 0 then circ(px, py, 2, C_RED) end
  circb(px, py, 3, C_WHITE)
  -- fast travel list
  if #on > 0 then
    local sel = on[clamp(Menu.sel, 1, #on)]
    if sel then
      local mx, my = ox + sel.x / 8, oy + sel.y / 8
      rectb(mx - 6, my - 6, 12, 12, (Frame // 6) % 2 == 0 and C_GOLD or C_WHITE)
      tprint("Z: travel to " .. sel.name, 4, 124, C_GOLD, true)
    end
  else
    tprint("Survey pagodas (climb + A) to unlock fast travel", 4, 124, C_WHITE, true)
  end
end

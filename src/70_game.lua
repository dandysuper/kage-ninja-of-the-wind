-- ============================================================================
--  70 GAME - states (title / play / dead / finale), the frame pipeline,
--  camera follow, weather, sleeping, fast travel, death and new game.
-- ============================================================================
Game = { state = "title", safe = false, region = nil, titleSel = 1, fade = 0 }
local WEATHER = {}

function Game.boot()
  Boot.all()
  FX.init()
  NPC.spawnAll()
  Game.state = "title"
  Game.titleSel = Save.exists() and 1 or 2
  Cam.x, Cam.y = TOWERS[1].x, TOWERS[1].y + 30
  Cam.z = math.max(0, groundAt(Cam.x, Cam.y))
  Clock.t = 0.62
  Music.play("title")
end

function Game.newGame()
  Player.new(POI.start.x, POI.start.y)
  Inv.reset()
  Inv.add("onigiri", 2)
  Inv.add("berries", 3)
  P.weapon = "bokken"
  P.spawnX, P.spawnY = POI.start.x, POI.start.y
  Quest.reset()
  Clock.t, Clock.day, Clock.total = 0.06, 1, 0
  MapUI.seen = {}
  Game.enterPlay()
  Quest.start("mq1", true)
  local q = QBYID.mq1
  Dialog.lines("Sensei Hayate", q.intro, function()
    UI.banner("The Way of the Shinobi", "Craft a torch: TAB opens the crafting menu")
  end, NPC.find("sensei"))
end

function Game.continue()
  if not Save.read() then Game.newGame() return end
  Game.enterPlay()
  UI.banner("Welcome back, Kage", "Day " .. Clock.day)
  NPC.spawnCat()
end

function Game.enterPlay()
  Game.state = "play"
  Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
  Cam.a, Cam.ta = math.pi / 4, math.pi / 4
  Game.region = nil
  NPC.spawnCat()
  Music.region()
end

function Game.toTitle()
  reset()
end

function Game.save() if P and Game.state == "play" then Save.write() end end
function Game.autosave()
  if P and Game.state == "play" and P.state ~= "dead" then
    Save.write()
    Game.savedT = 90
  end
end

function Game.onDeath(why)
  Game.state = "dead"
  Game.deadT = 0
  Game.deathWhy = why
end

function Game.finale()
  Game.state = "finale"
  Game.finT = 0
  Music.play("title")
end

function Game.safeToSleep()
  for _, e in ipairs(ENTS) do
    if e.alive and e.hostile and dist(e.x, e.y, P.x, P.y) < 100 then return false end
  end
  return true
end

-- sleep until morning (inn = full heal, bedroll = partial)
function Game.sleep(inn)
  Game.fade = 60
  Game.fadeDo = function()
    if Clock.t > 0.3 then Clock.day = Clock.day + 1 end
    Clock.t = 0.03
    P.stam = P.maxstam
    P.exhausted = false
    if inn then
      P.hp = P.maxhp
      P.spawnX, P.spawnY = P.x, P.y
    else
      Player.heal(P.maxhp // 2)
      P.hunger = math.max(0, P.hunger - 15)
    end
    for _, e in ipairs(ENTS) do if e.alive and e.kind == "enemy" and not e.camp then e.alive = false end end
    UI.banner("Day " .. Clock.day, inn and "You feel fully rested. Game saved." or "You slept rough...")
    Game.autosave()
    Music.region()
  end
end

function Game.travel(t)
  Game.fade = 50
  Game.fadeDo = function()
    P.x, P.y = t.x, t.y + 22
    P.z = groundAt(P.x, P.y)
    P.state = "ground"
    P.vx, P.vy, P.vz = 0, 0, 0
    Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
    for _, e in ipairs(ENTS) do
      if e.alive and e.kind == "enemy" and not e.camp and not e.boss then e.alive = false end
      if e.kind == "drop" or e.kind == "proj" then e.alive = false end
    end
    UI.toast("Travelled to " .. t.name)
  end
end

-- ---------------------------------------------------------------------------
-- per-frame helpers
-- ---------------------------------------------------------------------------
local function regionTick()
  if Frame % 20 ~= 0 then return end
  local p = P
  local cx, cy = clamp(flr(p.x / 8), 0, 239), clamp(flr(p.y / 8), 0, 111)
  local r = WR[cidx(cx, cy)]
  local safe = false
  for _, t in ipairs(TOWNS) do
    if dist(p.x, p.y, t.x, t.y) < t.r then safe = true Game.town = t.name end
  end
  if safe ~= Game.safe then
    Game.safe = safe
    if safe then UI.region(Game.town) end
    Music.region()
  end
  if r ~= Game.region then
    Game.region = r
    if not safe then UI.region(REG[r].name) end
    Music.region()
  end
  MapUI.reveal(p.x, p.y, 7)
  -- night music swap
  local night = Clock.isNight()
  if night ~= Game.wasNight then
    Game.wasNight = night
    Music.region()
  end
end

local function lightTick()
  local p = P
  if p.light and ITEM[p.light] and ITEM[p.light].fuel < 99999 and not Clock.isDay() then
    p.lightFuel = (p.lightFuel or 0) - 1
    if p.lightFuel <= 0 then
      UI.toast("Your " .. ITEM[p.light].n .. " burned out!")
      p.light = nil
    end
  end
end

local function camera()
  local p = P
  local tx, ty = p.x, p.y
  Cam.x = Cam.x + (tx - Cam.x) * 0.14
  Cam.y = Cam.y + (ty - Cam.y) * 0.14
  local tz = p.z
  if p.state == "air" or p.state == "plunge" then tz = math.min(p.z, groundAt(p.x, p.y) + 20) end
  Cam.z = Cam.z + (tz - Cam.z) * 0.08
  local d = angdiff(Cam.a, Cam.ta)
  if math.abs(d) < 0.01 then Cam.a = Cam.ta else Cam.a = Cam.a + d * 0.16 end
  Cam.sx = (rnd() - 0.5) * FX.shakeA
  Cam.sy = (rnd() - 0.5) * FX.shakeA
end

function Game.darkness()
  local t = Clock.t
  if t < NIGHT - 0.05 or t > DAWN then return 0 end
  if t < NIGHT then return (t - (NIGHT - 0.05)) / 0.05 end
  if t > DAWN - 0.03 then return (DAWN - t) / 0.03 end
  return 1
end

-- static objects in visible chunks
local function drawObjects()
  local f = Frame
  for _, k in ipairs(Render.visChunks) do
    local l = OLIST[k]
    if l then
      for ci in pairs(l) do
        local o = WO[ci]
        if o > 0 then
          local d = OBJ[o]
          local name = d.spr or (d.anim and d.anim[1 + (f // 10 + ci) % #d.anim])
          local r = name and SPR[name]
          if r then
            local ox, oy = objPos(ci)
            local z = math.max(WH[ci], 0)
            if (WF[ci] & F_ROOF) ~= 0 then z = groundAt(ox, oy) end
            if d.bob then z = z + math.sin((f + ci) / 12) * 1.5 + 2 end
            if d.shadow then Render.ground(SPR.shadow, ox, oy, z + 0.3, d.shadow) end
            local flip = (ci % 2 == 0) and d.r == nil and d.hand ~= nil
            local ch = World.chop[ci]
            if ch then
              -- chopped: leans further with each hit, wobbles right after one
              local lean = 0.24 * (World.hits[ci] or 0) / ch.n
              if ch.t > 0 then lean = lean + math.sin(ch.t * 1.3) * ch.t * 0.008 end
              Render.billRot(r, ox, oy, z, flip, d.pm, 1, World.chopSide(ch) * lean, 1.5)
            else
              Render.bill(r, ox, oy, z, flip, d.pm)
            end
          end
        end
      end
    end
  end
  Render.setPM(nil)
end

local function weather()
  local reg = Game.region and REG[Game.region]
  local biome = reg and reg.biome
  local kind = nil
  if Clock.rain > 0.2 then kind = (biome == "snow") and "snow" or "rain" end
  if not kind and biome == "sakura" then kind = "petal" end
  if not kind and biome == "snow" then kind = "snow" end
  if not kind and Clock.isNight() and (biome == "plains" or biome == "marsh" or biome == "sakura") then kind = "firefly" end
  local want = 0
  if kind == "rain" then want = flr(70 * Clock.rain) elseif kind == "snow" then want = 45 elseif kind == "petal" then want = 14 elseif kind == "firefly" then want = 16 end
  while #WEATHER < want do
    WEATHER[#WEATHER + 1] = { x = rnd(0, 239), y = rnd(-10, 135), s = rndf(0.5, 1.5), k = kind, ph = rnd() * 6 }
  end
  while #WEATHER > want do table.remove(WEATHER) end
  for _, w in ipairs(WEATHER) do
    w.k = kind
    if kind == "rain" then
      w.x, w.y = w.x - 1.2, w.y + 5 * w.s
      line(w.x, w.y, w.x + 2, w.y - 5, C_GRAY)
    elseif kind == "snow" then
      w.x, w.y = w.x + math.sin(Frame / 30 + w.ph) * 0.4 - 0.2, w.y + 0.5 * w.s
      pix(w.x, w.y, C_WHITE)
    elseif kind == "petal" then
      w.x, w.y = w.x + math.sin(Frame / 25 + w.ph) * 0.6 + 0.3, w.y + 0.35 * w.s
      pix(w.x, w.y, C_PINK)
      pix(w.x + 1, w.y, C_WHITE)
    elseif kind == "firefly" then
      w.x, w.y = w.x + math.sin(Frame / 40 + w.ph) * 0.4, w.y + math.cos(Frame / 33 + w.ph) * 0.3
      if (Frame // 20 + flr(w.ph * 3)) % 3 ~= 0 then pix(w.x, w.y, C_GOLD) end
    end
    if w.y > 136 then w.y = rnd(-8, 0) w.x = rnd(0, 260) end
    if w.x < -4 then w.x = 243 elseif w.x > 244 then w.x = -3 end
    if w.y < -12 then w.y = 135 end
  end
end

-- the world frame (shared by title and play)
local function drawWorld(withPlayer)
  vbank(0)
  -- menus and the finale dim the world through its palette (bank 0 only)
  local r, g, b = Clock.tint()
  if Menu.cur or Game.state == "finale" then r, g, b = r * 0.38, g * 0.38, b * 0.45 end
  Pal.setTint(r, g, b)
  cls(C_NIGHT)
  Render.begin()
  Gfx.animTiles(Frame)
  Render.world()
  drawObjects()
  Shrine.drawOrbs()
  if P then Ent.drawAll(P.x, P.y) end
  FX.drawWorld()
  if withPlayer and P then Player.draw() end
  FX.drawTop()
  weather()
  Light.collect()
  local a = Game.darkness()
  if P and P.has.mirror then a = math.min(a, 0.7) end
  Light.overlay(a)
end

-- ---------------------------------------------------------------------------
-- title screen
-- ---------------------------------------------------------------------------
local function titleTick()
  Clock.t = 0.6 + math.sin(Frame / 600) * 0.02
  Cam.ta = Cam.ta + 0.004
  Cam.a = Cam.ta
  local t = TOWERS[1]
  Cam.x, Cam.y = t.x, t.y
  Cam.z = math.max(0, groundAt(t.x, t.y)) + 10
  drawWorld(false)
  vbank(1)
  cls(0)
  -- logo
  local y = 22
  print("KAGE", 120 - 50 + 2, y + 2, C_NIGHT, false, 4)
  print("KAGE", 120 - 50, y, C_RED, false, 4)
  print("KAGE", 120 - 50, y - 1, C_WHITE, false, 4)
  local sub = "Ninja of the Wind"
  local w = textw(sub)
  tprint(sub, 120 - w / 2, y + 26, C_GOLD)
  local opts = { "Continue", "New Game", "Controls" }
  local has = Save.exists()
  for i, o in ipairs(opts) do
    local yy = 76 + (i - 1) * 12
    local dim = (i == 1 and not has)
    local col = dim and C_GRAY or (i == Game.titleSel and C_GOLD or C_WHITE)
    local ow = textw(o)
    if i == Game.titleSel then
      rect(120 - ow / 2 - 6, yy - 2, ow + 12, 10, C_NIGHT)
      print(">", 120 - ow / 2 - 5, yy, C_RED)
    end
    tprint(o, 120 - ow / 2, yy, col)
  end
  local hint = "Z select   arrows move"
  local hw = textw(hint, true)
  rect(120 - hw // 2 - 5, 123, hw + 10, 10, C_NIGHT)
  print(hint, 120 - hw // 2, 125, C_GRAY, false, 1, true)
  if Game.help then
    panel(20, 14, 200, 110)
    local lines = { "Arrows  move          SHIFT/C  sprint", "X  jump (air: hold to glide, water: leap out)", "Z  katana, chop, mine (air: plunge)",
      "A  talk / pick up / open / cook", "S  throw shuriken    Q/E  rotate view", "Push into a wall to climb, X to leap",
      "TAB  bag + crafting   M  map   J  quests", "1-0  use hotbar slot", "", "Survive: eat, carry light at night,", "climb pagodas, recover the Treasures.", "", "Z  close" }
    for i, l in ipairs(lines) do print(l, 28, 20 + (i - 1) * 8, C_WHITE, false, 1, true) end
    if In.p.atk or In.p.jump or In.p.ok then Game.help = false Sfx.play("close") end
    return
  end
  if In.p.up then Game.titleSel = (Game.titleSel - 2) % 3 + 1 Sfx.play("menu") end
  if In.p.down then Game.titleSel = Game.titleSel % 3 + 1 Sfx.play("menu") end
  if In.p.atk or In.p.ok or In.p.use then
    Sfx.play("select")
    if Game.titleSel == 1 and has then Game.continue()
    elseif Game.titleSel == 2 then Game.newGame()
    elseif Game.titleSel == 3 then Game.help = true end
  end
end

-- ---------------------------------------------------------------------------
-- main frame
-- ---------------------------------------------------------------------------
function Game.tick()
  In.poll()
  Frame = Frame + 1
  Music.update()
  if Game.state == "title" then
    titleTick()
    return
  end
  local p = P
  -- input routing
  if Game.fade > 0 then
    Game.fade = Game.fade - 1
    if Game.fade == 30 and Game.fadeDo then Game.fadeDo() Game.fadeDo = nil end
  elseif Game.state == "dead" then
    Game.deadT = Game.deadT + 1
    if Game.deadT > 90 and (In.p.atk or In.p.ok or In.p.use) then
      local lost = flr(p.ryo / 4)
      p.ryo = p.ryo - lost
      Player.respawn()
      Game.state = "play"
      UI.toast(lost > 0 and ("You lost " .. lost .. " ryo") or "You awaken...")
      for _, e in ipairs(ENTS) do if e.alive and e.kind == "enemy" and not e.camp then e.alive = false end end
      Music.region()
    end
  elseif Game.state == "finale" then
    Game.finT = Game.finT + 1
    if Game.finT > 240 and (In.p.atk or In.p.ok) then Game.state = "play" Music.region() end
  elseif Dialog.active then
    Dialog.update()
  elseif Menu.cur then
    Menu.update()
  elseif In.p.menu then
    Menu.open("pause", { tab = 1 })
  elseif In.p.map then
    Menu.open("pause", { tab = 3 })
  elseif In.p.quest then
    Menu.open("pause", { tab = 4 })
  end
  local paused = Dialog.active or Menu.cur or Game.fade > 0 or Game.state == "finale"
  if not paused then
    if FX.stop > 0 then
      FX.stop = FX.stop - 1
    else
      Clock.update()
      Player.update()
      if p.webbed and p.webbed > 0 then
        p.webbed = p.webbed - 1
        p.vx, p.vy = p.vx * 0.5, p.vy * 0.5
      end
      Ent.updateAll(p.x, p.y)
      Enemy.director()
      Boss.update()
      Shrine.update()
      World.update()
      Clock.survival()
      lightTick()
      regionTick()
    end
    FX.update()
  end
  camera()
  drawWorld(true)
  -- overlay bank
  vbank(1)
  cls(0)
  if Game.state == "play" then
    if not Menu.cur then UI.drawHUD() end
    Menu.draw()
    Dialog.draw()
  elseif Game.state == "dead" then
    local a = math.min(1, Game.deadT / 60)
    for y = 0, 135, a > 0.5 and 1 or 2 do line(0, y, 239, y, C_NIGHT) end
    local s = "You have fallen"
    print(s, 120 - textw(s, false) * 1, 50, C_RED, false, 2)
    local why = ({ dark = "The Yami took you in the dark.", cold = "You froze on the mountain.", starve = "You starved.",
      fall = "A fatal fall.", drown = "You drowned.", lava = "Burned by lava." })[Game.deathWhy] or "Defeated in battle."
    tprint(why, 120 - textw(why) / 2, 70, C_WHITE)
    if Game.deadT > 90 then tprint("Z: rise again", 120 - textw("Z: rise again") / 2, 90, C_GOLD) end
  elseif Game.state == "finale" then
    local lines = { "Shuten-doji is defeated.", "", "The Three Sacred Treasures shine", "once more over the realm,",
      "and dawn returns to the land.", "", "Thank you for playing KAGE!", "", "The world remains yours to roam." }
    for i, l in ipairs(lines) do
      local yy = 20 + (i - 1) * 10
      if Game.finT > i * 20 then tprint(l, 120 - textw(l) / 2, yy, i == 7 and C_GOLD or C_WHITE) end
    end
    if Game.finT > 240 then tprint("Z: continue", 120 - textw("Z: continue") / 2, 118, C_GRAY) end
  end
  if Game.savedT and Game.savedT > 0 then
    Game.savedT = Game.savedT - 1
    tprint("Saved", 204, 116, C_LIME, true)
  end
  -- fade
  if Game.fade > 0 then
    local f = Game.fade > 30 and (60 - Game.fade) or Game.fade
    local step = f > 22 and 1 or (f > 12 and 2 or 4)
    for y = 0, 135, step do line(0, y, 239, y, C_NIGHT) end
  end
  vbank(0)
end

-- ============================================================================
--  shot_itch: stages the itch.io store screenshots and the cover-art layers on
--  the real game loop. A coroutine yields once per frame (like t_quests).
--    itch_*  store screenshots, HUD included
--    art_*   cover, banner and page background layers: frozen world tiles
--            stitched into panoramas (HUD and ninja hidden), the logo and
--            sprites drawn on vbank 1
--  tools/itch_art.py turns build/shot_itch.log into the itch/ images.
-- ============================================================================
-- wrapped in a function: the game chunk is close to Lua's 200-local limit
;(function()
  math.randomseed(7)
  local co
  local clean = false   -- clear vbank 1 after the frame (no HUD)
  local freeze = false  -- pause the simulation and pin Frame (stitched tiles)
  local hideP = false   -- skip drawing the ninja
  local hush = false    -- clear toasts, banners and region titles every frame
  local pinF = 0
  local keepHP = nil
  local realDraw = Player.draw
  local function noDraw() end

  -- Ent.updateAll compacts ENTS but keeps entities spawned during the pass
  -- past the cut, leaving nil gaps that crash Ent.drawAll. Close them here
  -- (and log it) so the staged fights can run.
  local realUpdateAll = Ent.updateAll
  Ent.updateAll = function(px, py)
    realUpdateAll(px, py)
    local last = 0
    for k in pairs(ENTS) do if k > last then last = k end end
    local live = {}
    for i = 1, last do if ENTS[i] then live[#live + 1] = ENTS[i] end end
    if #live < last then
      Test.log(string.format("ENTS gap closed at frame %d: %d entities over %d slots", Frame, #live, last))
      for i = 1, last do ENTS[i] = live[i] end
    end
  end

  local function tick(n)
    for _ = 1, n or 1 do coroutine.yield() end
  end

  local function hold(t, n)
    for _ = 1, n or 1 do
      In.fake = t
      tick()
    end
  end

  local function cell(cx, cy) return cx * 8 + 4, cy * 8 + 4 end

  local function warp(x, y, z)
    P.x, P.y = x, y
    P.z = z or groundAt(x, y)
    P.state = "ground"
    P.vx, P.vy, P.vz = 0, 0, 0
    Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
  end

  local function quiet()
    UI.toasts, UI.bannerT, UI.regionT = {}, 0, 0
    Game.savedT = 0
  end

  -- render one more frame with the given input and save it
  local function snap(tag, input)
    quiet()
    In.fake = input or {}
    tick()
    Test.dump("itch_" .. tag)
  end

  local function cleanup()
    for _, e in ipairs(ENTS) do
      if e.kind ~= "npc" then e.alive = false end
    end
    Boss.cur = nil
    Shrine.trial = nil
    Dialog.active = false
    if Menu.cur then Menu.close() end
    FX.parts, FX.texts, FX.sprites = {}, {}, {}
    FX.shakeA, FX.stop = 0, 0
    P.state, P.glide, P.atk, P.combo = "ground", false, 0, 0
    P.vx, P.vy, P.vz, P.webbed = 0, 0, 0, 0
    P.light = nil
    P.stam, P.exhausted = P.maxstam, false
    Cam.a, Cam.ta = math.pi / 4, math.pi / 4
    Game.state = "play"
  end

  -- arrows that walk the ninja towards a world point (camera relative)
  local function toward(x, y, near)
    local dx, dy = x - P.x, y - P.y
    local ca, sa = math.cos(Cam.a), math.sin(Cam.a)
    local sx = dx * ca + dy * sa
    local su = dx * sa - dy * ca
    local d = math.sqrt(dx * dx + dy * dy)
    if d < (near or 20) then return {}, d end
    local m = math.max(math.abs(sx), math.abs(su))
    return { right = sx > m * 0.4, left = sx < -m * 0.4, up = su > m * 0.4, down = su < -m * 0.4 }, d
  end

  -- a mid-game ninja: 6 hearts, katana, a bag of supplies, the kite
  local function midgame()
    P.maxhp, P.hp = 24, 21
    keepHP = 21
    P.ryo, P.hunger = 186, 71
    P.has.kite = true
    P.weapon = "katana"
    Inv.reset()
    Inv.size = 12
    for _, it in ipairs({ { "katana", 1 }, { "onigiri", 4 }, { "dango", 3 }, { "torch", 2 }, { "shuriken", 24 },
      { "campfire", 2 }, { "wood", 9 }, { "bamboo", 12 }, { "flint", 5 }, { "grass", 14 } }) do
      Inv.add(it[1], it[2])
    end
    QS.mq1 = { st = "done", step = 3, count = 0 }
    QS.mq2 = { st = "active", step = 1, count = 0 }
    Quest.tracked = "mq2"
  end

  local function bossQuests(id)
    QS.mq2 = { st = "done", step = 1, count = 0 }
    for _, q in ipairs({ "jewel", "mirror", "sword" }) do QS[q] = QS[q] or { st = "active", step = 1, count = 0 } end
    local track = { tengulord = "mirror", shuten = "mq4" }
    if id == "shuten" then
      for _, q in ipairs({ "jewel", "mirror", "sword" }) do QS[q].st = "done" end
      QS.mq4 = { st = "active", step = 2, count = 0 }
      P.weapon = "kusanagi"
      P.has.djump, P.has.mirror = true, true
    end
    Quest.tracked = track[id]
  end

  -- a whole scene rendered as cols x rows frozen tiles (camera on the ninja)
  local function stitch(tag, cols, rows)
    local W, H = cols * 240, rows * 136
    freeze, clean, hideP = true, true, true
    pinF = Frame
    Cam.x, Cam.y, Cam.z = P.x, P.y, P.z
    for r = 0, rows - 1 do
      for c = 0, cols - 1 do
        Cam.SCX, Cam.SCY = W // 2 - c * 240, H // 2 - r * 136
        tick()
        Test.dump(string.format("art_%s_%d_%d", tag, r, c))
      end
    end
    Cam.SCX, Cam.SCY = 120, 76
    freeze, clean, hideP = false, false, false
    Game.fade = 0
    tick()
  end

  -- the world around cell (cx, cy) at time of day t, as cols x rows tiles
  local function pano(tag, t, cx, cy, cols, rows)
    Clock.t = t
    warp(cell(cx, cy))
    hold({}, 30)
    stitch(tag, cols, rows)
  end

  -- a flat clearing ringed by trees near (cx, cy)
  local TREES = { [O_TREE] = true, [O_SAKURA] = true, [O_MAPLE] = true, [O_PINE] = true, [O_SNOWPINE] = true,
    [O_WILLOW] = true, [O_DEAD] = true, [O_BAMBOO] = true }
  local function forestSpot(cx, cy, R)
    local best, bx, by = -1e9, cx, cy
    for yy = cy - R, cy + R do
      for xx = cx - R, cx + R do
        if inmap(xx - 5, yy - 5) and inmap(xx + 5, yy + 5) then
          local h = WH[cidx(xx, yy)]
          local ok = h >= 0
          for dy = -2, 2 do
            for dx = -2, 2 do
              local i = cidx(xx + dx, yy + dy)
              if WH[i] ~= h or (WF[i] & (F_WATER | F_ROOF | F_MODEL | F_TOWN | F_ROAD)) ~= 0 then ok = false end
              if math.abs(dx) <= 1 and math.abs(dy) <= 1 and WO[i] ~= 0 then ok = false end
            end
          end
          if ok then
            local n = 0
            for dy = -5, 5 do
              for dx = -5, 5 do
                if math.max(math.abs(dx), math.abs(dy)) >= 3 and TREES[WO[cidx(xx + dx, yy + dy)]] then n = n + 1 end
              end
            end
            local score = n * 100 - ((xx - cx) ^ 2 + (yy - cy) ^ 2)
            if score > best then best, bx, by = score, xx, yy end
          end
        end
      end
    end
    return bx * 8 + 4, by * 8 + 4
  end

  -- ---------------------------------------------------------------------------
  -- scenes
  -- ---------------------------------------------------------------------------
  local function village()
    cleanup()
    Clock.t = 0.2
    warp(cell(62, 84))
    hold({}, 40)
    hold({ right = true }, 14)
    hold({ down = true }, 10)
    snap("village", { down = true })
  end

  local function night()
    QS.spirits = QS.spirits or { st = "active", step = 1, count = 2 }
    cleanup()
    Clock.t = 0.8
    local x, y = forestSpot(70, 96, 14)
    warp(x, y)
    Quest.tracked = "spirits"
    P.light, P.lightFuel = "torch", 4800
    local fire = cidx(flr(x / 8) + 1, flr(y / 8) + 1)
    World.setObj(fire, O_FIRE)
    hush = true
    hold({}, 30)
    Enemy.spawn("onibi", x - 46, y - 24)
    Enemy.spawn("onibi", x + 52, y + 6)
    local yurei = Enemy.spawn("yurei", x - 26, y + 34)
    for f = 1, 36 do
      P.dir = math.atan(yurei.y - P.y, yurei.x - P.x)
      tick()
      if f % 6 == 0 then Test.dump(string.format("itch_night_%02d", f)) end
    end
    hush = false
    World.setObj(fire, 0)
    Quest.tracked = "mq2"
  end

  local function glide()
    cleanup()
    Clock.t = 0.27
    local x, y = cell(166, 78)
    local g = math.max(0, groundAt(x, y))
    warp(x, y, g + 48)
    P.state, P.vz = "air", -0.5
    Cam.z = g + 20
    hush = true
    for f = 1, 36 do
      In.fake = { jump = true, up = true }
      tick()
      if f % 6 == 0 then Test.dump(string.format("itch_glide_%02d", f)) end
    end
    hush = false
  end

  local function climb()
    cleanup()
    Clock.t = 0.33
    local t = TOWERS[2]
    warp(t.x - 18, t.y + 18)
    hush = true
    local n = 0
    for f = 1, 120 do
      In.fake = { up = true }
      tick()
      if P.state == "climb" and f % 12 == 0 and n < 4 then
        n = n + 1
        Test.dump(string.format("itch_climb_%03d", f))
      end
    end
    hush = false
  end

  -- boss attack frames worth a screenshot: state -> ticks into it
  local BOSSPOS = { tengulord = "summit", shuten = "onigashima" }
  local MOMENTS = {
    tengulord = { volley = { 18, 40 }, dive = { 8 }, summon = { 32 } },
    shuten = { fire = { 28, 36 }, charge = { 12 }, summon = { 32 } },
  }

  local function bossFight(id)
    cleanup()
    bossQuests(id)
    Clock.t = 0.3
    local a = POI[BOSSPOS[id]]
    local bx, by = a.x, a.y + 30
    local cx, cy = flr(bx / 8), flr(by / 8)
    local best = 1e9
    for yy = cy - 6, cy + 6 do
      for xx = cx - 6, cx + 6 do
        local i = cidx(xx, yy)
        if inmap(xx, yy) and WH[i] >= 0 and (WF[i] & F_WATER) == 0 then
          local d = (xx - cx) ^ 2 + (yy - cy) ^ 2
          if d < best then best, bx, by = d, xx * 8 + 4, yy * 8 + 4 end
        end
      end
    end
    if id == "tengulord" then P.armor = "cloak" end
    warp(bx, by)
    hush = true
    local b
    for _ = 1, 120 do
      tick()
      b = Boss.cur
      if b and b.def.id == id then break end
    end
    if not (b and b.def.id == id) then
      Test.log("FAIL " .. id .. " did not spawn")
      return
    end
    b.hp = flr(b.maxhp * 0.6)
    -- the Oni King only throws fire rings at a distance
    local near = ({ tengulord = 26, shuten = 46 })[id]
    local seen = {}
    local shots = 0
    for f = 1, 1100 do
      local input = {}
      if b.alive and not b.hidden then
        local mv, d = toward(b.x, b.y, near)
        input = mv
        if id == "shuten" and d < near - 10 then input = toward(2 * P.x - b.x, 2 * P.y - b.y, 0) end
        if d < 30 then input.atk = (f % 40 == 0) end
      end
      if b.hp < b.maxhp * 0.4 then b.hp = flr(b.maxhp * 0.4) end
      In.fake = input
      tick()
      local m = MOMENTS[id][b.state]
      if m and f > 60 and b.flash == 0 and P.flash == 0 and FX.shakeA < 2 then
        for _, st in ipairs(m) do
          local key = b.state .. st
          if b.st == st and (seen[key] or 0) < 2 and shots < 14 then
            seen[key] = (seen[key] or 0) + 1
            shots = shots + 1
            Test.dump(string.format("itch_%s_%s_%04d", id, key, f))
          end
        end
      end
    end
    hush = false
    P.armor = nil
    Test.log(string.format("%s: %d moments", id, shots))
  end

  local function haunted()
    cleanup()
    Clock.t = 0.66
    warp(cell(36, 20))
    hold({}, 40)
    Enemy.spawn("kitsune", P.x + 30, P.y - 20)
    hold({ up = true }, 12)
    snap("haunted", { up = true })
  end

  local function menus()
    cleanup()
    Clock.t = 0.3
    warp(cell(62, 84))
    for _, it in ipairs({ { "paper", 4 }, { "rope", 3 }, { "iron", 2 } }) do Inv.add(it[1], it[2]) end
    hold({}, 20)
    Menu.open("pause", { tab = 2 })
    Menu.ctab, Menu.sel = 2, 1
    snap("craft")
    Menu.close()
    for _, t in ipairs(TOWERS) do MapUI.reveal(t.x, t.y, 70) end
    for _, t in ipairs(TOWNS) do MapUI.reveal(t.x, t.y, 50) end
    Quest.towersOn[1], Quest.towersOn[2], Quest.towersOn[4] = true, true, true
    Menu.open("pause", { tab = 3 })
    snap("map")
    Menu.close()
    tick(2)
  end

  -- cover art: stitched world panoramas without HUD or ninja, then the logo
  -- glyphs and hero sprites on vbank 1 over an empty bank 0
  local function art()
    cleanup()
    Cam.a, Cam.ta = math.pi / 4, math.pi / 4
    pano("hanamura", 0.62, 69, 80, 2, 3)
    -- the title at 8x (itch_art.py reads it back at 1x) and the subtitle
    vbank(0) cls(C_INK)
    vbank(1) cls(0)
    print("KAGE", 8, 8, C_WHITE, false, 8)
    print("Ninja of the Wind", 8, 100, C_WHITE, false, 1)
    Test.dump("art_text")
    vbank(1) cls(0)
    local r = SPR.n_glide
    blit(r, 2, 2)
    Test.log(string.format("SPRITE n_glide 2 2 %d %d", r[3], r[4]))
    Test.dump("art_sprites")
    vbank(0)
  end

  local function script()
    Game.newGame()
    while Dialog.active do
      hold({ atk = true })
      hold({})
    end
    hold({}, 10)
    midgame()
    art()
    village()
    night()
    glide()
    climb()
    bossFight("tengulord")
    bossFight("shuten")
    midgame()
    haunted()
    menus()
    -- page banner (Kyo and the Fuyu foothills) and page background (Sakura Vale)
    cleanup()
    pano("kyo", 0.62, 116, 54, 3, 2)
    pano("vale", 0.62, 66, 86, 3, 3)
  end

  co = coroutine.create(script)

  function TIC()
    In.fake = {}
    if coroutine.status(co) == "dead" then Test.finish() return end
    local ok, err = coroutine.resume(co)
    if not ok then
      Test.log("FAIL script error: " .. tostring(err))
      Test.finish()
      return
    end
    if P then
      Game.cutscene = true
      P.iframes = 0
      if keepHP then P.hp = keepHP end
      P.hunger = math.max(P.hunger, 60)
    end
    Clock.raining, Clock.rain, Clock.rainT = false, 0, 1e9
    if hush then
      UI.toasts, UI.bannerT, UI.regionT = {}, 0, 0
      Game.savedT = 0
    end
    if freeze then
      Game.fade = 999
      Frame = pinF
      FX.shakeA = 0
    end
    Player.draw = hideP and noDraw or realDraw
    Game.tick()
    if clean then vbank(1) cls(0) vbank(0) end
  end
end)()

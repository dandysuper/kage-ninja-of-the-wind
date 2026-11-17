-- ============================================================================
--  06 ART: WORLD - trees, rocks, plants, props, effects, decals.
--  Organic shapes are painted procedurally (lit from the upper left);
--  props are hand-drawn rows.
-- ============================================================================
local H = hash2

-- blobby canopy painter: circles {x,y,r}; ramp {light, mid, dark, outline}
local function canopy(w, h, circles, ramp, trunk, seed)
  return function(x, y)
    local inside, best, bd = false, nil, 1e9
    for i = 1, #circles do
      local c = circles[i]
      local dx, dy = x + 0.5 - c[1], y + 0.5 - c[2]
      local d = (dx * dx + dy * dy) / (c[3] * c[3])
      if d <= 1 then
        inside = true
        -- prefer the circle drawn "in front" (later, lower)
        best = c
        bd = d
      end
    end
    if inside then
      local dx, dy = (x + 0.5 - best[1]) / best[3], (y + 0.5 - best[2]) / best[3]
      local l = -(dx * 0.7 + dy * 0.9) + (H(x, y, seed) - 0.5) * 0.5
      if bd > 0.82 and (dx + dy) > 0.2 then return ramp[4] end
      if l > 0.45 then return ramp[1] end
      if l > -0.25 then return ramp[2] end
      return ramp[3]
    end
    if trunk then return trunk(x, y) end
    return 0
  end
end

local function trunkFn(x0, x1, y0, y1)
  return function(x, y)
    if y >= y0 and y <= y1 and x >= x0 and x <= x1 then
      if x == x0 then return C_WOOD end
      if x == x1 then return C_NIGHT end
      if (x + y) % 5 == 0 then return C_NIGHT end
      return C_BROWN
    end
    -- roots
    if y == y1 and (x == x0 - 1 or x == x1 + 1) then return C_BROWN end
    return 0
  end
end

local function pine(w, h, snow)
  return function(x, y)
    local cx = w / 2
    -- trunk
    if y >= h - 5 and math.abs(x + 0.5 - cx) < 1.6 then return (x + 0.5 < cx) and C_WOOD or C_BROWN end
    -- 4 tiers of triangles
    for t = 0, 3 do
      local top = 1 + t * 6
      local bot = top + 9
      if y >= top and y <= bot then
        local half = 1 + (y - top) * (0.55 + t * 0.12)
        local dx = x + 0.5 - cx
        if math.abs(dx) <= half then
          if snow and (y - top) <= 1 + (H(x, t, 5) < 0.5 and 1 or 0) then return C_WHITE end
          if y == bot or math.abs(dx) > half - 1 and dx > 0 then return C_NIGHT end
          if dx < -half * 0.3 then return snow and C_WHITE or C_GREEN end
          if H(x, y, 9) < 0.15 then return C_GREEN end
          return C_DKGRN
        end
      end
    end
    return 0
  end
end

local function rockFn(w, h, ore)
  local cx, cy = w / 2, h * 0.6
  return function(x, y)
    local dx, dy = (x + 0.5 - cx) / (w / 2), (y + 0.5 - cy) / (h * 0.62)
    if dy > 0.62 then return 0 end
    local d = dx * dx + dy * dy + (H(x, y, 3) - 0.5) * 0.12
    if d > 1 then return 0 end
    if d > 0.78 and (dx + dy) > -0.1 then return C_NIGHT end
    local l = -(dx * 0.6 + dy) + (H(x, y, 4) - 0.5) * 0.4
    if ore and H(x, y, 7) < 0.12 and d < 0.7 then return (H(x, y, 8) < 0.5) and C_GOLD or C_BLUE end
    if l > 0.55 then return C_WHITE end
    if l > -0.2 then return C_GRAY end
    return C_INDIGO
  end
end

local function bushFn(w, h, berries)
  return canopy(w, h, { { w * 0.3, h * 0.6, h * 0.5 }, { w * 0.7, h * 0.6, h * 0.5 }, { w * 0.5, h * 0.45, h * 0.55 } },
    { C_LIME, C_GREEN, C_DKGRN, C_NIGHT }, nil, 21), berries
end

function Art.world()
  local add, addfn = Gfx.add, Gfx.addfn
  -- trees ------------------------------------------------------------------
  addfn("tree", 24, 30, canopy(24, 30, {
    { 7, 12, 6.5 }, { 17, 11, 6.5 }, { 12, 7, 7 }, { 8, 17, 6 }, { 16, 17, 6.5 }, { 12, 14, 7 },
  }, { C_LIME, C_GREEN, C_DKGRN, C_NIGHT }, trunkFn(10, 13, 18, 29), 11))
  addfn("pine", 16, 32, pine(16, 32, false))
  addfn("willow", 22, 28, function(x, y)
    local c = canopy(22, 28, { { 6, 9, 6 }, { 15, 8, 6.5 }, { 11, 6, 6 }, { 11, 11, 7 } },
      { C_LIME, C_GREEN, C_DKGRN, C_NIGHT }, trunkFn(10, 12, 14, 27), 31)(x, y)
    if c ~= 0 then return c end
    -- drooping strands
    if y > 10 and y < 24 and x % 3 == 1 and H(x, 0, 32) < 0.8 and y < 14 + H(x, 1, 33) * 10 then
      return (y % 2 == 0) and C_GREEN or C_LIME
    end
    return 0
  end)
  add("deadtree", [[
.......1.....1..
......181...18..
...1..181..181..
..181.1881181...
...1881888881...
.....188881.....
..11.18881......
.18818881.......
..11888881......
.....18881......
......1881......
......18881.....
......18891.....
......18891.....
......18891.....
......18891.....
.....188891.....
.....1888891....
....118888911...
....1.1111.1....
]])
  add("bamboo", [[
......7..7..7.
.7...77.776.77
.77.767.67.677
..7.6...6..76.
....76..76..7.
....76..76..76
....76..76..76
....56..56..76
....76..76..56
....76..76..76
....76..76..76
....76..56..76
....56..76..76
....76..76..76
....76..76..56
....76..76..76
....76..76..76
....76..56..76
....76..76..76
....56..76..76
....76..76..56
....76..76..76
....76..76..76
....76..76..76
....76..56..76
....56..76..76
....76..76..76
....76..76..76
....76..76..76
...1561156115611
]])
  -- the bamboo stalks: use lime/green; fix blue placeholder via remap at draw
  -- rocks --------------------------------------------------------------------
  addfn("rock", 10, 7, rockFn(10, 9, false))
  addfn("boulder", 16, 13, rockFn(16, 16, false))
  addfn("ore", 16, 13, rockFn(16, 16, true))
  -- plants -------------------------------------------------------------------
  add("grass", [[
.7....7.
.67..76.
..6.76..
.56.65.7
.5665576
55666655
]])
  add("grasscut", [[
.5.6.5..
55665565
]])
  add("flower", [[
.e.e...
eefee..
.e6e...
..6..d.
..6.dfd
..66.6.
...66..
]])
  add("bush", [[
.....1111.....
...11677611...
..1677766761..
.167766667761.
.16676d6667d61
1666d6f66666d1
1d6666666d66651
15666d66666651.
.155666666551..
..1111111111...
]])
  add("bush_empty", [[
.....1111.....
...11677611...
..1677766761..
.167766667761.
.1667666667661
16666666666661
1566666666665.
15566666666551.
.155666666551..
..1111111111...
]])
  add("mushroom", [[
..1111..
.1dcdd1.
1dddcdd1
1cddddc1
.11bb11.
...bb...
..1bb1..
]])
  add("reeds", [[
.8....8.
.8..8.8.
.6..8.6.
.6..6.6.
.66.6.6.
..6.6.66
..6.66.6
..66.6.6
.5.6.6.6
.5.6.65.
..56.55.
..5655..
.55655..
555555..
]])
  add("herb", [[
..7.7..
.776.7.
..676..
.76.67.
..565..
...5...
]])
  add("rice", [[
..f.f..
.f.f.f.
..f7f..
.7.6.7.
..767..
...6...
..565..
.5.5.5.
]])
  add("stump", [[
..11111...
.1aaaa91..
.19aa991..
.1888881..
1188888911
.11...111.
]])
  add("bamboostump", [[
.1..1...
.7117.1.
.76.76.7
.76.76.3
.56.56.5
]])
  -- props --------------------------------------------------------------------
  add("toro", [[
...111...
..14441..
.1444441.
.1111111.
...1c1...
..14f41..
..1fff1..
..14441..
...141...
...141...
...141...
..14441..
.1444441.
.1111111.
]])
  add("jizo", [[
..1111..
.1cccc1.
.1c1c11.
.1cccc1.
.1dddd1.
.1dddd1.
.1cccc1.
1cccccc1
1cc44cc1
14444441
.111111.
]])
  add("grave", [[
..1111..
.144441.
.14c441.
.144c41.
.144441.
.14c441.
.144441.
.144441.
1144441.
14444441
11111111
]])
  add("fence", [[
.1..1..1..1.
1a11a11a11a1
1a19a19a19a1
1aaaaaaaaaa1
1a91a91a91a1
1a11a11a11a1
1aaaaaaaaaa1
1a91a91a91a1
1a11a11a11a1
.1..1..1..1.
]])
  add("crate", [[
1111111111
1a9999999a
19aa999aa1
199aa9aa91
1999aa9991
199aa9aa91
19aa999aa1
1a9999999a
1111111111
]])
  add("barrel", [[
.111111.
19a99a91
1888888a
19a99a91
19a99a91
1888888a
19a99a91
.111111.
]])
  add("sign", [[
1111111111
1aaaaaaaa1
1a888888a1
1aaaaaaaa1
1a8888a8a1
1aaaaaaaa1
1111991111
....99....
....98....
....98....
....98....
...1981...
]])
  add("banner", [[
1111..
1dd1..
1dc1..
1dd1..
1cd1..
1dd1..
1dd1..
1cc1..
1dd1..
1d11..
11....
91....
91....
91....
91....
91....
91....
91....
91....
91....
91....
191...
]])
  add("chest", [[
.1111111111.
1f988888891f
19888f888891
1111111f1111
1988818f8891
19888818f891
198888888891
1f888888888f
111111111111
]])
  add("chest_open", [[
.1111111111.
1f911111191f
19111111191.
1f988888891f
1111111111111
1988818f8891
19888818f891
198888888891
1f888888888f
111111111111
]])
  add("kodama1", [[
..111..
.1ccc1.
1cc1c11
1ccccc1
.1ccc1.
.1c1c1.
..1.1..
]])
  add("kodama2", [[
..111..
.1ccc1.
11c1cc1
1ccccc1
.1ccc1.
1c1.1c1
.1...1.
]])
  add("hokora", [[
.....1111.....
...11dddd11...
.11dddddddd11.
1dddddddddddd1
11111111111111
..1b8bbbb8b1..
..1b8b11b8b1..
..1b8b11b8b1..
..1b8bbbb8b1..
..1888888881..
..1a99999981..
.1144444444411
.1444444444441
.1111111111111
]])
  add("well", [[
..1111111111..
.1888888888881
..1.......1...
..1.......1...
..1...1...1...
..1..1b1..1...
.1144444444411
14444c4444c441
1444444444444.
13333333333331
14444444444441
.111111111111.
]])
  add("fire1", [[
.....d......
....dfd.....
...dffd.d...
...dfcfdfd..
..dffcffd...
..dfccffd...
.19dffd891..
1989aa9898.1
.1188889811.
..1111111...
]])
  add("fire2", [[
......d.....
...d.dfd....
...dfffd....
..dfcffdd...
..dffcfffd..
..dfcccfd...
.19dffd891..
1989aa9898.1
.1188889811.
..1111111...
]])
  add("logs", [[
............
............
............
............
............
............
.19889.891..
1989aa9898.1
.1188889811.
..1111111...
]])
  add("pot", [[
..1111111.
.144444441
1442222244
14422222441
1444444444
.1444444441
..11111111
.1.....1..
]])
  add("chochin", [[
..1...
.141..
1dddd1
1dfdd1
1dddd1
1dfdd1
1dddd1
.1111.
..91..
..91..
..91..
..91..
..91..
..91..
.1981.
]])
  add("web", [[
c.....c.....c...
.c....c....c....
..c...c...c.....
...cccccccc.....
...c..c...c.....
cccc..c...cccccc
...c..c...c.....
...cccccccc.....
..c...c...c.....
.c....c....c....
c.....c.....c...
]])
  add("bones", [[
.c...cc...
cbc.c..c..
.cbcbbc.c.
..cbbcbc..
.11111111.
]])
  add("statue", [[
....1111....
...1cccc1...
...1c1c11...
...1cccc1...
....1cc1....
..11cccc11..
.1ccccccccf1
.1cfcccccff1
.1cc4cc4cc1.
.1cc4cc4cc1.
..1c4cc4c1..
..1cccccc1..
..1c4444c1..
..1cccccc1..
.11cccccc11.
1444444444441
144c4444c4441
.11111111111.
]])
  -- fx -----------------------------------------------------------------------
  add("slash", [[
.........cc.....
.......ccbc.....
.....cbbb.......
...cbbb.........
..cbb...........
.cbb............
.cb.............
cbb.............
cb..............
cb..............
.c..............
]])
  add("spark", [[
...c...
.c.c.c.
..cfc..
ccfcfcc
..cfc..
.c.c.c.
...c...
]])
  add("puff", [[
..11..
.1cc1.
1cbbc1
1cbbc1
.1cc1.
..11..
]])
  add("shadow", [[
..111111..
.11111111.
1111111111
1111111111
1111111111
1111111111
1111111111
1111111111
.11111111.
..111111..
]])
  add("shuriken", [[
...1...
..141..
.1441c.
1441441
.c1441.
..141..
...1...
]])
  add("arrow", [[
1........
.1444444f
1........
]])
  add("feather", [[
..11.
.1221
12221
1221.
.11..
]])
  add("fireball", [[
..dd..
.dffd.
dffcfd
dfccfd
.dffd.
..dd..
]])
  add("exclaim", [[
.111.
1fff1
1fff1
.1f1.
.1f1.
..1..
.1f1.
..1..
]])
  add("question", [[
.1111.
1fccf1
.1.1f1
..1f1.
..1f1.
...1..
..1f1.
...1..
]])
  add("zzz", [[
1111.
..1..
.1...
1111.
]])
  add("ripple", [[
..cccc..
cc....cc
..cccc..
]])
  add("petal", [[
ec
.e
]])
  add("orb", [[
..111..
.13331.
13ccc31
13c3c31
13ccc31
.13331.
..111..
]])
  -- decals (on walls) -----------------------------------------------------------
  add("door", [[
1111111111
18a8a8a8a1
1a8a8a8a81
18a8a8a8a1
1a8a8a8a81
18a8a8a8a1
1a8a8a8a81
18a8a8a8a1
1a8a8a8a81
18a8a8a8a1
1a8a8a8a81
1111111111
]])
  add("noren", [[
1111111111111111
1222222222222221
1222c222222c2221
122ccc2222ccc221
1222c222222c2221
1222222222222221
1222.222222.2221
1222.222222.2221
.22...2222...22.
]])
  add("dojo_sign", [[
1111111111111111
1aaaaaaaaaaaaaa1
1a1a11a1aa1a11a1
1a11a1a1a11aa1a1
1a1a11a1aa1a11a1
1aaaaaaaaaaaaaa1
1111111111111111
]])
  add("cave", [[
....1111111111....
..11111111111111..
.1111111111111111.
111111111111111111
111111111111111111
111111111111111111
111111111111111111
111111111111111111
111111111111111111
111111111111111111
]])
end

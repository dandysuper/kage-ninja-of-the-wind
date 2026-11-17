-- ============================================================================
--  07 - WORLD GENERATION
--
--  Builds the whole 240x136 tile world into the TIC-80 map at boot.
--
--  Vertical plan
--     y   0..32   high sky      (the tallest sky islands, clouds)
--     y  32..54   sky island band
--     y  54..80   surface       (rolling ground, 26 tiles of relief)
--     y  80..106  upper caves
--     y 106..136  the deep underworld (lava, dark rock)
--
--  Horizontal plan: 8 regions of 30 columns, in order of intended progress.
--
--  Terrain blocks are autotiled: after the mass is laid down, every solid tile
--  picks one of its 8 variants from which neighbours are exposed, which is what
--  produces the extruded-cube 2.5D look.
-- ============================================================================

local World = {
    surfY = {},        -- surface height per column, in tiles
    regOf = {},        -- region index per column
    decor = {},        -- background props drawn behind the play plane
    spawns = {},       -- enemy / pickup / chest spawn records
    startX = 6, startY = 60,
    w = MAP_W, h = MAP_H,
}

-- ---- regions ---------------------------------------------------------------
local REGIONS = {
    { name = "Bamboo Village", biome = BIOME.GRASS,  baseY = 64, amp = 3,
      tint = "none", fill = 8,  caves = 2, sky = 0 },
    { name = "Whispering Bamboo", biome = BIOME.BAMBOO, baseY = 62, amp = 7,
      tint = "none", fill = 10, caves = 4, sky = 1 },
    { name = "Sakura Hills", biome = BIOME.SAKURA, baseY = 66, amp = 6,
      tint = "dusk", fill = 9,  caves = 3, sky = 2 },
    { name = "Stone Pass", biome = BIOME.STONE, baseY = 58, amp = 9,
      tint = "none", fill = 12, caves = 4, sky = 2 },
    { name = "Yuki Mountain", biome = BIOME.SNOW, baseY = 54, amp = 10,
      tint = "cold", fill = 12, caves = 4, sky = 3 },
    { name = "Oni Caldera", biome = BIOME.VOLCANO, baseY = 70, amp = 8,
      tint = "ash", fill = 14, caves = 5, sky = 1 },
    { name = "Spirit Marsh", biome = BIOME.SWAMP, baseY = 68, amp = 4,
      tint = "night", fill = 10, caves = 3, sky = 1 },
    { name = "Temple Ruins", biome = BIOME.STONE, baseY = 60, amp = 7,
      tint = "dusk", fill = 12, caves = 4, sky = 2 },
}

-- Export the canonical list without copying it; HUD and camera share this table.
World.regions = REGIONS

local REGION_W = MAP_W / #REGIONS   -- 30 columns each
local BEDROCK = MAP_H              -- fill down to the bottom of the map
local SKY_FLOOR = 84               -- nothing survives below this in the sky band

local function regionAt(x) return min(#REGIONS, flr(x / REGION_W) + 1) end
local function biomeAt(x) return REGIONS[regionAt(x)].biome end
local function baseTileOf(b) return 1 + (b - 1) * 8 end

-- ---- surface profile ------------------------------------------------------
local function genSurface()
    for x = 0, MAP_W - 1 do
        local r = REGIONS[regionAt(x)]
        local t = x * 0.13
        local h = r.baseY
            + sin(t) * r.amp
            + sin(x * 0.37 + 1.7) * r.amp * 0.45
            + sin(x * 0.06 + 0.4) * r.amp * 0.8
        World.surfY[x + 1] = clamp(flr(h + 0.5), 40, SKY_FLOOR - 6)
        World.regOf[x + 1] = regionAt(x)
    end
    -- smooth so we never get unclimbable single-tile spikes
    for pass = 1, 2 do
        local src = {}
        for i = 1, MAP_W do src[i] = World.surfY[i] end
        for i = 1, MAP_W do
            local a = src[max(1, i - 1)]
            local b = src[i]
            local c = src[min(MAP_W, i + 1)]
            World.surfY[i] = flr((a + b * 2 + c) / 4 + 0.5)
        end
    end
end

-- ---- the solid mass -------------------------------------------------------
local function isTerrain(t) return t >= 1 and t <= 80 end

local function layMass()
    for x = 0, MAP_W - 1 do
        local top = World.surfY[x + 1]
        local b = biomeAt(x)
        local base = baseTileOf(b)
        for y = top, BEDROCK - 1 do
            -- leave the bottom two rows open as a lava/void floor
            if y < BEDROCK - 2 then
                mset(x, y, base + T.V_MID)
            end
        end
    end
end

-- ---- floating sky islands -------------------------------------------------
local function island(x, y, w, b, thick)
    local base = baseTileOf(b)
    thick = thick or 2
    for i = 0, w - 1 do
        for j = 0, thick - 1 do
            local yy = y + j
            if x + i >= 0 and x + i < MAP_W and yy >= 0 and yy < MAP_H then
                mset(x + i, yy, base + T.V_MID)
            end
        end
    end
end

local function genSky()
    rngSeed(0xA17E)
    for ri, r in ipairs(REGIONS) do
        local x0 = (ri - 1) * REGION_W
        for i = 1, r.sky do
            local w = 3 + rngI(4)
            local x = x0 + 2 + rngI(REGION_W - w - 4)
            local y = 12 + rngI(34)
            island(x, y, w, r.biome, 2 + rngI(2))
            -- a couple of one-way perches above
            if rngChance(0.6) then
                for k = 0, w - 1 do
                    mset(x + k, y - 3, k == 0 and T.PLAT_WOOD_L or T.PLAT_WOOD_R)
                end
            end
            World.spawns[#World.spawns + 1] = { kind = "coinRow", x = x, y = y - 1, w = w }
        end
    end
end

-- ---- caves ----------------------------------------------------------------
local HAZARDS = { VOLCANO = T.LAVA_BODY, SWAMP = T.SLUDGE_BODY }

local function carveCircle(cx, cy, r, b)
    local base = baseTileOf(b)
    for y = cy - r, cy + r do
        for x = cx - r, cx + r do
            if x >= 0 and x < MAP_W and y >= 0 and y < MAP_H then
                local dx, dy = x - cx, y - cy
                if dx * dx + dy * dy <= r * r then
                    if isTerrain(mget(x, y)) then mset(x, y, T.AIR) end
                end
            end
        end
    end
end

local function genCaves()
    rngSeed(0xCAFE)
    for ri, r in ipairs(REGIONS) do
        local x0 = (ri - 1) * REGION_W
        for c = 1, r.caves do
            local x = x0 + 4 + rngI(REGION_W - 8)
            local y = World.surfY[x + 1] + 4 + rngI(10)
            local dirx = rngChance(0.5) and 1 or -1
            local len = 18 + rngI(28)
            local rad = 2 + rngI(2)
            for step = 1, len do
                carveCircle(x, y, rad, r.biome)
                -- the volcano and the marsh keep their caves flooded: drop a
                -- pool along the floor of every pocket we just carved
                if r.tint == "ash" or r.tint == "night" then
                    local haz = (r.tint == "ash") and T.LAVA_BODY or T.SLUDGE_BODY
                    local fy = y + rad
                    for px = x - rad, x + rad do
                        if fy >= 2 and fy < MAP_H - 1 and mget(px, fy) == T.AIR then
                            mset(px, fy, haz)
                            if mget(px, fy + 1) == T.AIR then mset(px, fy + 1, haz) end
                        end
                    end
                end
                x = x + dirx
                y = y + (rngI(3) - 1)
                if rngChance(0.18) then dirx = -dirx end
                x = clamp(x, 1, MAP_W - 2)
                y = clamp(y, World.surfY[clamp(x, 1, MAP_W) + 1] + 3, MAP_H - 4)
            end
        end
    end

    -- Surface pools. Where a cave mouth has opened the ground in a hazardous
    -- region, fill the dip so the region has lethal terrain you can see.
    for ri, r in ipairs(REGIONS) do
        local haz
        if r.tint == "ash" then haz = T.LAVA_BODY
        elseif r.tint == "night" then haz = T.SLUDGE_BODY end
        if haz then
            local x0 = (ri - 1) * REGION_W
            for x = x0, x0 + REGION_W do
                local y = World.surfY[clamp(x, 1, MAP_W - 1) + 1]
                local filled = 0
                while mget(x, y) == T.AIR and filled < 3 do
                    mset(x, y, haz)
                    y = y + 1
                    filled = filled + 1
                end
            end
        end
    end
end

-- ---- autotiling ----------------------------------------------------------
-- Every solid terrain tile is rewritten with the variant that matches which of
-- its four neighbours are exposed. This is what gives the blocks their bevel.
local function refineTerrain()
    for y = 0, MAP_H - 1 do
        for x = 0, MAP_W - 1 do
            local t = mget(x, y)
            if isTerrain(t) then
                local b = flr((t - 1) / 8) + 1
                local base = baseTileOf(b)
                local up = not isTerrain(mget(x, y - 1))
                local dn = not isTerrain(mget(x, y + 1))
                local lf = not isTerrain(mget(x - 1, y))
                local rt = not isTerrain(mget(x + 1, y))

                local v
                if up and lf and rt then
                    v = T.V_SOLO
                elseif up and lf then
                    v = T.V_TOPL
                elseif up and rt then
                    v = T.V_TOPR
                elseif up then
                    v = T.V_TOP
                elseif dn and lf and rt then
                    v = T.V_SOLO
                elseif lf and rt then
                    v = T.V_SOLO
                elseif lf then
                    v = T.V_MIDL
                elseif rt then
                    v = T.V_MIDR
                elseif dn then
                    v = T.V_BOT
                else
                    v = T.V_MID
                end
                mset(x, y, base + v)
            end
        end
    end
end
-- ============================================================================
--  landmarks - villages, gates, shrines, bridges, pagodas
-- ============================================================================

-- a building: 5 wide, 3 tall, written as decor tiles (no collision)
local function house(x, y, style)
    local r = (style == "B") and T.ROOF_B_RIDGE or T.ROOF_A_RIDGE
    mset(x + 0, y, r + 0) mset(x + 1, y, r + 1) mset(x + 2, y, r + 1)
    mset(x + 3, y, r + 1) mset(x + 4, y, r + 2)
    mset(x + 0, y + 1, r + 3) mset(x + 1, y + 1, r + 4) mset(x + 2, y + 1, r + 4)
    mset(x + 3, y + 1, r + 4) mset(x + 4, y + 1, r + 5)
    mset(x + 0, y + 2, r + 6) mset(x + 1, y + 2, r + 7) mset(x + 2, y + 2, r + 7)
    mset(x + 3, y + 2, r + 7) mset(x + 4, y + 2, r + 8)
    mset(x + 0, y + 3, T.WALL_L)
    mset(x + 1, y + 3, rngChance(0.5) and T.WALL_WIN or T.WALL_PLAIN)
    mset(x + 2, y + 3, T.WALL_DOOR)
    mset(x + 3, y + 3, rngChance(0.5) and T.WALL_WIN or T.WALL_PLAIN)
    mset(x + 4, y + 3, T.WALL_R)
    -- a lantern hanging at the door
    World.spawns[#World.spawns + 1] = { kind = "lantern", x = x + 2, y = y + 2 }
end

-- a two tier pagoda, 5 wide x 7 tall
local function pagoda(x, y, style)
    local r = (style == "B") and T.ROOF_B_RIDGE or T.ROOF_A_RIDGE
    for tier = 0, 1 do
        local ty = y + tier * 3
        local shrink = tier
        mset(x + shrink, ty, r + 0)
        for i = 1, 4 - shrink * 2 do mset(x + shrink + i, ty, r + 1) end
        mset(x + 5 - shrink, ty, r + 2)
        mset(x + shrink, ty + 1, r + 3)
        for i = 1, 4 - shrink * 2 do mset(x + shrink + i, ty + 1, r + 4) end
        mset(x + 5 - shrink, ty + 1, r + 5)
        mset(x + shrink, ty + 2, r + 6)
        for i = 1, 4 - shrink * 2 do mset(x + shrink + i, ty + 2, r + 7) end
        mset(x + 5 - shrink, ty + 2, r + 8)
    end
    mset(x + 1, y + 6, T.PILLAR_TOP)
    mset(x + 2, y + 6, T.WALL_DOOR)
    mset(x + 3, y + 6, T.WALL_WIN)
    mset(x + 4, y + 6, T.PILLAR_TOP)
end

-- a torii gate: 4 wide x 5 tall, walk under the lintel
local function torii(x, y)
    mset(x + 0, y, T.TORII_CAP_L) mset(x + 1, y, T.TORII_CAP_M)
    mset(x + 2, y, T.TORII_CAP_M) mset(x + 3, y, T.TORII_CAP_R)
    for k = 2, 3 do
        mset(x + 0, y + k, T.TORII_COL_L)
        mset(x + 3, y + k, T.TORII_COL_R)
    end
    mset(x + 0, y + 4, T.TORII_BASE_L)
    mset(x + 3, y + 4, T.TORII_BASE_R)
end

-- a small shrine: solid stone platform, roof and a save lantern
local function shrine(x, y, id)
    mset(x + 0, y - 1, T.ROOF_A_EAVE + 0)
    mset(x + 1, y - 1, T.ROOF_A_EAVE + 1)
    mset(x + 2, y - 1, T.ROOF_A_EAVE + 2)
    mset(x + 0, y, T.TORII_COL_L)
    mset(x + 1, y, T.SHOJI_L)
    mset(x + 2, y, T.SHOJI_R)
    mset(x + 3, y, T.TORII_COL_R)
    -- walkable base
    for k = -1, 4 do mset(x + k, y + 1, T.FLOOR_STONE) end
    mset(x - 1, y + 1, T.FLOOR_STONE_L)
    mset(x + 4, y + 1, T.FLOOR_STONE_R)
    fset(T.FLOOR_STONE, F_SOLID, true)
    fset(T.FLOOR_STONE_L, F_SOLID, true)
    fset(T.FLOOR_STONE_R, F_SOLID, true)
    World.spawns[#World.spawns + 1] = { kind = "shrine", x = x + 1, y = y, id = id }
end

-- a plank bridge over a drop; the deck is solid
local function bridge(x, y, w)
    fset(T.BRIDGE_A, F_SOLID, true)
    fset(T.BRIDGE_B, F_SOLID, true)
    for i = 0, w - 1 do
        mset(x + i, y, (i % 2 == 0) and T.BRIDGE_A or T.BRIDGE_B)
    end
end

-- a one-way plank run (used for climbing cliffs)
local function planks(x, y, w, style)
    local l, r = T.PLAT_WOOD_L, T.PLAT_WOOD_R
    if style == "stone" then l, r = T.PLAT_STONE_L, T.PLAT_STONE_R end
    if style == "bamboo" then l, r = T.PLAT_BAMBOO_L, T.PLAT_BAMBOO_R end
    if style == "ice" then l, r = T.PLAT_ICE_L, T.PLAT_ICE_R end
    for i = 0, w - 1 do
        if i == 0 then mset(x + i, y, l)
        elseif i == w - 1 then mset(x + i, y, r)
        else mset(x + i, y, (i % 2 == 0) and l or r) end
    end
end

-- ============================================================================
--  surface decoration
-- ============================================================================
local DECOR = {
    [BIOME.GRASS]  = { T.TUFT_A, T.TUFT_B, T.FLOWER_A, T.FLOWER_B, T.BUSH_A, T.BUSH_B },
    [BIOME.BAMBOO] = { T.BAMBOO_CLUSTER, T.BAMBOO_TOP, T.TUFT_B, T.BUSH_A },
    [BIOME.SAKURA] = { T.FLOWER_A, T.FLOWER_B, T.TUFT_A, T.BUSH_B, T.CANOPY_BL },
    [BIOME.STONE]  = { T.ROCK_A, T.ROCK_B, T.TUFT_A, T.FENCE_A },
    [BIOME.SNOW]   = { T.ROCK_B, T.BUSH_A, T.TUFT_A, T.ROCK_A },
    [BIOME.ICE]    = { T.ROCK_A, T.BUSH_A },
    [BIOME.VOLCANO] = { T.ROCK_A, T.ROCK_B, T.SPIKES, T.BUSH_B },
    [BIOME.SWAMP]  = { T.BUSH_B, T.VINE_A, T.TOMB_A, T.JIZO_A },
    [BIOME.CLOUD]  = { T.TUFT_A },
    [BIOME.UNDER]  = { T.TOMB_A, T.ROCK_B },
}

local function placeTree(x, groundY, kind)
    -- kind: "sakura" | "pine" | "maple" | "snow"
    if kind == "pine" then
        mset(x, groundY - 1, T.PINE_TRUNK)
        mset(x, groundY - 2, T.PINE_TRUNK)
        mset(x, groundY - 3, T.PINE_T1)
        mset(x, groundY - 4, T.PINE_T2)
        mset(x, groundY - 5, T.PINE_T3)
    elseif kind == "sakura" or kind == "maple" then
        local a, b = T.CANOPY_TL, T.CANOPY_BL
        if kind == "maple" then a, b = T.MAPLE_A, T.MAPLE_B end
        mset(x, groundY - 1, T.TRUNK_TOP)
        mset(x, groundY - 2, T.TRUNK_MID)
        if kind == "sakura" then
            mset(x, groundY - 5, T.CANOPY_TL) mset(x + 1, groundY - 5, T.CANOPY_TR)
            mset(x, groundY - 4, T.CANOPY_ML) mset(x + 1, groundY - 4, T.CANOPY_MR)
            mset(x, groundY - 3, T.CANOPY_BL) mset(x + 1, groundY - 3, T.CANOPY_BR)
        else
            mset(x, groundY - 4, T.MAPLE_A) mset(x + 1, groundY - 4, T.MAPLE_B)
            mset(x, groundY - 3, T.MAPLE_B)
        end
    else
        mset(x, groundY - 1, T.SNOWTREE_A)
        mset(x, groundY - 2, T.SNOWTREE_B)
    end
end

local function placeSurfaceDecor()
    rngSeed(0xDEC0)
    for x = 1, MAP_W - 2 do
        local gy = World.surfY[x + 1]
        if isTerrain(mget(x, gy)) then          -- only on real ground
            local b = biomeAt(x)
            if b == BIOME.BAMBOO then
                if rngChance(0.55) then
                    local h = 3 + rngI(5)
                    for k = 1, h do mset(x, gy - k, T.BAMBOO_L) mset(x + 1, gy - k, T.BAMBOO_R) end
                    mset(x, gy - h - 1, T.BAMBOO_TOP)
                end
            elseif b == BIOME.SAKURA and rngChance(0.22) then
                placeTree(x, gy, "sakura")
                x = x + 1
            elseif b == BIOME.SNOW and rngChance(0.16) then
                placeTree(x, gy, "snow")
            elseif b == BIOME.STONE and rngChance(0.1) then
                placeTree(x, gy, "pine")
            elseif rngChance(0.42) then
                local set = DECOR[b]
                if set and #set > 0 then
                    mset(x, gy - 1, set[1 + rngI(#set)])
                end
            end
            -- lantern posts along the roads
            if rngChance(0.05) then
                mset(x, gy - 1, T.LANT_BOT)
                mset(x, gy - 2, T.LANT_MID)
                mset(x, gy - 3, T.LANT_TOP)
            end
        end
    end
end

-- ============================================================================
--  hand placed landmarks + the progression items
-- ============================================================================
local function placeLandmarks()
    local S = World.spawns
    local function chest(kind, x, y, item)
        S[#S + 1] = { kind = "chest", x = x, y = y, item = item }
    end
    local function enemy(kind, x, y)
        S[#S + 1] = { kind = kind, x = x, y = y }
    end
    local function coin(x, y)
        S[#S + 1] = { kind = "coin", x = x, y = y }
    end

    -- ---------- region 1 : Bamboo Village ----------
    local gy = World.surfY[7]
    World.startX, World.startY = 6, gy - 2
    house(10, gy - 4, "A")
    house(18, gy - 4, "B")
    house(26, gy - 4, "A")
    shrine(3, gy - 3, 1)
    torii(14, gy - 5)
    for i = 1, 6 do coin(20 + i, gy - 3) end
    S[#S + 1] = { kind = "npc", x = 13, y = gy - 1, text = "village" }
    S[#S + 1] = { kind = "npc", x = 22, y = gy - 1, text = "scroll" }
    enemy("oni", 27, gy - 1)

    -- ---------- region 2 : Whispering Bamboo ----------
    local g2 = World.surfY[36]
    shrine(32, g2 - 3, 2)
    chest("scroll", 40, g2 - 2, "doublejump")          -- unlocks double jump
    for i = 0, 5 do planks(44 + i * 2, g2 - 5 - i, 2, "bamboo") end
    for i = 1, 8 do coin(46 + i * 2, g2 - 6 - i) end
    enemy("oni", 34, g2 - 1)
    enemy("tengu", 44, g2 - 8)
    enemy("oni", 52, g2 - 1)
    S[#S + 1] = { kind = "npc", x = 48, y = g2 - 11, text = "hermit" }

    -- ---------- region 3 : Sakura Hills ----------
    local g3 = World.surfY[70]
    shrine(62, g3 - 3, 3)
    torii(66, g3 - 5)
    torii(78, g3 - 5)
    for i = 0, 7 do coin(68 + i, g3 - 2) end
    chest("scroll", 84, g3 - 2, "wallcling")           -- unlocks wall cling
    enemy("oni", 72, g3 - 1)
    enemy("tengu", 76, g3 - 7)
    enemy("kitsune", 82, g3 - 1)
    house(74, g3 - 4, "B")

    -- ---------- region 4 : Stone Pass ----------
    local g4 = World.surfY[100]
    shrine(92, g4 - 3, 4)
    pagoda(98, g4 - 8, "B")
    for i = 0, 6 do planks(106 + i, g4 - 4 - flr(i / 2), 1, "stone") end
    chest("coin", 104, g4 - 4, "coin")
    enemy("rogue", 96, g4 - 1)
    enemy("oni", 102, g4 - 1)
    enemy("rogue", 110, g4 - 1)
    bridge(112, g4, 5)

    -- ---------- region 5 : Yuki Mountain ----------
    local g5 = World.surfY[130]
    shrine(122, g5 - 3, 5)
    chest("scroll", 136, g5 - 2, "airDash")            -- unlocks the air dash
    for i = 0, 4 do planks(128 + i * 3, g5 - 5 - i, 3, "ice") end
    enemy("tengu", 126, g5 - 6)
    enemy("oni", 132, g5 - 1)
    enemy("kappa", 140, g5 - 1)
    for i = 1, 5 do coin(128 + i * 2, g5 - 8) end

    -- ---------- region 6 : Oni Caldera ----------
    local g6 = World.surfY[165]
    shrine(152, g6 - 3, 6)
    S[#S + 1] = { kind = "boss", x = 170, y = g6 - 6 }
    enemy("oni", 158, g6 - 1)
    enemy("oni", 162, g6 - 1)
    enemy("kitsune", 176, g6 - 1)
    enemy("tengu", 180, g6 - 8)
    chest("scroll", 156, g6 - 2, "spiritFlame")
    torii(150, g6 - 5)
    torii(184, g6 - 5)

    -- ---------- region 7 : Spirit Marsh ----------
    local g7 = World.surfY[195]
    shrine(190, g7 - 3, 7)
    chest("scroll", 204, g7 - 2, "waterWalk")          -- unlocks water walking
    for i = 0, 6 do planks(196 + i, g7 - 4 - (i % 2), 1, "stone") end
    enemy("yurei", 194, g7 - 5)
    enemy("yurei", 202, g7 - 6)
    enemy("kappa", 200, g7 - 1)
    enemy("kitsune", 208, g7 - 1)

    -- ---------- region 8 : Temple Ruins ----------
    local g8 = World.surfY[225]
    shrine(212, g8 - 3, 8)
    pagoda(216, g8 - 8, "B")
    pagoda(224, g8 - 8, "A")
    torii(222, g8 - 5)
    S[#S + 1] = { kind = "boss", x = 232, y = g8 - 6 }
    enemy("rogue", 218, g8 - 1)
    enemy("rogue", 228, g8 - 1)
    enemy("oni", 220, g8 - 1)
    chest("coin", 234, g8 - 2, "coin")
    for i = 0, 5 do coin(228 + i, g8 - 3) end
end

-- ---- traversal helper: planks where the step is impossible ----------------
local function placeClimbHelpers()
    for x = 1, MAP_W - 3 do
        local a, b = World.surfY[x + 1], World.surfY[x + 2]
        local step = a - b            -- positive = the next column is higher
        if step >= 4 then
            local y = a - 2
            local w = min(3, 240 - x)
            planks(x + 1, y, w, "wood")
        end
    end
end

-- ============================================================================
--  start position
-- ============================================================================
-- Never hard-code the spawn: drop it on the first solid thing under (x=8),
-- which is clear of the shrine the village places at x=2..7.
local function findStart()
    local x = 8
    for y = 36, MAP_H - 4 do
        local t = mget(x, y)
        if t ~= 0 and (isTerrain(t) or fget(t, F_SOLID)) then
            World.startX, World.startY = x, y - 2
            return
        end
    end
end

-- ============================================================================
--  entry point
-- ============================================================================
local function worldGen()
    genSurface()
    layMass()
    genSky()
    genCaves()
    placeLandmarks()
    placeSurfaceDecor()
    placeClimbHelpers()
    refineTerrain()
    findStart()
end

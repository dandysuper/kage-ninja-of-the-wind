-- ============================================================================
--  04 - ATLAS + TERRAIN
--
--  The tile registry (T) and the generators for every block in the world.
--  All terrain is drawn with a consistent 3-tone bevel - bright top, mid face,
--  dark right/bottom - plus a 1px ink line on exposed edges. Adjacent blocks
--  therefore read as extruded cubes: that is where the 2.5D illusion lives.
--  Light comes from the upper left.
-- ============================================================================

T.AIR = 0

-- ---- biome blocks 1..80 : base(b) = 1 + (b-1)*8 ----------------------------
T.V_SOLO, T.V_TOP, T.V_TOPL, T.V_TOPR = 0, 1, 2, 3
T.V_MID, T.V_MIDL, T.V_MIDR, T.V_BOT = 4, 5, 6, 7

local function tBase(b) return 1 + (b - 1) * 8 end

-- ---- one-way platforms 81..88 ---------------------------------------------
T.PLAT_WOOD_L, T.PLAT_WOOD_R = 81, 82
T.PLAT_STONE_L, T.PLAT_STONE_R = 83, 84
T.PLAT_BAMBOO_L, T.PLAT_BAMBOO_R = 85, 86
T.PLAT_ICE_L, T.PLAT_ICE_R = 87, 88

-- ---- liquids 89..100 ------------------------------------------------------
T.WATER_L, T.WATER_R, T.WATER_BODY = 89, 90, 91
T.FALL_TOP, T.FALL_MID, T.FALL_BOT = 92, 93, 94
T.LAVA_L, T.LAVA_R, T.LAVA_BODY = 95, 96, 97
T.SLUDGE_L, T.SLUDGE_R, T.SLUDGE_BODY = 98, 99, 100

-- ---- building parts 101..152 ---------------------------------------------
T.ROOF_A_RIDGE = 101   -- +0,+1,+2 = L,M,R
T.ROOF_A_SLOPE = 104
T.ROOF_A_EAVE = 107
T.ROOF_B_RIDGE = 110
T.ROOF_B_SLOPE = 113
T.ROOF_B_EAVE = 116
T.WALL_PLAIN, T.WALL_WIN, T.WALL_DOOR, T.WALL_BEAM = 119, 120, 121, 122
T.WALL_L, T.WALL_R = 123, 124
T.SHOJI_L, T.SHOJI_R = 125, 126
T.PILLAR_TOP, T.PILLAR_MID, T.PILLAR_BOT = 127, 128, 129
T.BEAM_H, T.BEAM_CL, T.BEAM_CR = 130, 131, 132
T.TORII_COL_L, T.TORII_COL_R = 133, 134
T.TORII_CAP_L, T.TORII_CAP_M, T.TORII_CAP_R = 135, 136, 137
T.TORII_BASE_L, T.TORII_BASE_R = 138, 139
T.LANT_TOP, T.LANT_MID, T.LANT_BOT = 140, 141, 142
T.FENCE_A, T.FENCE_B = 143, 144
T.BANNER_TOP, T.BANNER_MID = 145, 146
T.WELL_TOP, T.WELL_BOT = 147, 148
T.STAIR_L, T.STAIR_R = 149, 150
T.SIGN_TOP, T.SIGN_BOT = 151, 152

-- ---- nature 153..192 ------------------------------------------------------
T.TRUNK_TOP, T.TRUNK_MID = 153, 154
T.CANOPY_TL, T.CANOPY_TR, T.CANOPY_ML = 155, 156, 157
T.CANOPY_MR, T.CANOPY_BL, T.CANOPY_BR = 158, 159, 160
T.PINE_TRUNK = 161
T.PINE_T1, T.PINE_T2, T.PINE_T3 = 162, 163, 164
T.BAMBOO_L, T.BAMBOO_R, T.BAMBOO_TOP, T.BAMBOO_LEAF = 165, 166, 167, 168
T.BUSH_A, T.BUSH_B = 169, 170
T.TUFT_A, T.TUFT_B = 171, 172
T.FLOWER_A, T.FLOWER_B = 173, 174
T.ROCK_A, T.ROCK_B = 175, 176
T.BOULDER_TL, T.BOULDER_TR, T.BOULDER_BL, T.BOULDER_BR = 177, 178, 179, 180
T.VINE_A, T.VINE_B = 181, 182
T.LADDER_A, T.LADDER_B = 183, 184
T.JIZO_A, T.JIZO_B = 185, 186
T.TOMB_A = 187
T.BAMBOO_CLUSTER = 188
T.MAPLE_A, T.MAPLE_B = 189, 190
T.SNOWTREE_A, T.SNOWTREE_B = 191, 192

-- ---- misc / interiors 193..210 --------------------------------------------
T.CHEST_CLOSED, T.CHEST_OPEN = 193, 194
T.POT, T.BARREL, T.CRATE = 195, 196, 197
T.SPIKES, T.SPIKE_BASE = 198, 199
T.CLOUD_L, T.CLOUD_R = 200, 201
T.ISLAND_EDGE = 202
T.BRIDGE_A, T.BRIDGE_B = 203, 204
T.FLOOR_WOOD, T.FLOOR_WOOD_L, T.FLOOR_WOOD_R = 205, 206, 207
T.FLOOR_STONE, T.FLOOR_STONE_L, T.FLOOR_STONE_R = 208, 209, 210

-- ---- biome ids ------------------------------------------------------------
BIOME.GRASS, BIOME.BAMBOO, BIOME.SAKURA, BIOME.STONE, BIOME.SNOW = 1, 2, 3, 4, 5
BIOME.ICE, BIOME.VOLCANO, BIOME.SWAMP, BIOME.CLOUD, BIOME.UNDER = 6, 7, 8, 9, 10

-- biome palette: name, capTop, capShade, face, faceGrain, right, bottom, style
local BSPEC = {
    { J, F,  BR, DK, DK, K, "soil"  },  -- 1 grass
    { F, DK, BR, DK, DK, K, "soil"  },  -- 2 bamboo
    { J, F,  BR, DK, DK, K, "soil"  },  -- 3 sakura
    { N, S,  B,  K,  K,  K, "brick" },  -- 4 stone
    { W, N,  N,  B,  B,  K, "rock"  },  -- 5 snow
    { S, B,  B,  K,  K,  K, "ice"   },  -- 6 ice
    { K, K,  K,  R,  K,  K, "ash"   },  -- 7 volcano
    { F, DK, DK, K,  K,  K, "soil"  },  -- 8 swamp
    { W, N,  N,  S,  S,  B, "cloud" },  -- 9 cloud
    { VI, K, K,  VI, K,  K, "deep"  },  -- 10 under
}

-- ============================================================================
--  terrain blocks
-- ============================================================================

local function paintFace(y0, y1, face, grain, seed, dense)
    for y = y0, y1 do
        for x = 0, 7 do
            artP(x, y, face)
            if artNoise(x, y, seed) < dense then artP(x, y, grain) end
        end
    end
end

local function genBlock(id, spec, variant, seed)
    local ct, cs, fc, gr, rt, bt, sty =
        spec[1], spec[2], spec[3], spec[4], spec[5], spec[6], spec[7]

    artBegin8(id)
    artClear(V)

    local topE = variant == T.V_TOP or variant == T.V_TOPL or variant == T.V_TOPR or variant == T.V_SOLO
    local leftE = variant == T.V_TOPL or variant == T.V_MIDL or variant == T.V_SOLO
    local rightE = variant == T.V_TOPR or variant == T.V_MIDR or variant == T.V_SOLO
    local botE = variant == T.V_BOT

    local fy0 = 0
    if topE then
        artH(0, 7, 0, K)
        artH(0, 7, 1, ct)
        artH(0, 7, 2, cs)
        fy0 = 3
        artP(1, 1, ct) artP(5, 1, ct) artP(3, 0, ct)
        if sty == "soil" then artP(2, 2, cs) artP(6, 2, cs) end
    end

    paintFace(fy0, 7, fc, gr, seed, sty == "ice" and 8 or 18)

    if botE then
        artH(0, 7, 7, bt)
        artH(0, 7, 6, gr)
    end
    if leftE then
        artV(0, 0, 7, K)
        artV(1, 0, 7, gr)
    end
    if rightE then
        artV(7, 0, 7, rt)
        artV(6, 0, 7, rt)
    end

    if sty == "soil" then
        artP(3, 4 + (seed % 2), gr) artP(5, 6, gr) artP(2, 6, gr)
    elseif sty == "brick" then
        artH(0, 7, 4, K) artV(4, 0, 3, K) artV(2, 5, 7, K)
    elseif sty == "ice" then
        artLine(1, 5, 4, 3, S) artLine(4, 6, 6, 4, S)
    elseif sty == "ash" then
        artP(2, 4, R) artP(3, 5, R) artP(5, 3, O) artP(6, 6, C)
        artLine(1, 6, 2, 5, C)
    elseif sty == "cloud" then
        artP(2, 3, W) artP(6, 5, W) artDisc(4, 5, 1, W)
    elseif sty == "deep" then
        artP(2, 4, VI) artP(5, 6, VI) artP(4, 2, C)
    elseif sty == "rock" then
        artP(2, 5, B) artP(6, 3, B)
    end
end

-- ============================================================================
--  one-way platforms
-- ============================================================================
local PLAT_SPEC = {
    { T.PLAT_WOOD_L,   T.PLAT_WOOD_R,   BR, DK, G },
    { T.PLAT_STONE_L,  T.PLAT_STONE_R,  B,  K,  N },
    { T.PLAT_BAMBOO_L, T.PLAT_BAMBOO_R, J,  F,  N },
    { T.PLAT_ICE_L,    T.PLAT_ICE_R,    S,  B,  W },
}

local function genPlatforms()
    for i = 1, #PLAT_SPEC do
        local l, r, fc, dk, hi = PLAT_SPEC[i][1], PLAT_SPEC[i][2],
            PLAT_SPEC[i][3], PLAT_SPEC[i][4], PLAT_SPEC[i][5]

        artBegin8(l) artClear(V)
        artH(0, 7, 0, K)
        artH(0, 7, 1, hi) artH(0, 7, 2, fc) artH(0, 7, 3, dk)
        artP(0, 1, K) artP(0, 2, K) artP(0, 3, K)
        artH(1, 7, 4, dk) artP(2, 4, K) artP(5, 4, K)
        artV(0, 4, 5, K)
        fset(l, F_ONEWAY, true)

        artBegin8(r) artClear(V)
        artH(0, 7, 0, K)
        artH(0, 7, 1, hi) artH(0, 7, 2, fc) artH(0, 7, 3, dk)
        artP(7, 1, K) artP(7, 2, K) artP(7, 3, K)
        artH(0, 6, 4, dk) artP(2, 4, K) artP(6, 4, K)
        artV(7, 4, 5, K)
        fset(r, F_ONEWAY, true)
    end
end

-- ============================================================================
--  liquids
-- ============================================================================
local function genLiquids()
    local function waterSurface(id, left)
        artBegin8(id) artClear(V)
        artH(0, 7, 0, S) artH(0, 7, 1, B) artH(0, 7, 2, B)
        for x = 0, 7 do
            if artNoise(x, 3, 7) < 40 then artP(x, 0, W) end
        end
        artDither(0, 3, 7, 7, B, nil, 11, 40)
        if left then artV(0, 0, 7, K) end
        fset(id, F_WATER, true)
    end
    waterSurface(T.WATER_L, true)
    waterSurface(T.WATER_R, false)

    artBegin8(T.WATER_BODY) artClear(V)
    artDither(0, 0, 7, 7, B, nil, 13, 34)
    artP(2, 1, S) artP(5, 4, S)
    fset(T.WATER_BODY, F_WATER, true)

    artBegin8(T.FALL_TOP) artClear(V)
    artBox(1, 0, 6, 7, S) artBox(2, 1, 5, 7, W)
    artV(1, 0, 7, B) artV(6, 0, 7, B)
    fset(T.FALL_TOP, F_WATER, true)

    artBegin8(T.FALL_MID) artClear(V)
    artBox(1, 0, 6, 7, S)
    for y = 0, 7 do
        artP(2 + (y % 3), y, W)
        artP(5 - (y % 2), y, W)
        artP(1, y, B) artP(6, y, B)
    end
    fset(T.FALL_MID, F_WATER, true)

    artBegin8(T.FALL_BOT) artClear(V)
    artBox(1, 0, 6, 5, S)
    artDisc(2, 6, 2, S) artDisc(5, 6, 1, W)
    fset(T.FALL_BOT, F_WATER, true)

    local function lavaSurface(id, left)
        artBegin8(id) artClear(V)
        artH(0, 7, 0, O) artH(0, 7, 1, R)
        for x = 0, 7 do if artNoise(x, 4, 3) < 45 then artP(x, 0, G) end end
        artDither(0, 2, 7, 7, C, K, 5, 40)
        artP(3, 3, R) artP(6, 5, O) artP(1, 5, R)
        if left then artV(0, 0, 7, K) end
        fset(id, F_HAZARD, true) fset(id, F_WATER, true)
    end
    lavaSurface(T.LAVA_L, true)
    lavaSurface(T.LAVA_R, false)

    artBegin8(T.LAVA_BODY) artClear(V)
    artDither(0, 0, 7, 7, C, K, 17, 38)
    artP(4, 2, R) artP(2, 6, O)
    fset(T.LAVA_BODY, F_HAZARD, true)

    local function sludge(id, left)
        artBegin8(id) artClear(V)
        artH(0, 7, 0, F) artH(0, 7, 1, DK)
        artDither(0, 2, 7, 7, DK, F, 23, 30)
        for x = 0, 7 do if artNoise(x, 0, 9) < 35 then artP(x, 0, J) end end
        if left then artV(0, 0, 7, K) end
        fset(id, F_WATER, true)
    end
    sludge(T.SLUDGE_L, true)
    sludge(T.SLUDGE_R, false)

    artBegin8(T.SLUDGE_BODY) artClear(V)
    artDither(0, 0, 7, 7, DK, F, 29, 26)
    fset(T.SLUDGE_BODY, F_WATER, true)
end

-- ============================================================================
genTerrain = function()
    for b = 1, 10 do
        local base = tBase(b)
        local spec = BSPEC[b]
        for v = 0, 7 do
            genBlock(base + v, spec, v, b * 31 + v * 7)
        end
    end
    genPlatforms()
    genLiquids()
end

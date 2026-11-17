-- ============================================================================
--  05 - PROPS : buildings, gates, lanterns, furniture and nature
--
--  These tiles are mostly *decor*: they are placed into the map but carry no
--  collision flag, so entities are drawn over them. That keeps the world solid
--  only where the platforming needs it, and lets buildings sit "behind" the
--  ninja.
-- ============================================================================

-- ============================================================================
--  helpers
-- ============================================================================
local function paint(id, fn)
    artBegin8(id)
    artClear(V)
    fn()
end

-- vertical wooden plank: body colour, a darker grain line and lit left edge
local function woodV(cBody, cDark, seed)
    for y = 0, 7 do
        artV(0, y, y, cBody)
        for x = 0, 7 do
            artP(x, y, cBody)
            if artNoise(x, y, seed or 3) < 16 then artP(x, y, cDark) end
        end
    end
    artV(1, 0, 7, cDark)
    artV(7, 0, 7, cDark)
end

-- horizontal plank
local function woodH(cBody, cDark, seed)
    for x = 0, 7 do
        for y = 0, 7 do
            artP(x, y, cBody)
            if artNoise(x, y, seed or 5) < 16 then artP(x, y, cDark) end
        end
    end
    artH(0, 7, 1, cDark)
    artH(0, 7, 7, cDark)
end

-- ============================================================================
--  roofs - two styles, three horizontal bands, three columns
--    ridge : the top cap of the roof
--    slope : overlapping ceramic tiles
--    eave  : the lowest row, with the upturned corner on L/R
-- ============================================================================
local function roofSet(base, cMain, cDark, cLight, cRidge)
    -- ---- ridge ----
    paint(base, function()
        artH(0, 7, 0, K)
        artH(0, 7, 1, cRidge)
        artH(0, 7, 2, cMain)
        artH(0, 7, 3, cDark)
        artP(2, 1, cLight) artP(6, 1, cLight)
    end)
    paint(base + 1, function()
        artH(0, 7, 0, K)
        artH(0, 7, 1, cRidge)
        artH(0, 7, 2, cMain)
        artH(0, 7, 3, cDark)
        for x = 0, 7, 2 do artP(x, 1, cLight) end
    end)
    paint(base + 2, function()
        artH(0, 7, 0, K)
        artH(0, 7, 1, cRidge)
        artH(0, 7, 2, cMain)
        artH(0, 7, 3, cDark)
        artP(1, 1, cLight) artP(5, 1, cLight)
        artV(7, 1, 3, K)
    end)

    -- ---- slope ----
    paint(base + 3, function()
        artH(0, 7, 0, cLight)
        for y = 1, 7 do
            artH(0, 7, y, cMain)
            if artNoise(3, y, 8) < 55 then artH(0, 7, y, cDark) end
        end
        for y = 1, 7, 2 do artH(0, 7, y, cDark) end
        artH(0, 1, 4, cLight)
        artV(0, 0, 7, K)
    end)
    paint(base + 4, function()
        artH(0, 7, 0, cLight)
        for y = 1, 7 do
            artH(0, 7, y, cMain)
            if artNoise(3, y, 8) < 55 then artH(0, 7, y, cDark) end
        end
        for y = 1, 7, 2 do artH(0, 7, y, cDark) end
        for x = 0, 7, 3 do artP(x, 5, cDark) end
    end)
    paint(base + 5, function()
        artH(0, 7, 0, cLight)
        for y = 1, 7 do
            artH(0, 7, y, cMain)
            if artNoise(3, y, 8) < 55 then artH(0, 7, y, cDark) end
        end
        for y = 1, 7, 2 do artH(0, 7, y, cDark) end
        artH(6, 7, 4, cLight)
        artV(7, 0, 7, K)
    end)

    -- ---- eave ----
    paint(base + 6, function()
        artP(0, 0, cLight) artP(1, 1, cLight) artP(2, 1, cLight)
        artH(2, 7, 2, cMain) artH(0, 7, 3, cMain)
        artH(0, 7, 1, cMain)
        artH(0, 7, 4, cDark) artH(0, 7, 5, K)
        artH(0, 7, 6, K) artH(0, 7, 7, K)
        artV(0, 1, 5, K)
    end)
    paint(base + 7, function()
        artH(0, 7, 1, cMain)
        artH(0, 7, 2, cLight) artH(0, 7, 3, cMain)
        artH(0, 7, 4, cDark) artH(0, 7, 5, K)
        artH(0, 7, 6, K) artH(0, 7, 7, K)
        for x = 0, 7, 4 do artP(x, 4, K) end
    end)
    paint(base + 8, function()
        artP(5, 0, cLight) artP(6, 1, cLight)
        artH(0, 6, 1, cMain)
        artH(0, 7, 2, cMain) artH(0, 7, 3, cMain)
        artH(0, 7, 4, cDark) artH(0, 7, 5, K)
        artH(0, 7, 6, K) artH(0, 7, 7, K)
        artV(7, 1, 5, K)
    end)
end

-- ============================================================================
--  walls : white plaster with dark timber, plus windows, doors and screens
-- ============================================================================
local function wallBase(cPlaster, cPlasterD)
    for y = 0, 7 do
        for x = 0, 7 do
            artP(x, y, cPlaster)
            if artNoise(x, y, 21) < 10 then artP(x, y, cPlasterD) end
        end
    end
end

local function genWalls()
    local plaster, plasterD = N, S

    paint(T.WALL_PLAIN, function()
        wallBase(plaster, plasterD)
        artH(0, 7, 7, BR)
        artH(0, 7, 0, BR)
    end)

    paint(T.WALL_WIN, function()
        wallBase(plaster, plasterD)
        artH(0, 7, 7, BR) artH(0, 7, 0, BR)
        artBox(1, 2, 6, 5, K)
        artBox(2, 3, 5, 4, B)
        artP(3, 3, S) artP(4, 3, S)
        artV(3, 3, 4, K)
    end)

    paint(T.WALL_DOOR, function()
        wallBase(plaster, plasterD)
        artH(0, 7, 7, BR) artH(0, 7, 0, BR)
        artBox(1, 3, 6, 7, K)
        artBox(2, 4, 5, 7, DK)
        artH(1, 6, 3, R)
        artP(2, 3, C) artP(3, 3, C) artP(4, 3, C) artP(5, 3, C)
    end)

    paint(T.WALL_BEAM, function()
        wallBase(plaster, plasterD)
        artH(0, 7, 0, K)
        artH(0, 7, 1, BR) artH(0, 7, 2, DK)
        artH(0, 7, 7, BR)
    end)

    paint(T.WALL_L, function()
        wallBase(plaster, plasterD)
        artV(0, 0, 7, K)
        artV(1, 0, 7, BR) artV(2, 0, 7, DK)
        artH(0, 7, 7, BR)
    end)

    paint(T.WALL_R, function()
        wallBase(plaster, plasterD)
        artV(7, 0, 7, K)
        artV(6, 0, 7, BR) artV(5, 0, 7, DK)
        artH(0, 7, 7, BR)
    end)

    paint(T.SHOJI_L, function()
        artBox(0, 0, 7, 7, N)
        artV(0, 0, 7, K) artH(0, 7, 0, K) artH(0, 7, 7, K)
        artH(0, 7, 3, BR) artV(3, 0, 7, BR)
        artP(4, 1, S) artP(5, 5, S)
    end)

    paint(T.SHOJI_R, function()
        artBox(0, 0, 7, 7, N)
        artV(7, 0, 7, K) artH(0, 7, 0, K) artH(0, 7, 7, K)
        artH(0, 7, 3, BR) artV(4, 0, 7, BR)
        artP(2, 5, S) artP(1, 1, S)
    end)
end

-- ============================================================================
--  pillars, beams, gates, lanterns, fences
-- ============================================================================
local function genStructures()
    -- pillars: dark timber with a lit left facet
    paint(T.PILLAR_TOP, function()
        artH(0, 7, 0, K)
        artH(1, 6, 1, BR)
        artV(1, 1, 7, BR) artV(2, 1, 7, DK)
        artV(6, 1, 7, DK) artV(5, 1, 7, BR)
        artV(0, 1, 7, K) artV(7, 1, 7, K)
        artH(0, 7, 2, K)
    end)
    paint(T.PILLAR_MID, function()
        artV(1, 0, 7, BR) artV(2, 0, 7, DK)
        artV(6, 0, 7, DK) artV(5, 0, 7, BR)
        artV(0, 0, 7, K) artV(7, 0, 7, K)
    end)
    paint(T.PILLAR_BOT, function()
        artV(1, 0, 6, BR) artV(2, 0, 6, DK)
        artV(6, 0, 6, DK) artV(5, 0, 6, BR)
        artV(0, 0, 7, K) artV(7, 0, 7, K)
        artH(0, 7, 7, K)
        artH(0, 7, 5, K)
    end)

    paint(T.BEAM_H, function()
        artH(0, 7, 0, K)
        artH(0, 7, 1, BR) artH(0, 7, 2, BR)
        artH(0, 7, 3, DK) artH(0, 7, 4, K)
    end)
    paint(T.BEAM_CL, function()
        artH(0, 7, 0, K) artH(0, 7, 1, BR) artH(0, 7, 2, BR)
        artH(0, 7, 3, DK) artH(0, 7, 4, K)
        artV(0, 0, 4, K)
    end)
    paint(T.BEAM_CR, function()
        artH(0, 7, 0, K) artH(0, 7, 1, BR) artH(0, 7, 2, BR)
        artH(0, 7, 3, DK) artH(0, 7, 4, K)
        artV(7, 0, 4, K)
    end)

    -- ---- torii gate: vermilion columns, two crossbeams ----
    paint(T.TORII_COL_L, function()
        artV(2, 0, 7, K) artV(3, 0, 7, R) artV(4, 0, 7, R) artV(5, 0, 7, C)
        artV(1, 0, 7, K)
    end)
    paint(T.TORII_COL_R, function()
        artV(6, 0, 7, K) artV(5, 0, 7, R) artV(4, 0, 7, R) artV(3, 0, 7, C)
        artV(7, 0, 7, K)
    end)
    paint(T.TORII_CAP_L, function()
        artH(0, 7, 0, K)
        artH(0, 7, 1, K)
        artH(0, 7, 2, R) artH(0, 7, 3, R) artH(0, 7, 4, C)
        artH(0, 7, 5, K)
        artP(0, 1, K) artP(1, 0, R) artP(0, 2, R)
    end)
    paint(T.TORII_CAP_M, function()
        artH(0, 7, 0, K) artH(0, 7, 1, K)
        artH(0, 7, 2, R) artH(0, 7, 3, R) artH(0, 7, 4, C)
        artH(0, 7, 5, K)
        artH(0, 7, 6, R) artH(0, 7, 7, C)
    end)
    paint(T.TORII_CAP_R, function()
        artH(0, 7, 0, K) artH(0, 7, 1, K)
        artH(0, 7, 2, R) artH(0, 7, 3, R) artH(0, 7, 4, C)
        artH(0, 7, 5, K)
        artP(7, 1, K) artP(6, 0, R) artP(7, 2, R)
    end)
    paint(T.TORII_BASE_L, function()
        artH(0, 7, 6, K) artH(0, 7, 7, K)
        artBox(1, 3, 5, 5, N) artV(1, 3, 5, K)
        artH(1, 5, 3, K)
    end)
    paint(T.TORII_BASE_R, function()
        artH(0, 7, 6, K) artH(0, 7, 7, K)
        artBox(2, 3, 6, 5, N) artV(6, 3, 5, K)
        artH(2, 6, 3, K)
    end)

    -- ---- stone lantern ----
    paint(T.LANT_TOP, function()
        artH(0, 7, 0, K)
        artH(2, 6, 1, N) artH(1, 7, 2, N)
        artH(0, 7, 3, K)
        artP(3, 0, N) artP(4, 0, N) artH(2, 5, 1, N)
    end)
    paint(T.LANT_MID, function()
        artBox(1, 0, 6, 7, N) artV(1, 0, 7, K) artV(6, 0, 7, K)
        artBox(3, 2, 4, 5, G)
        artP(3, 3, W) artP(4, 4, W)
        artH(0, 7, 0, K) artH(0, 7, 7, K)
    end)
    paint(T.LANT_BOT, function()
        artH(0, 7, 0, K)
        artH(1, 6, 1, N) artH(2, 5, 2, N)
        artH(1, 6, 3, K)
        artBox(1, 4, 6, 7, N) artH(0, 7, 7, K)
    end)

    paint(T.FENCE_A, function()
        artBox(1, 2, 6, 7, BR)
        artV(1, 2, 7, K) artV(6, 2, 7, K)
        artH(0, 7, 2, K) artH(0, 7, 5, K)
        artH(2, 5, 1, BR)
    end)
    paint(T.FENCE_B, function()
        artBox(0, 3, 7, 7, BR)
        artV(0, 3, 7, K) artV(7, 3, 7, K)
        artH(0, 7, 3, K)
        for x = 2, 6, 2 do artP(x, 5, DK) end
    end)

    paint(T.BANNER_TOP, function()
        artBox(0, 0, 7, 6, R)
        artV(0, 0, 7, K) artV(7, 0, 7, K) artH(0, 7, 0, K)
        artP(3, 2, W) artP(4, 2, W) artP(3, 3, W)
        artH(0, 7, 7, K)
    end)
    paint(T.BANNER_MID, function()
        artBox(0, 0, 7, 6, R)
        artV(0, 0, 7, K) artV(7, 0, 7, K)
        artP(3, 2, W) artP(4, 4, W) artP(5, 1, W)
    end)

    paint(T.WELL_TOP, function()
        artH(0, 7, 0, K)
        artH(0, 7, 1, N) artH(1, 6, 2, N)
        artH(0, 7, 3, N) artH(0, 7, 4, K)
        artBox(1, 5, 6, 7, B)
        artP(2, 6, S) artP(5, 6, S)
    end)
    paint(T.WELL_BOT, function()
        artH(0, 7, 0, K) artH(0, 7, 1, N) artH(3, 4, 2, K) artH(0, 7, 7, K)
        artV(0, 0, 7, N) artV(7, 0, 7, N) artV(0, 0, 7, K) artV(7, 0, 7, K)
        artH(1, 6, 3, B)
    end)

    paint(T.STAIR_L, function()
        artH(0, 7, 0, K)
        artH(2, 7, 1, N) artH(4, 7, 3, N) artH(6, 7, 5, N)
        artH(0, 7, 7, K)
        artV(0, 0, 7, K)
    end)
    paint(T.STAIR_R, function()
        artH(0, 7, 0, K)
        artH(0, 5, 1, N) artH(0, 3, 3, N) artH(0, 1, 5, N)
        artH(0, 7, 7, K)
        artV(7, 0, 7, K)
    end)

    paint(T.SIGN_TOP, function()
        artBox(0, 0, 7, 5, BR)
        artV(0, 0, 5, K) artV(7, 0, 5, K) artH(0, 7, 0, K) artH(0, 7, 5, K)
        artP(2, 2, DK) artP(3, 2, DK) artP(4, 3, DK)
    end)
    paint(T.SIGN_BOT, function()
        artBox(3, 0, 4, 7, BR)
        artV(3, 0, 7, K) artV(4, 0, 7, K)
    end)
end

-- ============================================================================
local function genBuildings()
    roofSet(T.ROOF_A_RIDGE, B, K, S, B)        -- dark ceramic
    roofSet(T.ROOF_B_RIDGE, O, C, G, R)        -- red lacquer
    genWalls()
    genStructures()
end
-- ============================================================================
--  nature : trunks, canopies, bamboo, bushes, rocks, vines, statues
-- ============================================================================
local function genNature()
    -- ---- broadleaf trunk ----
    paint(T.TRUNK_TOP, function()
        artV(2, 0, 7, BR) artV(3, 0, 7, BR) artV(4, 0, 7, DK) artV(5, 0, 7, DK)
        artV(1, 0, 7, K) artV(6, 0, 7, K)
        artLine(1, 2, 0, 0, BR) artLine(6, 3, 7, 1, DK)
        artP(4, 2, DK) artP(3, 5, DK)
    end)
    paint(T.TRUNK_MID, function()
        artV(2, 0, 7, BR) artV(3, 0, 7, BR) artV(4, 0, 7, DK) artV(5, 0, 7, DK)
        artV(1, 0, 7, K) artV(6, 0, 7, K)
        artP(3, 2, DK) artP(4, 5, K)
    end)

    -- ---- sakura / maple canopy (2 wide x 3 tall = 6 tiles) ----
    local function canopy(tl, tr, ml, mr, bl, br, cA, cB, cC, seed, blossom)
        paint(tl, function()
            artDisc(6, 5, 5, cA)
            artDisc(3, 3, 3, cB)
            artH(0, 7, 7, cB)
            artDither(0, 0, 7, 7, cB, nil, seed, 34)
            if blossom then artP(2, 2, cC) artP(6, 4, cC) artP(4, 6, cC) end
        end)
        paint(tr, function()
            artDisc(2, 5, 5, cA)
            artDisc(5, 3, 3, cB)
            artDither(0, 0, 7, 7, cB, nil, seed + 3, 34)
            if blossom then artP(3, 4, cC) artP(6, 6, cC) end
        end)
        paint(ml, function()
            artBox(0, 0, 7, 7, cA)
            artDither(0, 0, 7, 7, cB, nil, seed + 1, 30)
            if blossom then artP(2, 3, cC) artP(5, 6, cC) artP(3, 1, cC) end
        end)
        paint(mr, function()
            artBox(0, 0, 7, 7, cA)
            artDither(0, 0, 7, 7, cB, nil, seed + 2, 30)
            if blossom then artP(4, 2, cC) artP(1, 5, cC) end
        end)
        paint(bl, function()
            artDisc(4, 2, 4, cA)
            artH(0, 7, 0, cA)
            artDither(0, 0, 7, 7, cB, nil, seed + 4, 30)
            if blossom then artP(3, 4, cC) artP(6, 1, cC) end
        end)
        paint(br, function()
            artDisc(4, 2, 4, cA)
            artH(0, 7, 0, cA)
            artDither(0, 0, 7, 7, cB, nil, seed + 5, 30)
            artH(0, 7, 6, cC)
            if blossom then artP(5, 3, cC) end
        end)
    end

    canopy(T.CANOPY_TL, T.CANOPY_TR, T.CANOPY_ML, T.CANOPY_MR,
        T.CANOPY_BL, T.CANOPY_BR, J, F, PK, 41, true)

    -- ---- pine ----
    paint(T.PINE_TRUNK, function()
        artV(3, 0, 7, BR) artV(4, 0, 7, DK)
        artV(2, 0, 7, K) artV(5, 0, 7, K)
    end)
    paint(T.PINE_T1, function()          -- top tier (narrow)
        artLine(3, 7, 7, 0, F)
        artLine(4, 7, 0, 0, F)
        artLine(3, 4, 7, 4, J)
        artH(0, 7, 7, K)
        artP(3, 2, G) artP(4, 2, G)
    end)
    paint(T.PINE_T2, function()          -- middle tier
        artLine(3, 0, 7, 7, F)
        artLine(4, 0, 0, 7, F)
        artH(0, 7, 3, J)
        artP(1, 5, F) artP(6, 5, F)
    end)
    paint(T.PINE_T3, function()          -- bottom tier (wide)
        artLine(0, 7, 7, 4, F)
        artLine(0, 4, 3, 7, F)
        artLine(4, 7, 7, 5, F)
        artH(0, 7, 2, J)
        artH(0, 7, 6, K)
    end)

    -- ---- bamboo ----
    paint(T.BAMBOO_L, function()
        artV(0, 0, 7, J) artV(1, 0, 7, J) artV(2, 0, 7, F) artV(3, 0, 7, F)
    end)
    paint(T.BAMBOO_R, function()
        artV(4, 0, 7, J) artV(5, 0, 7, F) artV(6, 0, 7, F)
        artV(7, 0, 7, K)
    end)
    paint(T.BAMBOO_TOP, function()
        artV(2, 0, 7, J) artV(3, 0, 7, F) artV(4, 0, 7, F)
        artH(2, 5, 0, J)
        artP(1, 2, J) artP(6, 2, J) artP(0, 1, F) artP(7, 1, F)
        artLine(1, 0, 5, 3, J) artLine(6, 0, 2, 3, F)
    end)
    paint(T.BAMBOO_LEAF, function()
        artLine(0, 7, 6, 2, J) artLine(1, 7, 7, 3, F)
        artLine(7, 7, 2, 3, J)
        artP(3, 5, J) artP(5, 4, F)
    end)
    paint(T.BAMBOO_CLUSTER, function()
        artV(1, 0, 7, J) artV(5, 0, 7, J) artV(6, 0, 7, F) artV(2, 0, 7, F)
        artP(4, 2, J) artP(0, 5, F) artP(7, 4, F)
    end)

    -- ---- ground clutter ----
    paint(T.BUSH_A, function()
        artDisc(3, 5, 3, J) artDisc(6, 5, 2, F)
        artP(2, 2, J) artP(6, 3, F)
        artH(0, 7, 7, K)
    end)
    paint(T.BUSH_B, function()
        artDisc(2, 6, 2, F) artDisc(5, 5, 3, J)
        artP(4, 2, J) artP(1, 3, F)
        artH(0, 7, 7, K)
    end)
    paint(T.TUFT_A, function()
        artLine(2, 7, 0, 2, J) artLine(3, 7, 3, 1, J) artLine(5, 7, 7, 3, J)
        artP(4, 5, F) artP(1, 6, F)
    end)
    paint(T.TUFT_B, function()
        artLine(4, 7, 1, 4, J) artLine(5, 7, 6, 2, F) artLine(3, 7, 3, 3, J)
    end)
    paint(T.FLOWER_A, function()
        artLine(4, 7, 4, 3, J)
        artP(3, 2, PK) artP(5, 2, PK) artP(4, 1, PK) artP(2, 3, PK) artP(6, 3, PK)
        artP(4, 3, G)
    end)
    paint(T.FLOWER_B, function()
        artLine(3, 7, 3, 4, F) artLine(5, 7, 6, 5, F)
        artP(3, 3, R) artP(4, 2, R) artP(2, 2, R) artP(3, 1, R)
    end)

    paint(T.ROCK_A, function()
        artDisc(3, 6, 2, N) artDisc(5, 6, 1, S)
        artH(1, 6, 7, K) artP(2, 4, K) artP(6, 6, B)
    end)
    paint(T.ROCK_B, function()
        artDisc(4, 6, 3, S) artDisc(3, 5, 1, N)
        artH(1, 7, 7, K) artP(6, 4, B)
    end)
    paint(T.BOULDER_TL, function()
        artDisc(0, 7, 7, S)
        artH(0, 7, 0, K) artV(0, 0, 7, K)
        artP(3, 3, N) artP(1, 5, B)
    end)
    paint(T.BOULDER_TR, function()
        artDisc(7, 7, 7, S)
        artH(0, 7, 0, K) artV(7, 0, 7, K)
        artP(5, 4, B) artP(6, 6, N)
    end)
    paint(T.BOULDER_BL, function()
        artDisc(0, 0, 7, S)
        artH(0, 7, 7, K) artV(0, 0, 7, K)
        artP(3, 4, B) artP(5, 6, N)
    end)
    paint(T.BOULDER_BR, function()
        artDisc(7, 0, 7, S)
        artH(0, 7, 7, K) artV(7, 0, 7, K)
        artP(4, 5, B)
    end)

    paint(T.VINE_A, function()
        artV(3, 0, 7, J) artV(4, 0, 7, F)
        artP(2, 2, J) artP(5, 5, F) artP(2, 6, J)
    end)
    paint(T.VINE_B, function()
        artV(2, 0, 7, F) artV(3, 0, 7, J)
        artP(5, 1, J) artP(1, 4, F)
        artP(4, 7, J)
    end)
    paint(T.LADDER_A, function()
        artV(1, 0, 7, BR) artV(6, 0, 7, BR)
        artH(1, 6, 2, DK) artH(1, 6, 6, DK)
        fset(T.LADDER_A, F_CLIMB, true)
    end)
    paint(T.LADDER_B, function()
        artV(1, 0, 7, BR) artV(6, 0, 7, BR)
        artH(1, 6, 4, DK)
        artV(1, 0, 7, K) artV(6, 0, 7, K)
        fset(T.LADDER_B, F_CLIMB, true)
    end)

    paint(T.JIZO_A, function()
        artH(0, 7, 7, K)
        artBox(2, 5, 5, 6, N)
        artBox(2, 1, 5, 4, N)
        artV(2, 1, 6, K) artV(5, 1, 6, K)
        artH(0, 7, 3, R) artP(3, 2, K) artP(4, 2, K)
    end)
    paint(T.JIZO_B, function()
        artH(0, 7, 7, K)
        artBox(2, 5, 5, 6, S)
        artDisc(3, 2, 2, S)
        artV(2, 1, 6, K) artV(5, 1, 6, K)
        artH(0, 7, 4, R) artP(3, 2, K)
    end)
    paint(T.TOMB_A, function()
        artH(0, 7, 7, K)
        artBox(1, 1, 6, 6, S)
        artV(1, 1, 6, K) artV(6, 1, 6, K) artH(1, 6, 1, K)
        artP(3, 3, B) artP(4, 3, B) artP(3, 4, B)
    end)

    paint(T.MAPLE_A, function()
        artDisc(4, 4, 4, O) artDisc(2, 6, 2, R) artDisc(6, 2, 2, G)
        artH(0, 7, 7, R)
    end)
    paint(T.MAPLE_B, function()
        artDisc(3, 5, 4, R) artDisc(6, 3, 2, O) artDisc(1, 2, 2, G)
        artH(0, 7, 7, C)
    end)
    paint(T.SNOWTREE_A, function()
        artDisc(4, 4, 4, N) artDisc(2, 6, 2, W) artDisc(6, 2, 2, S)
        artH(0, 7, 7, S)
    end)
    paint(T.SNOWTREE_B, function()
        artDisc(3, 5, 4, W) artDisc(6, 3, 2, N) artDisc(1, 2, 2, S)
        artH(0, 7, 7, B)
    end)
end

-- ============================================================================
--  misc: chests, pottery, spikes, cloud platforms, bridges, floors
-- ============================================================================
local function genMisc()
    paint(T.CHEST_CLOSED, function()
        artBox(1, 3, 6, 7, BR)
        artBox(1, 1, 6, 2, DK)
        artH(1, 6, 3, G) artP(3, 5, G) artP(4, 5, G) artP(3, 4, G)
        artH(0, 7, 7, K) artV(0, 1, 7, K) artV(7, 1, 7, K) artH(0, 7, 1, K)
    end)
    paint(T.CHEST_OPEN, function()
        artBox(1, 4, 6, 7, BR)
        artBox(1, 0, 6, 1, DK)
        artH(1, 6, 4, G)
        artP(2, 2, W) artP(4, 2, W) artP(3, 3, G)
        artH(0, 7, 7, K) artV(0, 0, 7, K) artV(7, 0, 7, K) artH(0, 7, 0, K)
    end)

    paint(T.POT, function()
        artDisc(3, 5, 3, BR)
        artH(2, 5, 2, DK) artH(1, 7, 7, K) artP(2, 4, DK)
        artH(2, 5, 1, DK)
    end)
    paint(T.BARREL, function()
        artBox(1, 1, 6, 7, BR)
        artH(1, 6, 2, K) artH(1, 6, 6, K)
        artV(1, 1, 7, K) artV(6, 1, 7, K) artH(1, 6, 7, K)
        artP(3, 4, DK)
    end)
    paint(T.CRATE, function()
        artBox(0, 0, 7, 7, BR)
        artRect(0, 0, 7, 7, K)
        artLine(1, 1, 6, 6, DK) artLine(6, 1, 1, 6, DK)
        artP(3, 3, G) artP(4, 4, G)
    end)

    paint(T.SPIKES, function()
        for x = 0, 7, 4 do
            artLine(x, 7, x + 2, 2, N)
            artLine(x + 1, 7, x + 4, 2, S)
        end
        artH(0, 7, 7, K)
        fset(T.SPIKES, F_HAZARD, true)
    end)
    paint(T.SPIKE_BASE, function()
        artBox(0, 4, 7, 7, S)
        artH(0, 7, 4, N) artH(0, 7, 7, K)
        artP(2, 6, B) artP(5, 6, B)
        fset(T.SPIKE_BASE, F_SOLID, true) fset(T.SPIKE_BASE, F_HAZARD, true)
    end)

    paint(T.CLOUD_L, function()
        artDisc(2, 5, 3, N) artDisc(5, 6, 2, W)
        artH(0, 7, 7, W) artH(0, 7, 0, W)
        artP(0, 3, W) artP(3, 2, W)
    end)
    paint(T.CLOUD_R, function()
        artDisc(5, 5, 3, N) artDisc(2, 6, 2, W)
        artH(0, 7, 7, W) artH(0, 7, 0, W)
        artP(7, 3, W) artP(4, 2, W)
    end)
    paint(T.ISLAND_EDGE, function()
        artH(0, 7, 0, N)
        artLine(0, 1, 3, 7, BR) artLine(7, 1, 4, 7, DK)
        artH(4, 4, 7, K)
        artP(2, 3, S) artP(5, 4, DK)
    end)

    paint(T.BRIDGE_A, function()
        artH(0, 7, 0, BR) artH(0, 7, 1, DK)
        artH(0, 7, 2, BR) artH(0, 7, 3, DK)
        artV(1, 0, 3, K) artV(5, 0, 3, K)
        artP(3, 1, DK)
    end)
    paint(T.BRIDGE_B, function()
        artH(0, 7, 0, BR) artH(0, 7, 1, DK)
        artH(0, 7, 2, BR) artH(0, 7, 3, DK)
        artV(2, 0, 3, K) artV(6, 0, 3, K)
        artP(4, 2, DK)
    end)

    local function floor(cBody, cDark, cLight, seed)
        woodH(cBody, cDark, seed)
        artH(0, 7, 0, cLight)
        artH(0, 7, 7, K)
        artP(1, 3, cDark) artP(5, 5, cDark)
    end
    paint(T.FLOOR_WOOD, function() floor(BR, DK, G, 3) end)
    paint(T.FLOOR_WOOD_L, function() floor(BR, DK, G, 4) artV(0, 0, 7, K) end)
    paint(T.FLOOR_WOOD_R, function() floor(BR, DK, G, 6) artV(7, 0, 7, K) end)
    paint(T.FLOOR_STONE, function()
        artBox(0, 0, 7, 7, B)
        artDither(0, 0, 7, 7, K, nil, 12, 12)
        artH(0, 7, 0, N) artH(0, 7, 7, K)
    end)
    paint(T.FLOOR_STONE_L, function()
        artBox(0, 0, 7, 7, B)
        artDither(0, 0, 7, 7, K, nil, 14, 12)
        artH(0, 7, 0, N) artV(0, 0, 7, K)
    end)
    paint(T.FLOOR_STONE_R, function()
        artBox(0, 0, 7, 7, B)
        artDither(0, 0, 7, 7, K, nil, 16, 12)
        artH(0, 7, 0, N) artV(7, 0, 7, K)
    end)
end

-- ============================================================================
genProps = function()
    genBuildings()
    genNature()
    genMisc()
end

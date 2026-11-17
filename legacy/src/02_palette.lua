-- ============================================================================
--  02 - PALETTE
--
--  TIC-80 stores the 16 colours as RGB triplets in RAM at 0x3FC0. This build
--  has no pal()/palt() helper, so we poke them directly. There are two palette
--  banks (one per sprite bank); we write both so bank-1 art matches bank-0 art.
--
--  The palette is an indigo / vermilion / gold / sakura scheme - the colours of
--  a woodblock print of a Japanese summer evening.
--
--   0 VOID    ink-dark, also the sprite transparency key
--   1 INK     outlines
--   2 BLUE    sky high, water deep, mountain stone, night
--   3 SKY     sky low, water light, ice highlight
--   4 BONE    washi paper, snow, light stone, light skin
--   5 WHITE   sun, sparkle, eyes
--   6 GOLD    lanterns, temple trim, sand, straw
--   7 ORANGE  autumn leaves, fire, roof tiles, fox
--   8 RED     torii, lacquer, oni skin
--   9 CRIMSON dark red, blood, shadow of red
--  10 JADE    foliage, bamboo
--  11 FOREST  foliage shadow
--  12 PINK    sakura blossom
--  13 VIOLET  magic, twilight, yokai
--  14 BROWN   wood, earth
--  15 DARK    wood/earth shadow
-- ============================================================================

-- short names used by the art tables and by the renderer
local V, K, B, S, N, W, G, O, R, C, J, F, PK, VI, BR, DK =
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15

-- ---------------------------------------------------------------------------
-- Lua allows only 200 local variables per function, and the main chunk of a
-- TIC-80 cart IS one function. The atlas modules (palette, art, terrain,
-- props, characters) together need far more than that, so they live inside
-- buildArt() and their locals never touch the chunk budget. Only these
-- handles are hoisted out, because later modules need them.
-- ---------------------------------------------------------------------------
local T, BIOME = {}, {}
local genTerrain, genProps, genChars, blk16
local isTerrain
local palApply, palSetTint, palUpdateTint
local PF, EF

local function buildArt()

local PAL_RGB = {
    0x0D0B14, 0x241E38, 0x3D5C8F, 0x79B8D6,
    0xF2E9D8, 0xFFFFFF, 0xC9A227, 0xE0763A,
    0xC0392B, 0x7A1C24, 0x4E9A5C, 0x24512C,
    0xE8A0B4, 0x6E4A94, 0x8A5A3B, 0x4A2C1B,
}

local PAL_ADDR = 0x3FC0

-- write the 16 RGB triplets of one palette bank
local function palWrite()
    local a = PAL_ADDR
    for i = 1, 16 do
        local c = PAL_RGB[i]
        poke(a, flr(c / 65536) % 256)
        poke(a + 1, flr(c / 256) % 256)
        poke(a + 2, c % 256)
        a = a + 3
    end
end

-- Apply to both palette banks, preserving the caller's active bank.
local function palWriteBanks()
    local prev = vbank(0)
    palWrite()
    vbank(1)
    palWrite()
    vbank(prev)
end

palApply = function()
    palWriteBanks()
end

-- ---- terrain / region tinting -------------------------------------------------
-- Some regions shift the whole palette for mood (dusk, snow haze, volcanic air).
-- Each entry is a per-index multiplier applied on top of PAL_RGB.
local TINTS = {
    none = nil,
    dusk = { [2] = 0.80, [3] = 0.85, [10] = 0.80, [11] = 0.80, [12] = 1.00 },
    cold = { [2] = 0.90, [10] = 0.70, [11] = 0.70, [6] = 0.95 },
    ash = { [2] = 0.70, [10] = 0.70, [11] = 0.70, [3] = 0.80, [4] = 0.92 },
    night = { [2] = 0.55, [3] = 0.60, [4] = 0.75, [10] = 0.55, [11] = 0.55, [14] = 0.7, [15] = 0.7 },
}

local curTint = "none"
local tintBlend = 0   -- 0..1 blend toward curTint
local TINT_STEP = 0.08

palSetTint = function(name) curTint = name or "none" end

-- Recompute the live palette as PAL_RGB blended toward the active tint.
-- Both banks must receive the same live palette because sprites and map art
-- can be selected independently.  vbank() returns the previous bank, so save
-- it before switching and restore it even when the caller is on either bank.
local function palWriteTint()
    local t = TINTS[curTint]
    local a = PAL_ADDR
    for i = 1, 16 do
        local c = PAL_RGB[i]
        local r, g, b = flr(c / 65536) % 256, flr(c / 256) % 256, c % 256
        local m = t and t[i]
        if m then
            local k = 1 - (1 - m) * tintBlend
            r, g, b = flr(r * k), flr(g * k), flr(b * k)
        end
        poke(a, r) poke(a + 1, g) poke(a + 2, b)
        a = a + 3
    end
end

palUpdateTint = function()
    local t = TINTS[curTint]
    if t then
        tintBlend = min(1, tintBlend + TINT_STEP)
    else
        tintBlend = max(0, tintBlend - TINT_STEP)
    end
    local prev = vbank(0)
    palWriteTint()
    vbank(1)
    palWriteTint()
    vbank(prev)
end

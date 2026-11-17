-- title:   KAGE - Ninja of the Wind
-- author:  Sixth
-- desc:    2.5D open-world ninja platformer in a fantasy anime Japan
-- site:    https://tic80.com
-- license: MIT
-- version: 1.0
-- script:  lua
--
-- ============================================================================
--  KAGE - Ninja of the Wind  (TIC-80 Pro 1.3 / Lua)
--
--  A 2.5D side-scrolling action-platformer set in a fantasy anime Japan.
--  Open world built from 8 regions + sky islands + a deep underworld,
--  drawn with layered parallax depth, pseudo-3D terrain blocks, depth-sorted
--  entities and drop shadows.
--
--  CONTROLS
--    Left/Right .......... run
--    Down ................ crouch / slide
--    Z (or A) ............ jump  (hold for higher, tap again = double jump)
--    X (or S) ............ katana slash  (air slash while airborne)
--    Up + X .............. throw kunai
--    Down + Z (in air) ... air dash (once per airtime)
--    Up (at shrine) ...... rest / save / fast travel
--
--  SOURCE LAYOUT
--    This cart is generated: tools/build.sh concatenates src/*.lua in
--    lexical order into ../kage.lua (the playable cartridge).
--    Every module below is a self-contained section. Because the modules are
--    concatenated into ONE Lua chunk, chunk-level locals declared in
--    01_core.lua are visible to every later module.
-- ============================================================================

-- ============================================================================
--  01 - CORE : constants, math, deterministic RNG, utilities, input
-- ============================================================================

-- ---- display / world geometry ---------------------------------------------
local SCREEN_W, SCREEN_H = 240, 136
local TS = 8                          -- tile size in pixels
local MAP_W, MAP_H = 240, 136         -- tile map dimensions (TIC-80 max)
local WORLD_W, WORLD_H = MAP_W * TS, MAP_H * TS

-- ---- physics tuning (units: pixels / frame @60fps) -------------------------
local GRAVITY = 0.30
local GRAVITY_APEX = 0.16             -- reduced gravity near jump apex
local MAX_FALL = 4.4
local RUN_ACCEL = 0.34
local RUN_MAX = 1.55
local RUN_FRICTION = 0.42
local AIR_ACCEL = 0.22
local JUMP_VEL = -4.05
local DOUBLE_JUMP_VEL = -3.55
local DASH_SPEED = 4.0
local COYOTE_TICKS = 7
local JUMP_BUFFER_TICKS = 7

-- ---- tile collision flags (see fset/fget) ---------------------------------
local F_SOLID = 0
local F_ONEWAY = 1
local F_WATER = 2
local F_HAZARD = 3
local F_CLIMB = 4
local F_BREAK = 5
local F_DECO = 6
local F_SLOPE = 7

-- ---- math -----------------------------------------------------------------
local flr, ceil, abs, sqrt = math.floor, math.ceil, math.abs, math.sqrt
local sin, cos, atan = math.sin, math.cos, math.atan
local min, max, fmod = math.min, math.max, math.fmod
local PI = math.pi
local TAU = PI * 2
local INV60 = 1 / 60

local function sgn(v) if v > 0 then return 1 elseif v < 0 then return -1 end return 0 end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function lerp(a, b, t) return a + (b - a) * t end
local function mid(a, b, c) return max(min(a, b), min(max(a, b), c)) end
-- move v toward target by at most step
local function approach(v, target, step)
    if v < target then return min(v + step, target) end
    return max(v - step, target)
end
local function dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end
local function dist2(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return dx * dx + dy * dy end
local function sign2(v) return v >= 0 and 1 or -1 end
-- wrap v into [0,m)
local function wrap(v, m) v = fmod(v, m) if v < 0 then v = v + m end return v end
-- smoothstep-ish ease
local function ease(t) t = clamp(t, 0, 1) return t * t * (3 - 2 * t) end

-- ---- deterministic RNG (does not rely on math.randomseed) ------------------
local rngS = 1
local function rngSeed(s) rngS = (s % 2147483647) if rngS <= 0 then rngS = rngS + 2147483646 end end
local function rngRaw()                       -- xorshift-ish LCG, 64-bit safe
    rngS = (rngS * 1103515245 + 12345) % 2147483647
    return rngS
end
local function rngF() return rngRaw() / 2147483647 end                  -- [0,1)
local function rngI(n) return rngRaw() % n end                          -- [0,n)
local function rngR(a, b) return a + (rngRaw() / 2147483647) * (b - a) end
local function rngPick(t) return t[1 + rngRaw() % #t] end
local function rngChance(p) return (rngRaw() / 2147483647) < p end

-- ---- misc helpers ---------------------------------------------------------
local function blit16Index(n) return n end -- placeholder for readability

-- cheap string repeat for HUD separators
local function rep(s, n) return string.rep(s, n) end

-- draw a 16x16 sprite (4 consecutive 8x8 tiles in a 2x2 block)
-- idx must be the top-left tile index of the block
local function spr16(idx, x, y, key)
    spr(idx, x, y, key, 1, 0, 0, 2, 2)
end

-- ============================================================================
--  INPUT
--  Held states plus one-frame "pressed" edges and a few ticks of buffering
--  (buffering is what makes platformer jumps feel responsive).
-- ============================================================================
local Input = {
    x = 0, y = 0,          -- -1..1
    left = false, right = false, up = false, down = false,
    jumpHeld = false, atkHeld = false,
    jump = false,          -- pressed this frame
    atk = false,
    jumpBuf = 0, atkBuf = 0,
    any = false,
}

-- Action buttons: jump = Z (4) / A (6), attack = X (5) / S (7).
local function btnJump() return btn(4) or btn(6) end
local function btnAtk() return btn(5) or btn(7) end

local function inputUpdate()
    local l, r = btn(0), btn(1)
    Input.left, Input.right = l, r
    Input.up, Input.down = btn(2), btn(3)
    Input.x = (r and 1 or 0) - (l and 1 or 0)

    local j = btnJump()
    Input.jump = j and not Input.jumpHeld
    Input.jumpHeld = j
    local a = btnAtk()
    Input.atk = a and not Input.atkHeld
    Input.atkHeld = a

    if Input.jump then Input.jumpBuf = JUMP_BUFFER_TICKS
    elseif Input.jumpBuf > 0 then Input.jumpBuf = Input.jumpBuf - 1 end
    if Input.atk then Input.atkBuf = JUMP_BUFFER_TICKS
    elseif Input.atkBuf > 0 then Input.atkBuf = Input.atkBuf - 1 end

    Input.any = Input.jump or Input.atk or l or r or Input.up or Input.down
end
local function inputConsumeJump() Input.jumpBuf = 0 end
local function inputConsumeAtk() Input.atkBuf = 0 end

-- ---- global tick counter ---------------------------------------------------
local Frame = 0
local function ticks() return Frame end
local function secs() return Frame * INV60 end

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

-- ============================================================================
--  03 - ART : procedural pixel painter + sprite atlas layout
--
--  All cartridge art is painted into the sprite sheet at boot. Two 8K banks:
--
--    bank 0  sprite   0..255   nibble base 0x8000   world tiles + parallax
--    bank 1  sprite 256..511   nibble base 0xC000   characters, items, UI
--
--  Sprite n pixel (x,y) lives at nibble  base + n*64 + y*8 + x  (linear 4bpp,
--  two pixels per byte, low nibble first). Verified against the TIC-80 source.
--
--  A "canvas" is either one 8x8 sprite or a 2x2 block of sprites (16x16). The
--  sheet is 16 sprites wide, so a 16x16 block at index n covers n, n+1, n+16,
--  n+17 - which is exactly what spr(n,x,y,key,1,0,0,2,2) draws.
-- ============================================================================

local NIB_BANK0 = 0x8000
local NIB_BANK1 = 0xC000

local Art = {}

-- ---- canvas state ----------------------------------------------------------
local cvNib = NIB_BANK0   -- nibble address of the canvas top-left sprite
local cvW = 8             -- 8 or 16

local function bankBaseOf(idx) return idx >= 256 and NIB_BANK1 or NIB_BANK0 end

-- begin painting on the 8x8 sprite `idx` (0..511)
local function artBegin8(idx)
    cvNib = bankBaseOf(idx) + (idx % 256) * 64
    cvW = 8
end

-- begin painting on the 16x16 block whose top-left sprite is `idx`
-- (idx must be even in x, i.e. idx % 16 <= 14)
local function artBegin16(idx)
    cvNib = bankBaseOf(idx) + (idx % 256) * 64
    cvW = 16
end

-- A 16x16 block sits on a 2x2 group of sprites: n, n+1, n+16, n+17 (the sheet
-- is 16 sprites wide). So blocks tile horizontally with a stride of 2, and only
-- 8 blocks fit per row-pair - after that we must skip two sprite rows.
-- blk16(base, k) is THE single source of truth for where block k lives, used by
-- both the atlas painters and the renderer.
blk16 = function(base, k)
    local r = flr(k / 8)
    local c = k - r * 8
    return base + r * 32 + c * 2
end

-- pixel plot on the current canvas; clipped to the canvas
local function artP(x, y, c)
    if x < 0 or y < 0 or x >= cvW or y >= cvW then return end
    if cvW == 8 then
        poke4(cvNib + y * 8 + x, c)
    else
        local sx = (x >= 8) and 1 or 0
        local sy = (y >= 8) and 16 or 0
        poke4(cvNib + (sx + sy) * 64 + (y % 8) * 8 + (x % 8), c)
    end
end

-- read a pixel of the current canvas (used by shading passes)
local function artG(x, y)
    if x < 0 or y < 0 or x >= cvW or y >= cvW then return -1 end
    if cvW == 8 then return peek4(cvNib + y * 8 + x) end
    local sx = (x >= 8) and 1 or 0
    local sy = (y >= 8) and 16 or 0
    return peek4(cvNib + (sx + sy) * 64 + (y % 8) * 8 + (x % 8))
end

local function artClear(c)
    c = c or V
    for y = 0, cvW - 1 do for x = 0, cvW - 1 do artP(x, y, c) end end
end

local function artH(x0, x1, y, c) for x = x0, x1 do artP(x, y, c) end end
local function artV(x, y0, y1, c) for y = y0, y1 do artP(x, y, c) end end
local function artBox(x0, y0, x1, y1, c)
    for y = y0, y1 do for x = x0, x1 do artP(x, y, c) end end
end
-- rectangle outline
local function artRect(x0, y0, x1, y1, c)
    artH(x0, x1, y0, c) artH(x0, x1, y1, c)
    artV(x0, y0, y1, c) artV(x1, y0, y1, c)
end
-- 1px ink outline around the bounding box
local function artOutline(x0, y0, x1, y1, c)
    artRect(x0 - 1, y0 - 1, x1 + 1, y1 + 1, c or K)
end

local function artLine(x0, y0, x1, y1, c)
    local dx, dy = abs(x1 - x0), abs(y1 - y0)
    local sx, sy = sign2(x1 - x0), sign2(y1 - y0)
    local err = dx - dy
    while true do
        artP(x0, y0, c)
        if x0 == x1 and y0 == y1 then break end
        local e2 = err * 2
        if e2 > -dy then err = err - dy x0 = x0 + sx end
        if e2 < dx then err = err + dx y0 = y0 + sy end
    end
end

local function artDisc(cx, cy, r, c)
    for y = -r, r do
        local w = flr(sqrt(r * r - y * y) + 0.35)
        artH(cx - w, cx + w, cy + y, c)
    end
end

local function artRing(cx, cy, r, c)
    local steps = 8 + r * 4
    for i = 0, steps - 1 do
        local a = (i / steps) * TAU
        artP(cx + flr(cos(a) * r + 0.5), cy + flr(sin(a) * r + 0.5), c)
    end
end

-- deterministic per-pixel noise, handy for stone / soil / foliage grain
local function artNoise(x, y, seed) return (x * 73856093 + y * 19349663 + seed * 83492791) % 100 end

-- speckle a region: returns a colour picker used by the shape helpers
local function artDither(x0, y0, x1, y1, cOn, cOff, seed, thresh)
    thresh = thresh or 50
    for y = y0, y1 do
        for x = x0, x1 do
            if artNoise(x, y, seed) < thresh then artP(x, y, cOn) elseif cOff then artP(x, y, cOff) end
        end
    end
end

-- replace every pixel of colour `from` with `to` on the current canvas
local function artSwap(from, to)
    for y = 0, cvW - 1 do
        for x = 0, cvW - 1 do
            if artG(x, y) == from then artP(x, y, to) end
        end
    end
end

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

-- ============================================================================
--  06 - CHARACTERS (bank 1 : sprite 256..)
--
--  16x16 characters painted with a "silhouette then fill" helper: every part is
--  first drawn one pixel larger in the outline colour, then filled. That gives
--  clean automatic outlines without hand plotting them.
--
--  Atlas plan
--    256..319  player   (16 frames, 4 sprites each)
--    320..415  enemies  (6 types x 4 frames)
--    416..447  boss     (8 frames)
--    448..511  items, projectiles, HUD
-- ============================================================================

-- ninja palette
local C_OUT, C_GI, C_GI_HI = V, K, B
local C_SASH, C_SCARF, C_SKIN = G, R, N
local C_EYE, C_BLADE, C_POM = S, N, G

-- ---- primitives with automatic outline --------------------------------------
local function part(x0, y0, x1, y1, c)
    artBox(x0 - 1, y0 - 1, x1 + 1, y1 + 1, C_OUT)
    artBox(x0, y0, x1, y1, c)
end

local function partSoft(cx, cy, r, c)
    artDisc(cx, cy, r + 1, C_OUT)
    artDisc(cx, cy, r, c)
end

-- ---- shared body pieces -----------------------------------------------------
-- head: hood with a glowing eye slit; face = 1 for right, -1 for left
local function ninjaHead(hx, hy, face)
    partSoft(hx, hy, 3, C_GI)
    -- top highlight
    artP(hx - 1, hy - 3, C_GI_HI) artP(hx, hy - 3, C_GI_HI) artP(hx + 1, hy - 3, C_GI_HI)
    -- eye slit, kept inside the hood so the visor reads at 16px
    if face > 0 then
        artH(hx + 1, hx + 2, hy, C_EYE)
        artP(hx + 3, hy, C_OUT)
        artH(hx + 1, hx + 3, hy + 1, C_OUT)
    else
        artH(hx - 2, hx - 1, hy, C_EYE)
        artP(hx - 3, hy, C_OUT)
        artH(hx - 3, hx - 1, hy + 1, C_OUT)
    end
    -- headband knot
    artP(hx - face * 3, hy - 2, C_SCARF)
    artP(hx - face * 4, hy - 1, C_SCARF)
end

-- torso with sash; widened a pixel each side so the body reads beside the hood
local function ninjaTorso(x0, y0, x1, y1)
    x0, x1 = x0 - 1, x1 + 1
    part(x0, y0, x1, y1, C_GI)
    artV(x0, y0, y1, C_GI_HI)          -- lit left facet
    artV(x0 + 1, y0, y1, C_GI)
    artH(x0, x1, y1 - 1, C_SASH)       -- sash
end

-- a limb: simple outlined bar
local function limb(x0, y0, x1, y1, c)
    part(x0, y0, x1, y1, c or C_GI)
end

-- trailing scarf: f = 0..7 length, d = 1 right / -1 left
local function scarf(x, y, f, d, ph)
    local c = C_SCARF
    local len = 3 + f
    for i = 1, len do
        local yy = y + flr(sin((ph + i) * 0.7) * 1.6) - flr(i * 0.35)
        artP(x + d * i, yy, c)
        if i < len - 1 then artP(x + d * i, yy + 1, C_OUT) end
    end
end

-- katana: drawn from a grip point at an angle
local function katana(gx, gy, dx, dy, len)
    for i = 2, len do
        local x, y = gx + dx * i, gy + dy * i
        artP(x, y, C_OUT) artP(x, y - 1, C_BLADE)
    end
    artP(gx, gy, C_POM) artP(gx + dx, gy + dy, C_SASH)
end
-- ============================================================================
--  PLAYER - 16 frames of 16x16, drawn facing right (the renderer mirrors them)
-- ============================================================================

-- sheathed katana worn across the back
local function katanaBack(flat)
    artLine(4, 11, 11, 4, C_OUT)
    artLine(5, 11, 12, 4, C_BLADE)
    if flat then artH(4, 5, 11, C_SASH) end
end

-- legs: (fx,fy) far foot, (nx,ny) near foot, knee height
local function legs(fx, fy, nx, ny, kx0, kx1)
    artBox(6, 11, 7, fy, C_OUT) artBox(6, 12, 7, fy, C_GI)
    artBox(nx, 11, nx + 1, ny, C_OUT) artBox(nx, 12, nx + 1, ny, C_GI)
    artH(fx - 1, kx0, fy + 1, C_OUT)
    artH(nx - 1, kx1, ny + 1, C_OUT)
end

local function drawPlayer(f, ph)
    artBegin16(blk16(256, f))
    artClear(V)

    if f == 0 then                     -- ---------- idle ----------
        scarf(5, 6, 0, -1, ph)
        katanaBack()
        limb(5, 8, 5, 11)
        legs(6, 14, 9, 14, 5, 8)
        ninjaTorso(6, 7, 10, 11)
        ninjaHead(8, 4, 1)
        limb(11, 8, 11, 11)

    elseif f == 1 then                 -- ---------- run 1 ----------
        scarf(5, 6, 2, -1, ph)
        katanaBack()
        limb(7, 8, 5, 10)
        artBox(5, 11, 6, 14, C_OUT) artBox(5, 12, 6, 14, C_GI)
        ninjaTorso(7, 7, 11, 11)
        artBox(9, 11, 10, 13, C_OUT) artBox(9, 12, 10, 13, C_GI)
        artH(9, 10, 14, C_OUT)
        ninjaHead(9, 4, 1)
        limb(12, 8, 11, 10)

    elseif f == 2 then                 -- ---------- run 2 ----------
        scarf(5, 6, 3, -1, ph)
        katanaBack()
        limb(6, 9, 6, 11)
        artBox(8, 11, 9, 14, C_OUT) artBox(8, 12, 9, 14, C_GI)
        ninjaTorso(7, 7, 11, 11)
        artBox(6, 11, 7, 13, C_OUT) artBox(6, 12, 7, 13, C_GI)
        artH(5, 7, 14, C_OUT)
        ninjaHead(9, 4, 1)
        limb(12, 9, 12, 11)

    elseif f == 3 then                 -- ---------- run 3 ----------
        scarf(5, 6, 2, -1, ph)
        katanaBack()
        limb(7, 8, 5, 10)
        artBox(5, 11, 6, 13, C_OUT) artBox(5, 12, 6, 13, C_GI)
        ninjaTorso(7, 7, 11, 11)
        artBox(9, 11, 10, 14, C_OUT) artBox(9, 12, 10, 14, C_GI)
        artH(9, 10, 15, C_OUT)
        ninjaHead(9, 4, 1)
        limb(12, 8, 11, 10)

    elseif f == 4 then                 -- ---------- run 4 ----------
        scarf(5, 6, 3, -1, ph)
        katanaBack()
        limb(6, 8, 5, 11)
        artBox(7, 11, 8, 14, C_OUT) artBox(7, 12, 8, 14, C_GI)
        ninjaTorso(7, 7, 11, 11)
        artBox(10, 11, 11, 13, C_OUT) artBox(10, 12, 11, 13, C_GI)
        ninjaHead(9, 4, 1)
        limb(12, 8, 12, 10)

    elseif f == 5 then                 -- ---------- jump ----------
        scarf(5, 6, 5, -1, ph)
        katanaBack()
        limb(5, 7, 4, 9)               -- arms up
        limb(11, 7, 12, 9)
        artBox(6, 11, 7, 13, C_OUT) artBox(6, 12, 7, 13, C_GI)
        artBox(9, 11, 10, 13, C_OUT) artBox(9, 12, 10, 13, C_GI)
        ninjaTorso(6, 7, 10, 11)
        artH(5, 7, 14, C_OUT) artH(9, 11, 14, C_OUT)
        ninjaHead(8, 4, 1)

    elseif f == 6 then                 -- ---------- fall ----------
        scarf(5, 6, 4, -1, ph)
        katanaBack()
        limb(4, 8, 3, 10)
        limb(12, 8, 13, 10)
        artBox(5, 11, 6, 12, C_OUT) artBox(5, 12, 6, 12, C_GI)
        artBox(10, 11, 11, 12, C_OUT) artBox(10, 12, 11, 12, C_GI)
        ninjaTorso(6, 7, 10, 11)
        artH(4, 7, 13, C_OUT) artH(9, 11, 13, C_OUT)
        ninjaHead(8, 4, 1)

    elseif f == 7 then                 -- ---------- slash 1 (overhead) ----------
        scarf(5, 6, 3, -1, ph)
        limb(5, 9, 3, 11)
        legs(6, 14, 9, 14, 5, 8)
        ninjaTorso(6, 7, 10, 11)
        katana(10, 8, 1, -1, 7)        -- blade sweeping up-right
        limb(11, 7, 12, 9)
        ninjaHead(8, 4, 1)

    elseif f == 8 then                 -- ---------- slash 2 (horizontal) ----------
        scarf(5, 7, 4, -1, ph)
        limb(5, 9, 3, 10)
        legs(6, 14, 9, 14, 5, 8)
        ninjaTorso(7, 7, 11, 11)
        katana(10, 9, 1, 0, 5)
        limb(11, 9, 12, 10)
        ninjaHead(9, 4, 1)

    elseif f == 9 then                 -- ---------- dash ----------
        scarf(4, 7, 6, -1, ph)
        katanaBack(true)
        artBox(4, 8, 7, 9, C_OUT) artBox(4, 8, 7, 9, C_GI)
        artBox(10, 8, 12, 9, C_OUT) artBox(10, 8, 12, 9, C_GI)
        ninjaTorso(5, 7, 10, 10)
        artH(3, 7, 11, C_OUT) artH(10, 13, 11, C_OUT)
        ninjaHead(7, 5, 1)

    elseif f == 10 then                -- ---------- wall slide ----------
        scarf(5, 8, 2, -1, ph)
        katanaBack()
        limb(3, 7, 4, 10)
        artBox(5, 11, 6, 14, C_OUT) artBox(5, 12, 6, 14, C_GI)
        artBox(8, 11, 9, 13, C_OUT) artBox(8, 12, 9, 13, C_GI)
        ninjaTorso(5, 7, 9, 11)
        ninjaHead(7, 4, -1)
        limb(10, 7, 9, 9)

    elseif f == 11 then                -- ---------- crouch ----------
        scarf(5, 9, 1, -1, ph)
        katanaBack(true)
        artBox(5, 12, 7, 14, C_OUT) artBox(5, 12, 7, 14, C_GI)
        artBox(9, 12, 11, 14, C_OUT) artBox(9, 12, 11, 14, C_GI)
        ninjaTorso(6, 9, 10, 12)
        ninjaHead(8, 6, 1)
        limb(11, 9, 10, 11)

    elseif f == 12 then                -- ---------- hurt ----------
        scarf(4, 5, 4, -1, ph)
        katanaBack()
        limb(4, 8, 2, 9)
        artBox(5, 11, 6, 14, C_OUT) artBox(5, 12, 6, 14, C_GI)
        artBox(10, 11, 11, 13, C_OUT) artBox(10, 12, 11, 13, C_GI)
        ninjaTorso(6, 7, 10, 11)
        ninjaHead(7, 4, -1)
        limb(11, 8, 12, 10)

    elseif f == 13 then                -- ---------- throw kunai ----------
        scarf(5, 6, 3, -1, ph)
        katanaBack()
        legs(6, 14, 9, 14, 5, 8)
        ninjaTorso(6, 7, 10, 11)
        ninjaHead(8, 4, 1)
        limb(11, 7, 14, 7)             -- extended throwing arm
        artP(15, 7, C_BLADE) artP(14, 6, C_BLADE)

    elseif f == 14 then                -- ---------- land ----------
        scarf(5, 8, 1, -1, ph)
        katanaBack(true)
        artBox(4, 12, 6, 14, C_OUT) artBox(4, 12, 6, 14, C_GI)
        artBox(9, 12, 11, 14, C_OUT) artBox(9, 12, 11, 14, C_GI)
        ninjaTorso(6, 8, 10, 12)
        ninjaHead(8, 5, 1)
        limb(11, 8, 10, 11)

    else                               -- ---------- f15 : power / victory ----------
        scarf(5, 5, 5, -1, ph)
        katanaBack(true)
        limb(5, 8, 4, 10)
        legs(6, 14, 9, 14, 5, 8)
        ninjaTorso(6, 7, 10, 11)
        ninjaHead(8, 4, 1)
        artLine(11, 6, 13, 2, C_BLADE) -- blade raised
        artLine(11, 6, 13, 2, C_OUT)
        limb(11, 8, 12, 10)
    end
end
-- ============================================================================
--  ENEMIES - 6 types, 4 frames each, 16x16, at 320 + (type-1)*16 + f*4
-- ============================================================================
-- Each enemy type owns one row-pair (8 blocks): 4 frames sit in the even
-- columns of the pair. Type t base = EB + (t-1)*8.
local EB = 320

-- ---- 1. ONI : red ogre with a kanabo club ----------------------------------
local function drawOni(f)
    artBegin16(blk16(EB + 0 * 8, f))
    artClear(V)
    local legY = 15

    -- legs
    artBox(4, 11, 6, legY, C_OUT) artBox(4, 11, 6, legY, R)
    artBox(9, 11, 11, legY, C_OUT) artBox(9, 11, 11, legY, R)
    if f == 1 then artBox(3, 11, 5, legY, C_OUT) artBox(3, 12, 5, legY, R) end
    if f == 2 then artBox(10, 11, 12, legY, C_OUT) artBox(10, 12, 12, legY, R) end

    -- tiger loincloth
    artH(3, 12, 10, C_OUT) artH(3, 12, 10, G)
    artP(5, 10, O) artP(8, 10, O)

    -- body
    artBox(3, 5, 12, 10, C_OUT) artBox(4, 6, 11, 10, R)
    artV(4, 6, 10, O)                      -- lit left
    artV(11, 6, 10, C)

    -- arms
    artBox(1, 6, 3, 10, C_OUT) artBox(1, 6, 3, 10, R)
    artBox(12, 6, 14, 10, C_OUT) artBox(12, 6, 14, 10, R)

    -- head
    partSoft(8, 4, 3, R)
    artH(5, 11, 3, C_OUT)
    artP(6, 3, W) artP(9, 3, W)            -- eyes
    artP(7, 4, K) artP(8, 4, K)
    artH(6, 9, 6, W) artP(7, 6, K)         -- tusks
    -- horns
    artLine(5, 1, 3, 0, C_OUT) artLine(5, 1, 4, 0, N)
    artLine(10, 1, 12, 0, C_OUT) artLine(10, 1, 11, 0, N)
    artP(5, 0, N) artP(11, 0, N)

    -- kanabo club
    if f == 3 then
        artLine(12, 6, 14, 2, C_OUT) artLine(12, 6, 14, 3, BR)
        artP(13, 2, DK) artP(14, 2, DK) artP(12, 2, DK)
    else
        artLine(13, 10, 14, 4, C_OUT) artLine(13, 10, 14, 5, BR)
        artP(14, 3, DK) artP(13, 3, DK)
    end
end

-- ---- 2. TENGU : crow goblin with a long nose --------------------------------
local function drawTengu(f)
    artBegin16(blk16(EB + 1 * 8, f))
    artClear(V)
    local wy = (f == 0) and 5 or (f == 1 and 3 or 8)

    -- wings
    artLine(4, wy, 0, wy - 1, C_OUT) artLine(4, wy + 1, 0, wy, K)
    artLine(11, wy, 15, wy - 1, C_OUT) artLine(11, wy + 1, 15, wy, K)
    if f == 3 then
        artLine(4, 4, 0, 7, C_OUT) artLine(11, 4, 15, 7, C_OUT)
        artLine(4, 5, 1, 8, K) artLine(11, 5, 14, 8, K)
    end

    -- body / robe
    artBox(5, 8, 10, 14, C_OUT) artBox(5, 9, 10, 14, K)
    artV(5, 9, 14, B)
    artH(6, 9, 12, B)                      -- belt

    -- feet
    artBox(4, 13, 6, 15, C_OUT) artBox(4, 13, 6, 15, K)
    artBox(9, 13, 11, 15, C_OUT) artBox(9, 13, 11, 15, K)

    -- head + long nose
    partSoft(8, 6, 3, K)
    artH(6, 10, 5, B)
    artBox(7, 3, 9, 5, C_OUT) artBox(7, 3, 9, 5, K)
    artLine(10, 6, 14, 7, C_OUT) artLine(10, 6, 13, 7, R)  -- nose
    artP(14, 7, C_OUT)
    artP(7, 5, G) artP(9, 5, G)            -- eyes
    artH(6, 9, 2, R)                        -- cap
    artP(5, 1, C_OUT) artP(10, 1, C_OUT)
end

-- ---- 3. YUREI : drifting ghost ---------------------------------------------
local function drawYurei(f)
    artBegin16(blk16(EB + 2 * 8, f))
    artClear(V)
    local dy = (f == 1) and 1 or ((f == 2) and -1 or 0)

    -- wispy tail
    for i = 0, 5 do
        local w = 4 - flr(i / 2)
        local yy = 11 + i + dy
        artH(8 - w, 8 + w, yy, VI)
        artH(8 - w, 8 - w + 1, yy, C_OUT)
        artH(8 + w - 1, 8 + w, yy, C_OUT)
    end

    -- body / hood
    partSoft(8, 6 + dy, 5, N)
    artBox(4, 6 + dy, 12, 11 + dy, C_OUT)
    artBox(5, 6 + dy, 11, 11 + dy, N)
    artV(5, 6 + dy, 11 + dy, W)

    -- dark face void with glowing eyes
    artBox(6, 5 + dy, 10, 8 + dy, C_OUT)
    artBox(6, 5 + dy, 10, 8 + dy, K)
    artP(7, 6 + dy, S) artP(9, 6 + dy, S)
    artP(7, 7 + dy, W) artP(9, 7 + dy, W)

    -- arms
    if f == 3 then
        artLine(4, 8 + dy, 1, 10 + dy, C_OUT) artLine(5, 8 + dy, 2, 10 + dy, N)
        artLine(12, 8 + dy, 15, 10 + dy, C_OUT) artLine(11, 8 + dy, 14, 10 + dy, N)
    else
        artLine(4, 8 + dy, 2, 12 + dy, C_OUT) artLine(5, 8 + dy, 3, 12 + dy, N)
        artLine(12, 8 + dy, 14, 12 + dy, C_OUT) artLine(11, 8 + dy, 13, 12 + dy, N)
    end
end

-- ---- 4. ROGUE NINJA : throws shuriken --------------------------------------
local function drawRogueNinja(f)
    artBegin16(blk16(EB + 3 * 8, f))
    artClear(V)
    local rogueGi, rogueHi, rogueScarf = VI, K, C

    -- legs
    if f == 1 then
        artBox(4, 11, 6, 15, C_OUT) artBox(4, 12, 6, 15, rogueGi)
        artBox(9, 11, 11, 14, C_OUT) artBox(9, 12, 11, 14, rogueGi)
    else
        artBox(5, 11, 7, 15, C_OUT) artBox(5, 12, 7, 15, rogueGi)
        artBox(9, 11, 11, 15, C_OUT) artBox(9, 12, 11, 15, rogueGi)
    end

    -- scarf
    for i = 1, 5 do artP(5 - i, 7 - flr(i / 2), rogueScarf) end

    -- torso
    artBox(5, 7, 10, 11, C_OUT) artBox(6, 7, 10, 11, rogueGi)
    artV(6, 7, 11, rogueHi)
    artH(6, 10, 10, rogueScarf)

    -- head
    partSoft(8, 4, 3, rogueGi)
    artH(6, 9, 4, C)                       -- eye slit
    artP(9, 3, rogueHi) artP(8, 3, rogueHi)

    -- arms
    if f == 2 then
        artBox(11, 5, 14, 7, C_OUT) artBox(11, 5, 14, 7, rogueGi)  -- throwing
        artP(15, 4, N) artP(14, 4, N)
    else
        artBox(11, 8, 13, 11, C_OUT) artBox(11, 8, 13, 11, rogueGi)
        artBox(2, 8, 4, 11, C_OUT) artBox(2, 8, 4, 11, rogueGi)
    end
    if f == 3 then
        artBox(5, 12, 7, 15, C_OUT) artBox(5, 13, 7, 15, rogueGi)
        artBox(9, 12, 11, 15, C_OUT) artBox(9, 13, 11, 15, rogueGi)
        artBox(5, 9, 10, 12, C_OUT) artBox(6, 9, 10, 12, rogueGi)
    end
end

-- ---- 5. KAPPA : turtle imp --------------------------------------------------
local function drawKappa(f)
    artBegin16(blk16(EB + 4 * 8, f))
    artClear(V)
    local dy = (f == 2) and -2 or 0

    -- legs
    artBox(4, 11 + dy, 6, 15, C_OUT) artBox(4, 12 + dy, 6, 15, J)
    artBox(9, 11 + dy, 11, 15, C_OUT) artBox(9, 12 + dy, 11, 15, J)

    -- shell
    partSoft(8, 10 + dy, 5, B)
    artP(6, 9 + dy, N) artP(10, 9 + dy, N) artP(8, 12 + dy, N)
    artH(4, 12, 13 + dy, C_OUT)

    -- body
    artBox(6, 7 + dy, 10, 11 + dy, C_OUT) artBox(6, 7 + dy, 10, 11 + dy, J)
    artV(6, 7 + dy, 11 + dy, N)

    -- head
    partSoft(8, 5 + dy, 3, J)
    artBox(11, 5 + dy, 13, 6 + dy, C_OUT) artBox(11, 5 + dy, 13, 6 + dy, G)  -- beak
    artP(10, 5 + dy, G)
    artP(7, 4 + dy, W) artP(9, 4 + dy, W)
    -- water dish on the head
    artH(6, 10, 2 + dy, C_OUT) artH(7, 9, 2 + dy, S)

    -- arms
    if f == 3 then
        artBox(11, 6 + dy, 14, 8 + dy, C_OUT) artBox(11, 6 + dy, 14, 8 + dy, J)
    else
        artBox(3, 8 + dy, 5, 11 + dy, C_OUT) artBox(3, 8 + dy, 5, 11 + dy, J)
        artBox(11, 8 + dy, 13, 11 + dy, C_OUT) artBox(11, 8 + dy, 13, 11 + dy, J)
    end
end

-- ---- 6. KITSUNE : fox spirit ------------------------------------------------
local function drawKitsune(f)
    artBegin16(blk16(EB + 5 * 8, f))
    artClear(V)
    local dy = (f == 2) and -2 or 0

    -- tails
    local tn = (f == 3) and 3 or 2
    for t = 1, tn do
        local ox = 2 - t
        artLine(4 + ox, 10 + dy, 0 + ox, 6 + dy, C_OUT)
        artLine(4 + ox, 10 + dy, 1 + ox, 6 + dy, O)
        artP(0 + ox, 5 + dy, W) artP(1 + ox, 5 + dy, W)
    end

    -- legs
    artBox(5, 11 + dy, 7, 15, C_OUT) artBox(5, 12 + dy, 7, 15, O)
    artBox(9, 11 + dy, 11, 15, C_OUT) artBox(9, 12 + dy, 11, 15, O)
    if f == 1 then
        artBox(3, 11 + dy, 5, 14, C_OUT) artBox(3, 12 + dy, 5, 14, O)
        artBox(11, 11 + dy, 13, 14, C_OUT) artBox(11, 12 + dy, 13, 14, O)
    end

    -- body
    artBox(5, 8 + dy, 11, 12 + dy, C_OUT) artBox(5, 8 + dy, 11, 12 + dy, O)
    artV(5, 8 + dy, 12 + dy, G)
    artH(6, 10, 11 + dy, N)                       -- white belly

    -- head
    partSoft(8, 6 + dy, 3, O)
    artP(5, 4 + dy, C_OUT) artP(11, 4 + dy, C_OUT)   -- ears
    artLine(4, 3 + dy, 6, 5 + dy, O) artLine(12, 3 + dy, 10, 5 + dy, O)
    artP(6, 6 + dy, K) artP(10, 6 + dy, K)           -- eyes
    artP(8, 7 + dy, K) artP(8, 8 + dy, N)            -- snout
    -- fire when attacking
    if f == 3 then
        artP(13, 6 + dy, G) artP(14, 6 + dy, O) artP(13, 5 + dy, R)
    end
end
-- ============================================================================
--  BOSS - Oni Warlord : 8 frames at 416, drawn at scale 2 by the renderer
-- ============================================================================
local BOSSB = 384

local function drawBoss(f)
    artBegin16(blk16(BOSSB, f))
    artClear(V)
    local roar = (f == 3)
    local stomp = (f == 1)
    local slam = (f == 2 or f == 5)
    local dy = stomp and 1 or 0

    -- cape
    artBox(1, 4, 4, 14, C_OUT)
    artBox(1, 4, 4, 14, C)
    artV(1, 4, 14, K)
    if f == 4 then artH(0, 2, 8, C) artH(0, 2, 10, C) end

    -- legs
    artBox(4, 11 + dy, 6, 15, C_OUT) artBox(4, 11 + dy, 6, 15, R)
    artBox(9, 11 + dy, 11, 15, C_OUT) artBox(9, 11 + dy, 11, 15, R)
    artH(3, 7, 15, C_OUT)
    artH(8, 12, 15, C_OUT)

    -- gold armour skirt
    artH(3, 12, 10 + dy, C_OUT) artH(3, 12, 10 + dy, G)
    artP(5, 10 + dy, O) artP(8, 10 + dy, O) artP(10, 10 + dy, O)

    -- torso and chest plate
    artBox(3, 4, 12, 10 + dy, C_OUT) artBox(4, 5, 11, 10 + dy, R)
    artV(4, 5, 10 + dy, O)
    artBox(5, 6, 10, 9 + dy, B)
    artBox(6, 7, 9, 8 + dy, S)
    artP(7, 7 + dy, W)

    -- shoulder guards
    artBox(1, 4, 4, 7, C_OUT) artBox(1, 4, 4, 7, B)
    artBox(11, 4, 14, 7, C_OUT) artBox(11, 4, 14, 7, B)
    artH(1, 4, 5, S) artH(11, 14, 5, S)

    -- arms
    if slam then
        artBox(12, 2, 14, 6, C_OUT) artBox(12, 2, 14, 6, R)
    else
        artBox(12, 8, 14, 12, C_OUT) artBox(12, 8, 14, 12, R)
    end
    artBox(1, 8, 3, 12, C_OUT) artBox(1, 8, 3, 12, R)

    -- head
    partSoft(8, 3, 4, R)
    artH(4, 12, 2, C_OUT)
    artP(6, 2, W) artP(10, 2, W)
    artP(6, 3, G) artP(10, 3, G)
    artP(7, 4, K) artP(9, 4, K)
    -- tusks
    artP(5, 5, W) artP(11, 5, W) artP(6, 6, W) artP(10, 6, W)
    -- two pairs of horns
    artLine(5, 0, 2, -1, C_OUT) artLine(5, 0, 3, 0, N)
    artLine(11, 0, 14, -1, C_OUT) artLine(11, 0, 13, 0, N)
    artP(4, 0, N) artP(12, 0, N)
    if roar then
        artH(6, 10, 5, K)
        artP(7, 5, R) artP(9, 5, R)
    end

    -- kanabo
    if slam then
        artLine(13, 4, 15, 15, C_OUT) artLine(13, 5, 14, 15, BR)
        artP(14, 4, DK) artP(15, 5, DK) artP(14, 6, DK)
    elseif f == 4 then
        artLine(13, 12, 15, 6, C_OUT) artLine(13, 12, 14, 7, BR)
        artP(14, 5, DK) artP(15, 6, DK)
    else
        artLine(14, 12, 15, 5, C_OUT) artLine(14, 12, 15, 6, BR)
        artP(15, 4, DK)
    end
end

-- ============================================================================
--  ITEMS, PROJECTILES, HUD ICONS - 8x8 at 448..511
-- ============================================================================
local IT = 448

local function item(id, fn)
    artBegin8(id)
    artClear(V)
    fn()
end

local function genItems()
    item(IT + 0, function()             -- kunai
        artLine(1, 6, 6, 1, C_OUT) artLine(1, 5, 5, 1, N)
        artP(1, 5, N) artP(2, 4, N)
        artP(0, 7, G) artP(1, 7, G) artP(0, 6, G)
    end)
    item(IT + 1, function()             -- shuriken
        artBox(2, 2, 5, 5, C_OUT)
        artP(3, 3, S) artP(4, 4, S)
        artLine(1, 3, 0, 3, N) artLine(4, 1, 4, 0, N)
        artLine(1, 4, 0, 4, N) artLine(4, 1, 4, 0, N)
        artLine(6, 3, 7, 3, N) artLine(3, 6, 3, 7, N)
        artLine(6, 4, 7, 4, N) artLine(4, 6, 4, 7, N)
        artP(3, 3, W)
    end)
    item(IT + 2, function()             -- ryo coin
        artDisc(3, 4, 3, G)
        artDisc(3, 4, 2, O)
        artBox(3, 2, 4, 5, C_OUT)
        artP(2, 2, W)
    end)
    item(IT + 3, function()             -- heart full
        artDisc(2, 3, 2, R) artDisc(5, 3, 2, R)
        artBox(1, 3, 6, 5, R)
        artLine(2, 6, 4, 7, R) artLine(3, 6, 4, 7, R)
        artP(2, 2, PK) artP(3, 2, PK)
    end)
    item(IT + 4, function()             -- heart empty
        artDisc(2, 3, 2, K) artDisc(5, 3, 2, K)
        artBox(1, 3, 6, 5, K)
        artLine(2, 6, 4, 7, K) artLine(3, 6, 4, 7, K)
        artP(2, 2, B) artP(3, 2, B)
    end)
    item(IT + 5, function()             -- scroll
        artH(1, 6, 1, N) artH(1, 6, 6, N)
        artBox(1, 1, 6, 6, N)
        artV(2, 2, 5, K) artH(3, 5, 3, K) artH(3, 5, 4, K)
        artP(1, 0, R) artP(6, 0, R) artP(1, 7, R) artP(6, 7, R)
    end)
    item(IT + 6, function()             -- spirit orb
        artDisc(3, 4, 3, VI)
        artDisc(2, 3, 1, S)
        artP(4, 4, W) artP(3, 5, C)
    end)
    item(IT + 7, function()             -- bomb
        artDisc(3, 5, 3, K)
        artP(1, 3, W) artP(2, 2, B)
        artLine(4, 1, 5, 0, BR)
        artP(5, 0, O) artP(6, 0, G) artP(5, 1, G)
    end)
end

local function genFx()
    item(IT + 8, function()             -- ember
        artP(3, 3, O) artP(3, 4, G) artP(4, 3, R) artP(2, 4, R)
        artP(4, 4, O) artP(3, 2, G)
    end)
    item(IT + 9, function()             -- maple leaf
        artLine(4, 0, 4, 7, C) artLine(3, 2, 5, 2, O)
        artP(2, 3, O) artP(6, 3, O) artP(1, 4, R) artP(7, 4, R)
        artP(3, 6, R) artP(5, 6, R)
    end)
    item(IT + 10, function()            -- sakura petal
        artP(4, 1, PK) artP(3, 2, PK) artP(4, 2, PK) artP(5, 2, PK)
        artP(2, 3, PK) artP(3, 3, PK) artP(4, 3, PK)
        artP(2, 4, PK) artP(3, 4, PK)
        artP(4, 1, W) artP(2, 3, R)
    end)
    item(IT + 11, function()            -- snowflake
        artV(4, 0, 7, W) artH(0, 7, 4, W)
        artP(2, 2, W) artP(3, 3, W) artP(5, 2, W) artP(4, 3, W)
        artP(2, 6, W) artP(3, 5, W) artP(5, 6, W) artP(4, 5, W)
    end)
    item(IT + 12, function()            -- bubble
        artDisc(3, 4, 3, N)
        artDisc(3, 4, 2, V)
        artP(2, 2, W) artP(3, 2, W)
    end)
    item(IT + 13, function()            -- splash
        artP(0, 4, S) artP(2, 3, S) artP(4, 2, W) artP(6, 3, S)
        artP(1, 5, B) artP(3, 5, B) artP(5, 5, B)
    end)
    item(IT + 14, function()            -- spark / hit
        artV(4, 1, 5, W) artH(1, 5, 4, W)
        artP(2, 2, G) artP(6, 2, G) artP(2, 6, G) artP(6, 6, G)
        artP(4, 3, W) artP(4, 4, W)
    end)
    item(IT + 15, function()            -- smoke puff
        artDisc(3, 4, 3, K)
        artDisc(5, 3, 2, B)
        artP(2, 2, S) artP(5, 5, S)
    end)
    item(IT + 16, function()            -- slash arc (small)
        artLine(1, 6, 6, 1, C_OUT) artLine(0, 5, 6, 0, W)
        artP(2, 3, S) artP(4, 2, S)
    end)
    item(IT + 17, function()            -- slash arc (horizontal)
        artH(0, 7, 4, C_OUT) artH(1, 6, 3, W) artH(2, 5, 2, W)
        artP(4, 2, S) artP(5, 1, S)
    end)
    item(IT + 18, function()            -- impact star
        artV(4, 0, 7, W) artH(0, 7, 4, W)
        artP(2, 2, G) artP(3, 3, G) artP(5, 2, G) artP(4, 3, G)
        artP(2, 6, G) artP(3, 5, G) artP(5, 6, G) artP(4, 5, G)
        artP(4, 3, W) artP(4, 4, W)
    end)
    item(IT + 19, function()            -- dust
        artP(2, 5, N) artP(3, 4, S) artP(5, 5, N) artP(4, 6, S)
    end)
    item(IT + 20, function()            -- water ripple
        artH(1, 6, 4, S) artP(0, 4, B) artP(7, 4, B)
        artH(2, 5, 5, B)
    end)
    item(IT + 21, function()            -- oni fire ball
        artDisc(3, 4, 3, O)
        artDisc(3, 4, 2, G)
        artP(3, 3, W)
    end)
    item(IT + 22, function()            -- arrow / boss shock
        artH(0, 7, 3, C_OUT) artH(1, 7, 3, R)
        artH(1, 7, 4, C)
    end)
    item(IT + 23, function()            -- blank
        artClear(V)
    end)
end

local function genIcons()
    item(IT + 24, function()            -- double jump icon
        artLine(1, 7, 4, 3, S) artLine(1, 7, 4, 3, C_OUT)
        artLine(4, 3, 7, 7, S) artLine(4, 3, 7, 7, C_OUT)
        artH(2, 6, 6, W)
    end)
    item(IT + 25, function()            -- dash icon
        artH(0, 4, 2, W) artH(2, 6, 4, W) artH(0, 4, 6, S)
    end)
    item(IT + 26, function()            -- wall cling icon
        artBox(0, 0, 2, 7, S)
        artV(0, 0, 7, C_OUT) artV(2, 0, 7, C_OUT)
        artP(4, 2, W) artP(5, 3, W) artP(4, 5, W)
    end)
    item(IT + 27, function()            -- water walking icon
        artH(0, 7, 4, B) artH(0, 7, 5, S)
        artP(2, 2, W) artP(4, 1, W) artP(6, 2, W)
    end)
    item(IT + 28, function()            -- key
        artDisc(2, 2, 2, G)
        artDisc(2, 2, 1, V)
        artH(4, 7, 4, G) artP(6, 5, G) artP(6, 3, G)
    end)
    item(IT + 29, function()            -- shrine icon (torii)
        artH(1, 6, 1, R) artH(2, 5, 2, R)
        artV(2, 2, 7, R) artV(5, 2, 7, R)
        artH(2, 5, 4, R)
    end)
    item(IT + 30, function()            -- lantern / save icon
        artH(2, 6, 1, N)
        artBox(2, 2, 5, 5, G)
        artP(3, 3, W) artH(2, 6, 6, N)
    end)
    item(IT + 31, function()            -- map marker
        artDisc(3, 3, 2, R)
        artLine(3, 5, 3, 7, R) artLine(4, 5, 4, 7, C)
        artP(3, 3, W)
    end)
end

-- ============================================================================
genChars = function(ph)
    ph = ph or 0
    for f = 0, 15 do drawPlayer(f, ph) end
    drawOni(0) drawOni(1) drawOni(2) drawOni(3)
    drawTengu(0) drawTengu(1) drawTengu(2) drawTengu(3)
    drawYurei(0) drawYurei(1) drawYurei(2) drawYurei(3)
    drawRogueNinja(0) drawRogueNinja(1) drawRogueNinja(2) drawRogueNinja(3)
    drawKappa(0) drawKappa(1) drawKappa(2) drawKappa(3)
    drawKitsune(0) drawKitsune(1) drawKitsune(2) drawKitsune(3)
    for f = 0, 7 do drawBoss(f) end
    genItems()
    genFx()
    genIcons()
end

-- ============================================================================
--  frame index constants used by gameplay code
-- ============================================================================
PF = { IDLE = 0, RUN1 = 1, RUN2 = 2, RUN3 = 3, RUN4 = 4, JUMP = 5, FALL = 6,
       SLASH1 = 7, SLASH2 = 8, DASH = 9, WALL = 10, CROUCH = 11, HURT = 12,
       THROW = 13, LAND = 14, POWER = 15 }
EF = { ONI = 0, TENGU = 1, YUREI = 2, ROGUE = 3, KAPPA = 4, KITSUNE = 5 }

end   -- buildArt

-- Paint the whole atlas once, at boot.
buildArt()

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

-- ============================================================================
--  08 - TILE COLLISION
--
--  Collision is flag-driven.  The registration below is the only tile-id
--  policy in this module; all later queries use the flag store.
-- ============================================================================

local Tiles = {}

function Tiles.registerCollisionFlags()
    for tileId = 1, 80 do fset(tileId, F_SOLID, true) end
    for tileId = 81, 88 do fset(tileId, F_ONEWAY, true) end
    fset(T.SPIKE_BASE, F_SOLID, true)
    for tileId = T.BRIDGE_A, T.FLOOR_WOOD_R do fset(tileId, F_SOLID, true) end
end

Tiles.registerCollisionFlags()

function Tiles.inBounds(tx, ty)
    return tx >= 0 and ty >= 0 and tx < MAP_W and ty < MAP_H
end

function Tiles.at(tx, ty)
    if not Tiles.inBounds(tx, ty) then return 0 end
    return mget(tx, ty)
end

-- Pixel coordinates are half-open: x=8 belongs to tile column 1.
function Tiles.atPx(px, py)
    if px == nil or py == nil then return 0 end
    return Tiles.at(flr(px / TS), flr(py / TS))
end

function Tiles.tileFlag(tx, ty, flag)
    if flag == nil or not Tiles.inBounds(tx, ty) then return false end
    return fget(mget(tx, ty), flag) == true
end

function Tiles.flagAtPx(px, py, flag)
    if flag == nil or px == nil or py == nil then return false end
    return Tiles.tileFlag(flr(px / TS), flr(py / TS), flag)
end

function Tiles.solidAtPx(px, py)
    return Tiles.flagAtPx(px, py, F_SOLID)
end

-- Tiny epsilon keeps exact tile edges out of the neighbouring cell.
function Tiles.rectHitsFlag(rect, flag)
    if rect == nil or flag == nil then return false end
    local x0, y0 = tonumber(rect.x), tonumber(rect.y)
    local w, h = tonumber(rect.w), tonumber(rect.h)
    if x0 == nil or y0 == nil or w == nil or h == nil or w <= 0 or h <= 0 then
        return false
    end
    local eps = 0.000001
    local x1, y1 = x0 + w, y0 + h
    local tx0 = flr(x0 / TS)
    local tx1 = flr((x1 - eps) / TS)
    local ty0 = flr(y0 / TS)
    local ty1 = flr((y1 - eps) / TS)
    for ty = ty0, ty1 do
        for tx = tx0, tx1 do
            if Tiles.tileFlag(tx, ty, flag) then return true end
        end
    end
    return false
end

function Tiles.rectHitsSolid(rect)
    return Tiles.rectHitsFlag(rect, F_SOLID)
end

function Tiles.rectHitsOneWay(rect)
    return Tiles.rectHitsFlag(rect, F_ONEWAY)
end

function Tiles.rectHitsFlagOr(rect, first, second)
    return Tiles.rectHitsFlag(rect, first) or Tiles.rectHitsFlag(rect, second)
end

function Tiles.wallSideForRect(rect, face)
    if rect == nil then return 0 end
    if face >= 0 and Tiles.rectHitsSolid({ x = rect.x + rect.w, y = rect.y, w = 1, h = rect.h }) then
        return 1
    end
    if face <= 0 and Tiles.rectHitsSolid({ x = rect.x - 1, y = rect.y, w = 1, h = rect.h }) then
        return -1
    end
    return 0
end

function Tiles.newMoveResult()
    return {
        x = 0, y = 0,
        dx = 0, dy = 0,
        hitX = false, hitY = false,
        blockedX = false, blockedY = false,
        tileHitX = false, tileHitY = false,
        worldHitX = false, worldHitY = false,
        normalX = 0, normalY = 0,
        nx = 0, ny = 0,
        impactX = 0, impactY = 0,
        axis = "none",
        grounded = false, onGround = false,
        wall = 0, onWall = false,
        oneWay = false,
        outOfBounds = false, outX = false, outY = false,
        fell = false,
    }
end

-- Axis-separated swept AABB movement.  The body is mutated in x/y; caller
-- owns velocity policy.  One-way tiles are descending-only and are skipped by
-- opts.dropThrough for a deliberate down+jump drop.
function Tiles.moveBody(body, dx, dy, opts)
    opts = opts or {}
    local result = Tiles.newMoveResult()
    if body == nil then return result end

    local w = tonumber(body.w) or 0
    local h = tonumber(body.h) or 0
    if w <= 0 or h <= 0 then
        result.x, result.y = body.x or 0, body.y or 0
        body.x, body.y = result.x, result.y
        return result
    end

    local maxX = max(0, WORLD_W - w)
    local maxY = max(0, WORLD_H - h)
    local startX = clamp(tonumber(body.x) or 0, 0, maxX)
    local startY = clamp(tonumber(body.y) or 0, 0, maxY)
    body.x, body.y = startX, startY
    if dx == nil then dx = body.vx or 0 end
    if dy == nil then dy = body.vy or 0 end
    dx, dy = tonumber(dx) or 0, tonumber(dy) or 0

    local desiredX = startX + dx
    local desiredY = startY + dy
    local boundedX = clamp(desiredX, 0, maxX)
    local boundedY = clamp(desiredY, 0, maxY)
    if boundedX ~= desiredX then
        result.outOfBounds, result.outX = true, true
        result.worldHitX, result.hitX = true, true
        result.normalX, result.nx = dx > 0 and -1 or 1, dx > 0 and -1 or 1
    end
    if boundedY ~= desiredY then
        result.outOfBounds, result.outY = true, true
        result.worldHitY, result.hitY = true, true
        result.normalY, result.ny = dy > 0 and -1 or 1, dy > 0 and -1 or 1
        if dy > 0 then result.fell = true end
    end

    local eps = 0.000001
    local x, y = boundedX, startY

    -- Horizontal sweep.
    if dx ~= 0 then
        local limit = boundedX
        local ty0 = flr(startY / TS)
        local ty1 = flr((startY + h - eps) / TS)
        if dx > 0 then
            local first = flr((startX + w) / TS)
            local last = flr((desiredX + w + eps) / TS)
            for tx = first, last do
                local tileLeft = tx * TS
                if startX + w <= tileLeft + eps and desiredX + w >= tileLeft - eps then
                    for ty = ty0, ty1 do
                        if Tiles.tileFlag(tx, ty, F_SOLID) then
                            local candidate = tileLeft - w
                            if candidate < limit then
                                limit = candidate
                                result.hitX, result.tileHitX = true, true
                                result.normalX, result.nx = -1, -1
                                result.wall = 1
                            end
                            break
                        end
                    end
                end
            end
        else
            local first = flr(startX / TS) - 1
            local last = flr((desiredX + eps) / TS)
            for tx = first, last, -1 do
                local tileRight = (tx + 1) * TS
                if startX >= tileRight - eps and desiredX <= tileRight + eps then
                    for ty = ty0, ty1 do
                        if Tiles.tileFlag(tx, ty, F_SOLID) then
                            local candidate = tileRight
                            if candidate > limit then
                                limit = candidate
                                result.hitX, result.tileHitX = true, true
                                result.normalX, result.nx = 1, 1
                                result.wall = -1
                            end
                            break
                        end
                    end
                end
            end
        end
        x = clamp(limit, 0, maxX)
    end
    body.x = x
    result.x = x

    -- Vertical sweep after horizontal movement, so corners cannot tunnel.
    local yLimit = boundedY
    if dy ~= 0 then
        local tx0 = flr(x / TS)
        local tx1 = flr((x + w - eps) / TS)
        if dy > 0 then
            local first = flr((startY + h) / TS)
            local last = flr((desiredY + h + eps) / TS)
            for ty = first, last do
                local tileTop = ty * TS
                -- One-way platforms only catch a body whose previous feet
                -- were at or above the platform top.
                if startY + h <= tileTop + eps and desiredY + h >= tileTop - eps then
                    for tx = tx0, tx1 do
                        local solid = Tiles.tileFlag(tx, ty, F_SOLID)
                        local oneWay = not opts.dropThrough and Tiles.tileFlag(tx, ty, F_ONEWAY)
                        if solid or oneWay then
                            local candidate = tileTop - h
                            if candidate < yLimit then
                                yLimit = candidate
                                result.hitY, result.tileHitY = true, true
                                result.normalY, result.ny = -1, -1
                                result.oneWay = result.oneWay or oneWay
                            end
                            break
                        end
                    end
                end
            end
        else
            local first = flr(startY / TS) - 1
            local last = flr((desiredY - eps) / TS)
            for ty = first, last, -1 do
                local tileBottom = (ty + 1) * TS
                if startY >= tileBottom - eps and desiredY <= tileBottom + eps then
                    for tx = tx0, tx1 do
                        if Tiles.tileFlag(tx, ty, F_SOLID) then
                            local candidate = tileBottom
                            if candidate > yLimit then
                                yLimit = candidate
                                result.hitY, result.tileHitY = true, true
                                result.normalY, result.ny = 1, 1
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    y = clamp(yLimit, 0, maxY)
    body.y = y
    result.y = y
    result.dx, result.dy = body.x - startX, body.y - startY
    result.blockedX, result.blockedY = result.hitX, result.hitY
    result.grounded = result.tileHitY and result.normalY < 0
    result.onGround = result.grounded
    result.onWall = result.tileHitX and result.wall ~= 0
    result.impactX, result.impactY = result.normalX, result.normalY
    if result.hitX and result.hitY then
        result.axis = "xy"
    elseif result.hitX then
        result.axis = "x"
    elseif result.hitY then
        result.axis = "y"
    end
    return result
end

Tiles.sweepMove = Tiles.moveBody
Tiles.sweepAABB = Tiles.moveBody
Tiles.moveAABB = Tiles.moveBody

-- ============================================================================
--  09 - PLAYER
--
--  A deterministic, fixed-step character controller.  The table is also the
--  public state object consumed by rendering, combat, and progression modules.
--  x/y are always the top-left corner of the AABB.
-- ============================================================================

local Player = {
    x = 0, y = 0, w = 6, h = 14,
    vx = 0, vy = 0,
    face = 1,
    onGround = false,
    onWall = false,
    state = "idle",
    frame = 0,
    animTime = 0,
    coyote = 0,
    jumpBuffer = 0,
    airJumps = 0,
    dashLeft = 0,
    dashReady = false,
    climbing = false,
    ledge = false,
    canDoubleJump = false,
    canDash = false,
    canWallCling = false,
    hearts = 3,
    maxHearts = 3,
    stamina = 100,
    ryo = 0,
    scrolls = 0,
    invuln = 0,
    hazard = false,
    fell = false,
    spawnX = 0,
    spawnY = 0,

    -- State-machine internals remain on the public object rather than adding
    -- chunk-level locals to the concatenated cart.
    wallSide = 0,
    landTimer = 0,
    ledgeSide = 0,
    dropThrough = false,
    dashUsed = false,
    _inputBufActive = false,
    _jumpWasHeld = false,
    _groundProbe = false,
}

function Player.reset(x, y)
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    Player.w, Player.h = 6, 14
    Player.x = clamp(x, 0, WORLD_W - Player.w)
    Player.y = clamp(y, 0, WORLD_H - Player.h)
    Player.spawnX, Player.spawnY = Player.x, Player.y
    Player.vx, Player.vy = 0, 0
    Player.face = 1
    Player.onGround = false
    Player.onWall = false
    Player.state = "idle"
    Player.frame = PF.IDLE
    Player.animTime = 0
    Player.coyote = 0
    Player.jumpBuffer = 0
    Player.airJumps = 0
    Player.dashLeft = 0
    Player.dashReady = false
    Player.climbing = false
    Player.ledge = false
    Player.wallSide = 0
    Player.ledgeSide = 0
    Player.landTimer = 0
    Player.dropThrough = false
    Player._inputBufActive = false
    Player._jumpWasHeld = false
    Player._groundProbe = false
    Player.invuln = 0
    Player.hazard = false
    Player.fell = false
    if Player.hearts == nil then Player.hearts = 3 end
    if Player.maxHearts == nil then Player.maxHearts = 3 end
    if Player.hearts > Player.maxHearts then Player.hearts = Player.maxHearts end
    if Player.stamina == nil then Player.stamina = 100 end
    if Player.ryo == nil then Player.ryo = 0 end
    if Player.scrolls == nil then Player.scrolls = 0 end
    if Player.canDoubleJump == nil then Player.canDoubleJump = false end
    if Player.canDash == nil then Player.canDash = false end
    if Player.canWallCling == nil then Player.canWallCling = false end
    Player.dashReady = Player.canDash == true

    -- A reset at a floor is immediately grounded, while a reset in the air
    -- remains airborne.  The next fixed step always re-probes the support.
    Player.onGround = Tiles.rectHitsFlag({ x = Player.x, y = Player.y + Player.h, w = Player.w, h = 0.5 }, F_SOLID)
        or Tiles.rectHitsFlag({ x = Player.x, y = Player.y + Player.h, w = Player.w, h = 0.5 }, F_ONEWAY)
    if Player.onGround then Player.coyote = COYOTE_TICKS end
    return Player
end

function Player.supportProbe()
    local foot = { x = Player.x, y = Player.y + Player.h, w = Player.w, h = 0.5 }
    local solid = Tiles.rectHitsFlag(foot, F_SOLID)
    local oneWay = Tiles.rectHitsFlag(foot, F_ONEWAY)
    Player._groundProbe = solid or oneWay
    return Player._groundProbe
end

function Player.findWall()
    local body = { x = Player.x, y = Player.y, w = Player.w, h = Player.h }
    local right = Tiles.rectHitsSolid({ x = body.x + body.w, y = body.y, w = 1, h = body.h })
    local left = Tiles.rectHitsSolid({ x = body.x - 1, y = body.y, w = 1, h = body.h })
    if right and left then
        if Player.face >= 0 then return 1 end
        return -1
    end
    if right then return 1 end
    if left then return -1 end
    return 0
end

function Player.findLedge()
    if Player.onGround or Player.vy < 0 then return 0, 0 end
    local side = Player.findWall()
    if side == 0 then return 0, 0 end
    local probeX = side > 0 and (Player.x + Player.w + 0.5) or (Player.x - 0.5)
    local probeY = Player.y + 2
    local id = Tiles.atPx(probeX, probeY)
    if id == 0 or not fget(id, F_SOLID) then return 0, 0 end
    local tx, ty = flr(probeX / TS), flr(probeY / TS)
    if not Tiles.tileFlag(tx, ty, F_SOLID) then return 0, 0 end

    -- Find the nearest upper edge of this wall.  A clear landing footprint
    -- distinguishes a grabbable ledge from a solid face with no space above.
    local topY = ty * TS
    for probe = ty - 1, ty - 3, -1 do
        if Tiles.tileFlag(tx, probe, F_SOLID) then topY = probe * TS else break end
    end
    -- A grabbable ledge has its top above the player's top edge but within one
    -- body height.  A one-tile horizontal floor beside the body has its top at
    -- the player's top edge and must never teleport the player upward.
    if not (topY < Player.y - 1 and topY > Player.y - Player.h) then
        return 0, 0
    end
    if not (Tiles.tileFlag(tx, ty + 1, F_SOLID) or Tiles.tileFlag(tx, ty + 2, F_SOLID)) then
        return 0, 0
    end
    local landingX = side > 0 and (tx * TS - Player.w) or ((tx + 1) * TS)
    local landing = { x = landingX, y = topY - Player.h, w = Player.w, h = Player.h }
    if Tiles.rectHitsSolid(landing) then return 0, 0 end
    return side, topY
end

function Player.canStand()
    local feet = Player.y + Player.h
    local stand = { x = Player.x, y = feet - 14, w = Player.w, h = 14 }
    return not Tiles.rectHitsSolid(stand)
end

function Player.setCrouch(down)
    if not down or not Player.onGround then
        if Player.h ~= 14 and Player.canStand() then
            local feet = Player.y + Player.h
            Player.h = 14
            Player.y = feet - Player.h
        end
        return
    end
    if Player.h ~= 8 then
        local feet = Player.y + Player.h
        local stand = { x = Player.x, y = feet - 8, w = Player.w, h = 8 }
        if not Tiles.rectHitsSolid(stand) then
            Player.h = 8
            Player.y = feet - Player.h
        end
    end
end

function Player.readInput(input)
    input = input or Input
    local x = tonumber(input.x) or 0
    if x == 0 then
        x = ((input.right and 1) or 0) - ((input.left and 1) or 0)
    end
    if x < -1 then x = -1 elseif x > 1 then x = 1 end
    local y = tonumber(input.y) or 0
    if y < -1 then y = -1 elseif y > 1 then y = 1 end
    return x, y, input.left == true, input.right == true, input.up == true,
        input.down == true, input.jump == true, input.jumpHeld == true,
        tonumber(input.jumpBuf) or 0
end

function Player.update(input)
    input = input or Input
    local moveX, moveY, leftHeld, rightHeld, upHeld, downHeld,
        jumpPressed, jumpHeld, inputJumpBuf = Player.readInput(input)

    -- Track a snapshot buffer as an edge without writing to the caller's
    -- table.  This is important for replay tapes and for the shared Input.
    if jumpPressed then
        Player.jumpBuffer = JUMP_BUFFER_TICKS
        Player._inputBufActive = true
    elseif inputJumpBuf > 0 and not Player._inputBufActive then
        Player.jumpBuffer = max(Player.jumpBuffer, inputJumpBuf)
        Player._inputBufActive = true
    elseif inputJumpBuf <= 0 then
        Player._inputBufActive = false
    end
    local wasGround = Player.onGround
    local support = Player.supportProbe()
    if wasGround and not support then
        -- Leaving a ledge grants a fresh coyote window on this transition.
        Player.coyote = COYOTE_TICKS
        Player.onGround = false
    elseif wasGround then
        Player.coyote = COYOTE_TICKS
    elseif Player.coyote > 0 then
        Player.coyote = Player.coyote - 1
    end

    if Player.ledge then
        local ledgeSide = Player.ledgeSide or Player.findWall()
        if Player.jumpBuffer > 0 and jumpPressed == false then
            -- A held buffered jump releases the ledge; an explicit down+jump
            -- below is handled by the normal drop branch.
        end
        if Player.jumpBuffer > 0 and downHeld then
            Player.jumpBuffer = 0
            Player.ledge = false
            Player.ledgeSide = 0
            Player.onGround = false
            Player.onWall = false
            Player.wallSide = 0
            Player.vy = 0.5
            Player.dropThrough = true
        elseif Player.jumpBuffer > 0 then
            Player.jumpBuffer = 0
            Player.ledge = false
            Player.ledgeSide = 0
            Player.onGround = false
            Player.onWall = false
            Player.wallSide = 0
            Player.face = ledgeSide > 0 and -1 or 1
            Player.vx = Player.face * RUN_MAX
            Player.vy = JUMP_VEL * (jumpHeld and 1 or 0.55)
            Player.coyote = 0
        else
            Player.vx = 0
            Player.vy = 0
            Player.onWall = ledgeSide ~= 0
            Player.wallSide = ledgeSide
            Player.state = "ledge"
            Player.frame = PF.WALL
            Player.animTime = Player.animTime + 1
            if Player.invuln > 0 then Player.invuln = Player.invuln - 1 end
            Player.hazard = Tiles.rectHitsFlag(Player, F_HAZARD)
            return Player
        end
    end

    -- A wall is useful for feedback even when the upgrade is locked.  Cling,
    -- slide, and wall jump are gated exclusively by canWallCling.
    local wallSide = Player.findWall()
    Player.wallSide = wallSide
    Player.onWall = wallSide ~= 0
    local canCling = Player.canWallCling and wallSide ~= 0 and not Player.onGround
    if canCling and (moveX == 0 or moveX == wallSide) then
        Player.climbing = true
        Player.vx = 0
        if Player.vy < 0 then Player.vy = 0 end
        if Player.vy > 0.85 then Player.vy = 0.85 end
        Player.stamina = max(0, Player.stamina - 0.12)
    else
        Player.climbing = false
    end

    -- Crouching always preserves the feet.  Expanding is deferred until a
    -- full-height headroom probe succeeds.
    Player.setCrouch(downHeld and Player.onGround)

    local groundedJump = Player.onGround or Player.coyote > 0
    local usedAction = false
    if Player.jumpBuffer > 0 and groundedJump and not (downHeld and Player.onGround) then
        Player.jumpBuffer = 0
        Player.vy = JUMP_VEL * (jumpHeld and 1 or 0.55)
        Player.onGround = false
        Player.coyote = 0
        Player.airJumps = 0
        usedAction = true
    elseif Player.jumpBuffer > 0 and canCling then
        Player.jumpBuffer = 0
        Player.face = wallSide > 0 and -1 or 1
        Player.vx = Player.face * RUN_MAX
        Player.vy = JUMP_VEL * (jumpHeld and 1 or 0.55)
        Player.onGround = false
        Player.onWall = false
        Player.climbing = false
        Player.wallSide = 0
        Player.coyote = 0
        Player.airJumps = 0
        Player.stamina = max(0, Player.stamina - 10)
        usedAction = true
    elseif Player.jumpBuffer > 0 and not Player.onGround and downHeld and Player.canDash
        and Player.dashLeft <= 0 and Player.dashReady and Player.stamina >= 18 then
        Player.jumpBuffer = 0
        Player.dashLeft = 8
        Player.dashReady = false
        Player.stamina = max(0, Player.stamina - 18)
        Player.vx = Player.face * DASH_SPEED
        Player.vy = 0
        Player.onGround = false
        Player.coyote = 0
        usedAction = true
    elseif Player.jumpBuffer > 0 and not Player.onGround and Player.canDoubleJump
        and Player.airJumps == 0 then
        Player.jumpBuffer = 0
        Player.airJumps = 1
        Player.vy = DOUBLE_JUMP_VEL * (jumpHeld and 1 or 0.55)
        usedAction = true
    end
    Player._jumpWasHeld = jumpHeld

    -- Grounded down+jump drops through a one-way platform.  It is not an air
    -- dash and it never consumes a solid floor.
    if downHeld and jumpPressed and Player.onGround then
        local under = { x = Player.x, y = Player.y + Player.h - 0.5, w = Player.w, h = 1.5 }
        if Tiles.rectHitsFlag(under, F_ONEWAY) then
            Player.jumpBuffer = 0
            Player.dropThrough = true
            Player.vy = 0.5
            Player.onGround = false
            Player.coyote = 0
        end
    end

    -- Horizontal acceleration/friction.  A locked dash or wall cling owns vx.
    if Player.dashLeft > 0 then
        Player.vx = Player.face * DASH_SPEED
        Player.vy = 0
        if moveX ~= 0 then Player.face = moveX end
    elseif not canCling then
        local target = moveX * RUN_MAX
        local accel = Player.onGround and RUN_ACCEL or AIR_ACCEL
        if moveX ~= 0 then
            Player.vx = approach(Player.vx, target, accel)
            Player.face = moveX
        else
            Player.vx = approach(Player.vx, 0, (Player.onGround and RUN_FRICTION or AIR_ACCEL * 0.65))
        end
    end

    -- Variable-height jump: a released button cuts upward momentum on the next
    -- rising frames, while the initial tap multiplier remains deterministic.
    if Player.vy < 0 and not jumpHeld and not usedAction then
        Player.vy = approach(Player.vy, 0, GRAVITY * 1.35)
    elseif Player.vy < 0 and not jumpHeld and usedAction and Player._jumpWasHeld then
        Player.vy = approach(Player.vy, 0, GRAVITY * 1.35)
    end

    if Player.dashLeft <= 0 and not canCling and not Player.climbing then
        if Player.onGround then
            Player.vy = 0
        else
            local gravity = abs(Player.vy) < 0.85 and GRAVITY_APEX or GRAVITY
            Player.vy = min(MAX_FALL, Player.vy + gravity)
        end
    elseif Player.climbing then
        Player.vy = moveY * RUN_MAX
    end

    local dropThroughMove = Player.dropThrough
    local moveResult = Tiles.moveBody(Player, Player.vx, Player.vy, { dropThrough = dropThroughMove })
    Player.dropThrough = false
    if moveResult.hitX then Player.vx = 0 end
    if moveResult.hitY and moveResult.normalY < 0 and not moveResult.outY then
        if not wasGround and Player.vy >= 0 then Player.landTimer = 6 end
        Player.vy = 0
        Player.onGround = true
        Player.coyote = COYOTE_TICKS
        Player.airJumps = 0
        if Player.canDash then Player.dashReady = true end
    elseif moveResult.hitY then
        Player.vy = 0
        Player.onGround = false
    elseif not dropThroughMove and Player.supportProbe() and Player.vy >= 0 then
        -- A grounded body can move horizontally with dy=0; retain support after
        -- the axis-separated sweep instead of briefly entering fall state.  A
        -- support snap is still a landing for animation purposes.
        if not wasGround then Player.landTimer = 6 end
        Player.vy = 0
        Player.onGround = true
        Player.coyote = COYOTE_TICKS
        Player.airJumps = 0
        if Player.canDash then Player.dashReady = true end
    else
        Player.onGround = false
        if Player.vy == 0 then Player.vy = GRAVITY end
    end
    if moveResult.fell then Player.fell = true end
    if Player.landTimer > 0 then Player.landTimer = Player.landTimer - 1 end
    if Player.dashLeft > 0 then Player.dashLeft = Player.dashLeft - 1 end
    if Player.jumpBuffer > 0 then Player.jumpBuffer = Player.jumpBuffer - 1 end
    if Player.invuln > 0 then Player.invuln = Player.invuln - 1 end

    -- Ledge capture happens after the normal sweep, but never while already
    -- grounded and only while descending beside a real solid face.
    if not Player.onGround and not Player.ledge and Player.vy >= 0 and Player.dashLeft <= 0 then
        local ledgeSide, topY = Player.findLedge()
        if ledgeSide ~= 0 then
            Player.ledge = true
            Player.ledgeSide = ledgeSide
            Player.onWall = true
            Player.wallSide = ledgeSide
            Player.climbing = false
            Player.vx, Player.vy = 0, 0
            if ledgeSide > 0 then
                Player.x = flr((Player.x + Player.w + 0.5) / TS) * TS - Player.w
            else
                Player.x = (flr((Player.x - 0.5) / TS) + 1) * TS
            end
            Player.y = topY - Player.h
            Player.face = ledgeSide > 0 and 1 or -1
        end
    end

    -- The ladder flag is intentionally independent from solid collision.
    Player.climbing = Player.climbing or (Tiles.rectHitsFlag(Player, F_CLIMB) and not Player.onGround)
    if Player.climbing and not canCling and moveY ~= 0 then Player.vy = moveY * RUN_MAX end

    Player.hazard = Tiles.rectHitsFlag(Player, F_HAZARD)
    if Player.hazard and Player.invuln > 0 then
        -- Keep the raw overlap visible; combat decides whether to consume it.
        Player.hazard = true
    end

    -- State selection and deterministic animation timing.
    Player.animTime = Player.animTime + 1
    local nextState, nextFrame
    if Player.ledge then
        nextState, nextFrame = "ledge", PF.WALL
    elseif Player.dashLeft > 0 then
        nextState, nextFrame = "dash", PF.DASH
    elseif Player.climbing or (Player.onWall and Player.canWallCling and not Player.onGround) then
        nextState, nextFrame = "wall", PF.WALL
    elseif Player.onGround and downHeld then
        nextState, nextFrame = "crouch", PF.CROUCH
    elseif not Player.onGround and Player.vy < 0 then
        nextState, nextFrame = "jump", PF.JUMP
    elseif not Player.onGround then
        nextState, nextFrame = "fall", PF.FALL
    elseif Player.landTimer > 0 then
        nextState, nextFrame = "land", PF.LAND
    elseif abs(Player.vx) > 0.08 then
        nextState = "run"
        nextFrame = PF.RUN1 + (flr(Player.animTime / 5) % 4)
    else
        nextState, nextFrame = "idle", PF.IDLE
    end
    Player.state, Player.frame = nextState, nextFrame
    if Player.frame < PF.IDLE or Player.frame > 15 then Player.frame = PF.IDLE end
    if Player.face ~= 1 and Player.face ~= -1 then Player.face = 1 end
    Player.stamina = clamp(Player.stamina + (Player.climbing and 0 or 0.18), 0, 100)
    if Player.stamina < 0 then Player.stamina = 0 end
    return Player
end

-- ============================================================================
--  10 - CAMERA
--
--  Fixed-step, deterministic pixel follow camera. The 2.5D scene stays anchored
--  to the player while the primitive background receives Camera.x/y as its
--  parallax source.
-- ============================================================================

local Camera = {}

Camera.x, Camera.y = 0, 0
Camera.region, Camera.regionName = 1, ""
Camera.lookX, Camera.lookY = 0, 0
Camera.tint, Camera.changed = "none", false

Camera.reset = function(player)
    local centerX = player.x + player.w * 0.5
    local centerY = player.y + player.h * 0.5
    local maxX, maxY = max(0, WORLD_W - SCREEN_W), max(0, WORLD_H - SCREEN_H)

    Camera.lookX, Camera.lookY = 0, 0
    Camera.x = clamp(centerX - SCREEN_W * 0.5, 0, maxX)
    Camera.y = clamp(centerY - SCREEN_H * 0.5, 0, maxY)

    local column = clamp(flr(centerX / TS) + 1, 1, MAP_W)
    local oldRegion = Camera.region
    Camera.region = World.regOf[column] or 1
    local region = World.regions[Camera.region] or {}
    Camera.regionName = region.name or ""
    Camera.tint = region.tint or "none"
    Camera.changed = Camera.region ~= oldRegion

    palSetTint(Camera.tint)
    return Camera.changed, Camera.region
end

Camera.update = function(player, snap)
    local centerX = player.x + player.w * 0.5
    local centerY = player.y + player.h * 0.5
    local maxX, maxY = max(0, WORLD_W - SCREEN_W), max(0, WORLD_H - SCREEN_H)

    -- Keep anticipation deliberately small: enough to reveal travel direction,
    -- not enough to make the player appear to slide away from screen centre.
    local targetLookX = clamp((player.vx or 0) * 1.15, -14, 14)
    local targetLookY = clamp((player.vy or 0) * 0.55, -8, 8)
    local lookBlend = snap and 1 or 0.12
    Camera.lookX = lerp(Camera.lookX or 0, targetLookX, lookBlend)
    Camera.lookY = lerp(Camera.lookY or 0, targetLookY, lookBlend)

    local targetX = clamp(centerX + Camera.lookX - SCREEN_W * 0.5, 0, maxX)
    local targetY = clamp(centerY + Camera.lookY - SCREEN_H * 0.5, 0, maxY)
    local followBlend = snap and 1 or 0.15
    Camera.x = lerp(Camera.x or targetX, targetX, followBlend)
    Camera.y = lerp(Camera.y or targetY, targetY, 0.12)
    if snap then Camera.y = targetY end
    Camera.x = clamp(Camera.x, 0, maxX)
    Camera.y = clamp(Camera.y, 0, maxY)

    local column = clamp(flr(centerX / TS) + 1, 1, MAP_W)
    local oldRegion = Camera.region
    Camera.region = World.regOf[column] or 1
    local region = World.regions[Camera.region] or {}
    Camera.regionName = region.name or ""
    Camera.tint = region.tint or "none"
    Camera.changed = Camera.region ~= oldRegion

    palSetTint(Camera.tint)
    return Camera.changed, Camera.region
end

-- ============================================================================
--  18 - GAME LIFECYCLE
--
--  Owns boot order, progression defaults, deterministic recovery, and the
--  per-frame update order.  The renderer is deliberately a forward handle:
--  20_render assigns it after this module is concatenated.
-- ============================================================================

local renderFrame
local Game = {}

function Game.boot()
    -- Build art before placing map decorations and before the first render.
    -- The guard makes BOOT safe to invoke more than once (for example from a
    -- headless test driver) without duplicating map state or spawn records.
    if not Game.worldReady then
        genTerrain()
        genProps()
        genChars(0)
        worldGen()
        Game.worldReady = true
    end

    -- Reset motion first, then seed progression so reset cannot overwrite the
    -- slice's baseline unlocks or inventory.
    Player.reset(World.startX * TS, World.startY * TS)
    Player.spawnX = World.startX * TS
    Player.spawnY = World.startY * TS
    Player.canDoubleJump = false
    Player.canDash = false
    Player.canWallCling = false
    Player.dashReady = false
    Player.maxHearts = 3
    Player.hearts = 3
    Player.stamina = 100
    Player.ryo = 0
    Player.scrolls = 0
    Player.invuln = 0
    Player.hazard = false
    Player.fell = false

    Camera.reset(Player)
    palSetTint(World.regions[1].tint)
    palUpdateTint()
    Game.ready = true
end

function Game.frame()
    if not Game.ready then Game.boot() end

    Player.update(Input)
    Camera.update(Player)
    palUpdateTint()

    -- Environmental damage is intentionally simple: one hit per invulnerability
    -- window, immediate recovery at the deterministic spawn, and full hearts on
    -- a life loss.  Combat and enemy contact are owned by later systems.
    if Player.invuln == 0 and (Player.hazard or Player.fell) then
        Player.hearts = max(0, Player.hearts - 1)
        Player.reset(Player.spawnX, Player.spawnY)
        Player.invuln = 90
        Camera.reset(Player)
        if Player.hearts <= 0 then
            Player.maxHearts = max(3, Player.maxHearts)
            Player.hearts = Player.maxHearts
        end
    end

    if renderFrame then renderFrame(Player) end
end

-- ============================================================================
--  20 - RENDER
--
--  Immediate 240x136 presentation: region woodblock sky, three procedural
--  parallax planes, the playable map plane, the ninja, then a compact HUD.
-- ============================================================================

renderFrame = function(player)
    local function skyPalette(region)
        if region == 3 or region == 8 then return B, C, R, PK end
        if region == 5 then return S, W, B, N end
        if region == 6 then return K, R, O, C end
        if region == 7 then return VI, K, F, S end
        return B, S, W, G
    end

    local function drawSky(hi, mid, low, accent)
        local night = Camera.region == 6 or Camera.region == 7 or Camera.region == 8
        cls(hi)
        rect(0, 76, SCREEN_W, 28, mid)
        rect(0, 104, SCREEN_W, 32, low)
        for y = 0, 72, 6 do
            local wave = flr(sin((y + Camera.y * 0.08) * 0.19) * 3)
            for x = -4, SCREEN_W, 12 do
                local px = x + flr(Camera.x * 0.04) + wave
                rect(px, y + flr(Camera.y * 0.025), 6, 1, mid)
            end
        end
        local sx = 196 - flr(Camera.x * 0.025) % 42
        local sy = 20 - flr(Camera.y * 0.018) % 8
        circ(sx, sy, night and 5 or 7, night and N or accent)
        circb(sx, sy, night and 5 or 7, K)
        if night then
            circ(sx + 3, sy - 2, night and 5 or 7, hi)
        else
            pix(sx - 3, sy - 3, W) pix(sx - 2, sy - 3, W)
        end
    end

    local function drawFarMountains(face, shade)
        local base = 105 - flr(Camera.y * 0.045)
        local offset = flr(Camera.x * 0.10) % 72
        for i = -2, 5 do
            local x = i * 72 - offset
            local peak = base - 24 - flr(sin((i + Camera.region) * 1.71) * 8)
            tri(x - 8, base, x + 34, peak, x + 78, base, face)
            line(x + 3, base - 7, x + 34, peak, shade)
            line(x + 34, peak, x + 69, base - 10, shade)
            if Camera.region == 5 then
                line(x + 26, peak + 5, x + 34, peak, W)
                line(x + 34, peak, x + 42, peak + 7, W)
            end
        end
        rect(0, base + 1, SCREEN_W, SCREEN_H - base, shade)
    end

    local function drawMidSilhouettes(face, accent)
        local base = 112 - flr(Camera.y * 0.085)
        local offset = flr(Camera.x * 0.24) % 48
        for i = -2, 7 do
            local x = i * 48 - offset
            if Camera.region == 1 then
                rect(x + 14, base - 15, 2, 15, DK)
                rect(x + 10, base - 20, 10, 2, F)
                rect(x + 12, base - 17, 6, 2, face)
                rect(x + 11, base - 11, 12, 1, face)
            elseif Camera.region == 2 then
                rect(x + 13, base - 23, 2, 23, DK)
                rect(x + 25, base - 19, 2, 19, DK)
                for k = 0, 3 do
                    rect(x + 9, base - 6 - k * 5, 22, 1, face)
                end
                rect(x + 10, base - 23, 8, 2, J)
                rect(x + 22, base - 19, 8, 2, J)
            elseif Camera.region == 3 then
                circ(x + 18, base - 12, 9, face)
                circ(x + 29, base - 15, 7, face)
                rect(x + 22, base - 8, 3, 8, DK)
            elseif Camera.region == 4 or Camera.region == 8 then
                rect(x + 20, base - 26, 2, 26, DK)
                for k = 0, 3 do
                    local yy = base - 6 - k * 6
                    local half = 5 + k * 3
                    tri(x + 21 - half, yy, x + 21, yy - 8, x + 21 + half, yy, face)
                end
                if Camera.region == 8 then
                    rect(x + 8, base - 7, 14, 2, accent)
                    rect(x + 10, base - 7, 2, 7, DK)
                    rect(x + 18, base - 7, 2, 7, DK)
                    rect(x + 28, base - 7, 14, 2, accent)
                    rect(x + 30, base - 7, 2, 7, DK)
                    rect(x + 38, base - 7, 2, 7, DK)
                end
            elseif Camera.region == 5 then
                rect(x + 22, base - 28, 3, 28, DK)
                tri(x + 8, base - 9, x + 24, base - 30, x + 40, base - 9, face)
                rect(x + 20, base - 30, 7, 2, W)
            elseif Camera.region == 6 then
                tri(x + 6, base, x + 25, base - 31, x + 43, base, face)
                line(x + 25, base - 31, x + 19, base - 18, accent)
                line(x + 25, base - 31, x + 31, base - 16, accent)
            elseif Camera.region == 7 then
                for k = 0, 3 do
                    local xx = x + 9 + k * 7
                    line(xx, base, xx + (k % 2 == 0 and -2 or 2), base - 16 - k * 2, face)
                    rect(xx - 3, base - 15 - k * 2, 6, 2, face)
                end
            end
        end
    end

    local function drawNearWinds(face, accent)
        local shift = flr(Camera.x * 0.42)
        for y = 34, 104, 18 do
            local x = (y * 11 + shift * (1 + (y % 3))) % 310 - 45
            line(x, y, x + 28, y - 3, face)
            line(x + 6, y + 1, x + 22, y - 1, accent)
        end
        for i = 0, 3 do
            local x = 24 + i * 63 - shift % 63
            local y = 42 + (i % 2) * 19
            line(x, y, x + 12, y - 4, face)
            line(x + 5, y + 2, x + 17, y - 1, face)
        end
    end

    local hi, mid, low, accent = skyPalette(Camera.region)
    drawSky(hi, mid, low, accent)
    drawFarMountains(Camera.region == 6 and DK or B, Camera.region == 6 and R or K)
    drawMidSilhouettes(Camera.region == 7 and K or F, accent)
    drawNearWinds(Camera.region == 5 and B or DK, Camera.region == 3 and PK or N)

    local srcX = flr(Camera.x / TS)
    local srcY = flr(Camera.y / TS)
    local dstX = flr(Camera.x) - srcX * TS
    local dstY = flr(Camera.y) - srcY * TS
    local mapW = ceil((SCREEN_W - dstX) / TS) + 1
    local mapH = ceil((SCREEN_H - dstY) / TS) + 1
    map(srcX, srcY, mapW, mapH, dstX, dstY, 0)

    if player then
        local shadowX = flr(player.x + player.w * 0.5 - Camera.x)
        local shadowY = flr(player.y + player.h - Camera.y)
        ellib(flr(shadowX + player.w * 0.5), shadowY, max(2, player.w - 1), 1, V)

        local hide = player.invuln and player.invuln > 0
            and flr(player.invuln / 3) % 2 == 1
        if not hide then
            local sx = flr(player.x - Camera.x) - flr((16 - player.w) * 0.5)
            local sy = flr(player.y - Camera.y) - flr((16 - player.h) * 0.5)
            local frame = clamp(player.frame or PF.IDLE, 0, 15)
            spr(blk16(256, frame), sx, sy, 0, 1, player.face < 0 and 1 or 0, 0, 1, 1)
        end
    end

    local maxHearts = clamp(player and player.maxHearts or 3, 1, 5)
    local hearts = clamp(player and player.hearts or maxHearts, 0, maxHearts)
    for i = 0, maxHearts - 1 do
        spr(i < hearts and 451 or 452, 4 + i * 9, 4, 0)
    end

    local stamina = player and player.stamina or 0
    rect(4, 15, 42, 4, V)
    rectb(4, 15, 42, 4, K)
    local staminaW = flr(clamp(stamina, 0, 100) * 0.38)
    rect(6, 17, staminaW, 1, stamina < 20 and O or J)

    local ryo = player and player.ryo or 0
    spr(450, 52, 3, 0)
    print(tostring(ryo), 61, 4, N)

    local name = Camera.regionName or ""
    local nameX = max(92, SCREEN_W - #name * 4 - 6)
    rect(nameX - 3, 1, #name * 4 + 5, 11, V)
    print(name, nameX, 3, N)

    if Camera.changed then
        local bw = #name * 4 + 12
        local bx = flr((SCREEN_W - bw) * 0.5)
        rect(bx, 24, bw, 12, V)
        rectb(bx, 24, bw, 12, R)
        print(name, flr((SCREEN_W - #name * 4) * 0.5), 27, N)
    end
end

-- ============================================================================
--  80 - MAIN : cartridge entry points
-- ============================================================================

function BOOT()
    palApply()
    if Game and Game.boot then Game.boot() end
end

function TIC()
    Frame = Frame + 1
    inputUpdate()
    if Game and Game.frame then
        Game.frame()
    else
        cls(V)
        print("KAGE - modules loading", 40, 64, W)
    end
end


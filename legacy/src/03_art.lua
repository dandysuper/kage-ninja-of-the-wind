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

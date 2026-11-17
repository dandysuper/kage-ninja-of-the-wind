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

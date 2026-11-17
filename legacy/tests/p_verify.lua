-- ============================================================================
--  p_verify - framebuffer pixel verification (headless)
--
--  Runs the production BOOT/Game path in --cli mode, then reads the rendered
--  framebuffer back from VRAM (screen at 0x0000, palette at 0x3FC0) and
--  asserts what the player would actually see: sky bands, terrain, the ninja
--  sprite, and the HUD.  This replaces screenshot-based verification where
--  the host cannot capture the screen.
--
--  usage: tools/test.sh tests/p_verify.lua
-- ============================================================================

local verifyDone = false

local function px(x, y)
    return peek4(0x0000 + (y * SCREEN_W + x))
end

local function countColor(lo, hi)
    local n = 0
    for y = 0, SCREEN_H - 1 do
        for x = 0, SCREEN_W - 1 do
            local c = px(x, y)
            if c >= lo and c <= hi then n = n + 1 end
        end
    end
    return n
end

local function countColorIn(x0, y0, x1, y1, color)
    local n = 0
    for y = y0, y1 do
        for x = x0, x1 do
            if px(x, y) == color then n = n + 1 end
        end
    end
    return n
end

local function palRGB(i)
    local a = 0x3FC0 + i * 3
    return peek(a), peek(a + 1), peek(a + 2)
end

function TIC()
    if verifyDone then return end
    verifyDone = true

    local checks, fails = 0, 0
    local function ck(name, got, want)
        checks = checks + 1
        if got ~= want then
            fails = fails + 1
            trace("FAIL " .. name .. " got=" .. tostring(got) ..
                " want=" .. tostring(want))
        end
    end

    -- Production boot, then a few real frames with neutral input.
    palApply()
    Game.boot()
    Input.x, Input.y = 0, 0
    Input.left, Input.right = false, false
    Input.up, Input.down = false, false
    Input.jumpHeld, Input.atkHeld = false, false
    Input.jump, Input.atk = false, false
    Input.jumpBuf, Input.atkBuf = 0, 0
    for _ = 1, 4 do Game.frame() end

    -- Palette is live in VRAM (BLUE sky at index 2 = 0x3D5C8F).
    local r, g, b = palRGB(B)
    ck("pal.blue.r", r, 0x3D)
    ck("pal.blue.g", g, 0x5C)
    ck("pal.blue.b", b, 0x8F)

    -- Sky: region 1 clears with B (indigo) - the dominant upper-screen color.
    local sky = countColorIn(0, 0, SCREEN_W - 1, 40, B)
    ck("render.sky.px", sky > 2000, true)

    -- Terrain: the map plane must have drawn grass/dirt tiles somewhere in the
    -- lower half.  Grass blocks use J (jade) foliage and BR (brown) earth.
    local greens = countColorIn(0, 60, SCREEN_W - 1, SCREEN_H - 1, J)
    local earth = countColorIn(0, 60, SCREEN_W - 1, SCREEN_H - 1, BR)
    ck("render.terrain.px", greens > 20 or earth > 20, true)

    -- Player: the ninja sprite uses the vermilion scarf (R).  Find it near the
    -- player's screen position.
    local psx = flr(Player.x - Camera.x)
    local psy = flr(Player.y - Camera.y)
    ck("render.player.onscreen", psx >= -16 and psx <= SCREEN_W and
        psy >= -16 and psy <= SCREEN_H, true)
    local scarf = countColorIn(max(0, psx - 10), max(0, psy - 10),
        min(SCREEN_W - 1, psx + 20), min(SCREEN_H - 1, psy + 20), R)
    ck("render.player.sprite", scarf > 0, true)

    -- HUD: three hearts at the top-left use sprite 451 (heart full).
    -- The heart art uses R (vermilion); check the HUD band.
    local hudRed = countColorIn(0, 0, 40, 14, R)
    ck("render.hud.hearts", hudRed > 0, true)

    -- Stamina bar frame (K outline) at 4,15.
    ck("render.hud.stamina", px(4, 15) == K or px(5, 15) == K or px(4, 16) == K, true)

    -- Not a blank screen: at least 4 distinct colors overall.
    local seen = {}
    local distinct = 0
    for y = 0, SCREEN_H - 1, 4 do
        for x = 0, SCREEN_W - 1, 4 do
            local c = px(x, y)
            if not seen[c] then seen[c] = true distinct = distinct + 1 end
        end
    end
    ck("render.distinct", distinct >= 4, true)

    -- Movement renders: walk right for 30 frames, the camera must follow and
    -- the player must stay on screen.
    Input.x, Input.right = 1, true
    for _ = 1, 30 do Game.frame() end
    local psx2 = flr(Player.x - Camera.x)
    ck("render.follow.onscreen", psx2 >= -16 and psx2 <= SCREEN_W, true)
    ck("render.follow.moved", Player.x > World.startX * TS + 8, true)

    -- Emit the framebuffer as a PPM so the rendered scene can be inspected as
    -- an image without any screen-capture permission.  Rows are emitted as
    -- hex strings; tools/ppm.sh reassembles them into build/frame.ppm/png.
    local function dumpFrame(tag)
        trace("PPM-BEGIN " .. tag)
        for y = 0, SCREEN_H - 1 do
            local parts = {}
            for x = 0, SCREEN_W - 1 do
                local pr, pg, pb = palRGB(px(x, y))
                parts[#parts + 1] = string.format("%02x%02x%02x", pr, pg, pb)
            end
            trace(table.concat(parts))
        end
        trace("PPM-END " .. tag)
    end

    dumpFrame("spawn")

    trace("CHECKS=" .. checks .. " FAILS=" .. fails)
    trace("VERIFY-DONE")
    exit()
end

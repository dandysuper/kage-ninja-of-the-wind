-- ============================================================================
--  t_smoke - foundation smoke test
--
--  Test drivers are appended after the game modules, so they run inside the
--  same Lua chunk and can see every chunk-level local. Top-level driver code
--  runs BEFORE BOOT(), so assertions go inside a wrapped TIC() to run on the
--  first real frame.
-- ============================================================================

local TIC_ORIG = TIC
local phase = 0

local fails, checks = 0, 0
local function ck(name, got, want)
    checks = checks + 1
    if got ~= want then
        fails = fails + 1
        trace("FAIL " .. name .. " got=" .. tostring(got) .. " want=" .. tostring(want))
    end
end

local function fillN(nibbase, n, c)
    for y = 0, 7 do for x = 0, 7 do poke4(nibbase + n * 64 + y * 8 + x, c) end end
end

local function countPix(x0, y0, w, h, c)
    local n = 0
    for y = y0, y0 + h - 1 do
        for x = x0, x0 + w - 1 do
            if pix(x, y) == c then n = n + 1 end
        end
    end
    return n
end

local function runTests()
    -- ---- palette (bank 0) ------------------------------------------------
    ck("pal0.r", peek(0x3FC0), 0x0D)
    ck("pal0.g", peek(0x3FC1), 0x0B)
    ck("pal0.b", peek(0x3FC2), 0x14)
    ck("pal8.r", peek(0x3FC0 + 8 * 3), 0xC0)   -- RED 0xC0392B
    ck("pal8.g", peek(0x3FC0 + 8 * 3 + 1), 0x39)
    ck("pal8.b", peek(0x3FC0 + 8 * 3 + 2), 0x2B)

    -- ---- palette (bank 1) : does vbank switch the palette RAM view? ------
    local prev = vbank(1)
    local b1r, b1g, b1b = peek(0x3FC0), peek(0x3FC1), peek(0x3FC2)
    vbank(prev)
    trace("bank1 palette view = " .. b1r .. "," .. b1g .. "," .. b1b)
    ck("pal1.r", b1r, 0x0D)

    -- ---- map bounds ------------------------------------------------------
    mset(239, 135, 7)
    ck("map.max", mget(239, 135), 7)
    mset(0, 0, 3)
    ck("map.00", mget(0, 0), 3)
    local ok1, v1 = pcall(mget, 240, 0)
    local ok2, v2 = pcall(mget, 0, 136)
    trace("oob mget(240,0) ok=" .. tostring(ok1) .. " v=" .. tostring(v1))
    trace("oob mget(0,136) ok=" .. tostring(ok2) .. " v=" .. tostring(v2))

    -- ---- sprite flags ----------------------------------------------------
    fset(100, 2, true)
    ck("flag.set", fget(100, 2), true)
    fset(100, 2, false)
    ck("flag.clear", fget(100, 2), false)

    -- ---- bank 0 / bank 1 sprite separation --------------------------------
    fillN(0x8000, 10, 0)      -- clear block tiles
    fillN(0x8000, 11, 0)
    fillN(0x8000, 26, 0)
    fillN(0x8000, 27, 0)
    fillN(0xC000, 10, 0)
    fillN(0xC000, 11, 0)
    fillN(0xC000, 26, 0)
    fillN(0xC000, 27, 0)

    fillN(0x8000, 10, 4) fillN(0x8000, 11, 4)
    fillN(0x8000, 26, 4) fillN(0x8000, 27, 4)
    cls(0)
    spr16(10, 20, 20, -1)
    ck("spr16.bank0", countPix(20, 20, 16, 16, 4), 256)

    fillN(0xC000, 10, 9) fillN(0xC000, 11, 9)
    fillN(0xC000, 26, 9) fillN(0xC000, 27, 9)
    cls(0)
    spr16(256 + 10, 20, 20, -1)
    ck("spr16.bank1", countPix(20, 20, 16, 16, 9), 256)

    -- ---- api surface -----------------------------------------------------
    ck("fn.key", type(key), "function")
    ck("fn.font", type(font), "function")
    ck("fn.time", type(time), "function")
    ck("const.TS", TS, 8)
    ck("const.MAP_W", MAP_W, 240)

    trace("CHECKS=" .. checks .. " FAILS=" .. fails)
end

function TIC()
    if phase == 0 then
        phase = 1
        TIC_ORIG()
        runTests()
        exit()
        return
    end
    TIC_ORIG()
end

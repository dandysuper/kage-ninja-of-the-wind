-- title:  probe3
-- author: sixth
-- desc:   pixel readback self-test
-- script: lua

local flr = math.floor
local function setpal(i, r, g, b)
    poke(0x3FC0 + i * 3 + 0, r)
    poke(0x3FC0 + i * 3 + 1, g)
    poke(0x3FC0 + i * 3 + 2, b)
end
local function spixN(nibbase, n, x, y, c) poke4(nibbase + n * 64 + y * 8 + x, c) end

local fails, checks = 0, 0
local function ck(name, got, want)
    checks = checks + 1
    if got ~= want then
        fails = fails + 1
        trace("FAIL " .. name .. " got=" .. tostring(got) .. " want=" .. tostring(want))
    end
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

local ran = false

function TIC()
    if ran then return end
    ran = true

    setpal(1, 255, 0, 0)
    -- solid sprite 1 in bank A: color 1 everywhere
    for y = 0, 7 do for x = 0, 7 do spixN(0x8000, 1, x, y, 1) end end

    -- 1) does pix() read back what we draw?
    cls(0)
    rect(10, 10, 4, 4, 3)
    ck("rect-readback", countPix(10, 10, 4, 4, 3), 16)

    -- 2) sprite readback
    cls(0)
    spr(1, 20, 20, -1, 2) -- scale 2, opaque
    ck("spr-readback", countPix(20, 20, 16, 16, 1), 256)

    -- 3) map readback (mset tile 1 at 5,5 -> drawn at screen pos)
    cls(0)
    mset(5, 5, 1)
    map(5, 5, 1, 1, 0, 0, -1)
    ck("map-readback", countPix(0, 0, 8, 8, 1), 64)

    -- 4) text readback at several y positions (explain missing labels)
    cls(0)
    local w1 = print("A", 4, 12, 15)
    local n12 = countPix(4, 12, 8, 8, 15)
    trace("text@12 w=" .. tostring(w1) .. " pix=" .. tostring(n12))
    cls(0)
    local n100 = countPix(4, 100, 1, 1, 15)
    print("B", 4, 100, 15)
    n100 = countPix(4, 100, 8, 8, 15)
    trace("text@100 pix=" .. tostring(n100))
    cls(0)
    print("C", 4, 122, 15)
    local n122 = countPix(4, 122, 8, 8, 15)
    trace("text@122 pix=" .. tostring(n122))

    -- 5) screen size / bounds
    cls(0)
    rect(0, 0, 1, 1, 7)
    ck("corner00", pix(0, 0), 7)
    rect(239, 135, 1, 1, 7)
    ck("corner239x135", pix(239, 135), 7)
    ck("beyond-height", pix(0, 140), 0)

    -- 6) btn / keyp availability
    ck("btn0", type(btn(0)), "boolean")
    ck("btnp0", type(btnp(0)), "boolean")

    trace("CHECKS=" .. checks .. " FAILS=" .. fails)
    exit()
end

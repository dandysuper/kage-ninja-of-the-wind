-- title:  probe
-- author: sixth
-- desc:   pipeline probe
-- script: lua

-- helper aliases (this build lacks TIC-80's flr/sin/cos/... globals)
local flr, ceil, abs, sqrt = math.floor, math.ceil, math.abs, math.sqrt
local sin, cos, atan2, pi = math.sin, math.cos, math.atan, math.pi
local min, max, fmod = math.min, math.max, math.fmod
local function mid(a, b, c) return max(min(a, b), min(max(a, b), c)) end
local function rnd(n) n = n or 1 if n == 0 then return math.random() end return math.random() * n end

local function setpal(i, r, g, b)
    poke(0x3FC0 + i * 3 + 0, r)
    poke(0x3FC0 + i * 3 + 1, g)
    poke(0x3FC0 + i * 3 + 2, b)
end

local function spixN(nibbase, n, x, y, c)
    poke4(nibbase + n * 64 + y * 8 + x, c)
end

-- draw left half red, right half border etc, so orientation is obvious
local function patternspr(nibbase, n, ca, cb)
    for y = 0, 7 do
        for x = 0, 7 do
            local v = ca
            if y < 4 then v = cb end
            if x == 0 and y == 0 then v = 4 end
            if x == 7 and y == 7 then v = 5 end
            spixN(nibbase, n, x, y, v)
        end
    end
end

function BOOT()
    trace("mid(1,2,3)=" .. tostring(mid(1, 2, 3)))
    trace("flr(5.7)=" .. tostring(flr(5.7)) .. " sin(0)=" .. tostring(sin(0)) ..
        " rnd=" .. tostring(rnd(10)) .. " pi=" .. tostring(pi))
    setpal(1, 255, 0, 0)
    setpal(2, 0, 255, 0)
    setpal(3, 40, 60, 255)
    setpal(4, 255, 255, 0)
    setpal(5, 255, 0, 255)
    setpal(15, 255, 255, 255)

    patternspr(0x8000, 1, 1, 2)  -- bank candidate A (byte 0x4000)
    patternspr(0xC000, 2, 5, 4)  -- bank candidate B (byte 0x6000)
    patternspr(0x8000, 3, 3, 15) -- A only
end

local t = 0

function TIC()
    t = t + 1
    cls(0)
    setpal(1, 255, 0, 0)
    setpal(2, 0, 255, 0)
    setpal(3, 40, 60, 255)
    setpal(4, 255, 255, 0)
    setpal(5, 255, 0, 255)

    print("PROBE  t=" .. t, 2, 2, 15)
    -- scale 8 so pixels are obvious: each 8x8 sprite -> 64x64
    spr(1, 4, 20, 0, 8)   -- A: top half green, bottom red
    spr(2, 72, 20, 0, 8)  -- B: top half yellow, bottom magenta
    spr(3, 140, 20, 0, 8) -- A: top half white, bottom blue

    print("A(b0x4000)", 4, 12, 11)
    print("B(b0x6000)", 72, 12, 11)
    print("A2", 140, 12, 11)

    rect(4, 96, 20, 20, 3)
    print("rect ok", 30, 100, 15)
    print("hw 240x136. mid=" .. mid(1, 2, 3), 4, 122, 11)
end

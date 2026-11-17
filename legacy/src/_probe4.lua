-- title:  probe4
-- author: sixth
-- desc:   bank1 / flags / perf
-- script: lua

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

local phase = 0
local t0, frames = 0, 0
local NSPR = 0
local results = {}

function TIC()
    if phase == 0 then
        phase = 1

        -- A) bank1 sprite: sprite 1 of bank1 == global index 256
        for y = 0, 7 do for x = 0, 7 do spixN(0xC000, 1, x, y, 6) end end
        cls(0)
        spr(256 + 1, 10, 10, -1, 4)
        local n = countPix(10, 10, 32, 32, 6)
        ck("bank1-spr-257", n, 1024)

        -- B) bank0 sprite same index 257 -> should be different art
        cls(0)
        spr(1, 10, 10, -1, 4)
        ck("bank0-spr-1-empty", countPix(10, 10, 32, 32, 6), 0)

        -- C) sprite flags
        fset(5, 3, true)
        ck("fset-fget-true", fget(5, 3), true)
        ck("fset-fget-false", fget(5, 4), false)
        fset(5, 3, false)
        ck("fset-clear", fget(5, 3), false)

        -- D) tile flag on a map tile id
        fset(20, 0, true)
        ck("tile-flag-20", fget(20, 0), true)

        trace("CHECKS=" .. checks .. " FAILS=" .. fails)
        phase = 2
        NSPR = 100
        t0 = time()
        frames = 0
        return
    end

    if phase == 2 or phase == 3 or phase == 4 then
        cls(0)
        for i = 1, NSPR do
            spr(1, (i * 7) % 232, (i * 13) % 128, 0)
        end
        for i = 1, 200 do
            local x = (i * 11) % 240
            rect(x, 100, 3, 3, i % 16)
        end
        frames = frames + 1
        local el = time() - t0
        if el >= 60 then
            results[#results + 1] = "N=" .. NSPR .. " fps=" .. math.floor(frames / (el / 60))
            NSPR = NSPR + 200
            if NSPR > 700 then
                trace("PERF " .. table.concat(results, " | "))
                phase = 9
                exit()
            end
            t0 = time()
            frames = 0
            phase = phase + 1
            if phase > 4 then phase = 2 end
            if NSPR == 300 then phase = 2 end
            if NSPR == 500 then phase = 2 end
            if NSPR == 700 then phase = 2 end
        end
        return
    end
end

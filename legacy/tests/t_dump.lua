-- ============================================================================
--  t_dump - print sprite blocks as text so art can be inspected exactly
-- ============================================================================

local built = false
local done = false

local function nibOf(idx)
    if idx >= 256 then return 0xC000 + (idx - 256) * 64 end
    return 0x8000 + idx * 64
end

local function dumpIdx(idx, label)
    trace("--- " .. label .. " (sprite " .. idx .. ") ---")
    local base = nibOf(idx)
    for y = 0, 15 do
        local s = ""
        for x = 0, 15 do
            local sx = (x >= 8) and 1 or 0
            local sy = (y >= 8) and 16 or 0
            s = s .. string.format("%x", peek4(base + (sx + sy) * 64 + (y % 8) * 8 + (x % 8)))
        end
        trace(string.format("%2d|%s|", y, s))
    end
end

local function run()
    genTerrain()
    genProps()
    genChars(0)
    dumpIdx(256 + 0 * 4, "player idle")
    dumpIdx(256 + 1 * 4, "player run1")
    dumpIdx(320 + 0, "oni f0")
    dumpIdx(448, "kunai")
end

function TIC()
    if done then return end
    done = true
    run()
    trace("DUMP-DONE")
    exit()
end

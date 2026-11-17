-- ============================================================================
--  t_paint - controlled 16x16 canvas experiment
--  Paints four distinct corner markers plus a diagonal, then dumps the four
--  sprites of the block individually.
-- ============================================================================

local done = false

local function dump8(idx, label)
    local base = (idx >= 256) and (0xC000 + (idx - 256) * 64) or (0x8000 + idx * 64)
    local rows = {}
    for y = 0, 7 do
        local s = ""
        for x = 0, 7 do s = s .. string.format("%x", peek4(base + y * 8 + x)) end
        rows[#rows + 1] = s
    end
    trace(label .. "(" .. idx .. ") " .. table.concat(rows, "/"))
end

local function run()
    artBegin16(256)
    artClear(0)
    artP(0, 0, 1)      -- top-left of canvas
    artP(7, 0, 2)      -- top-right of top-left sprite
    artP(8, 0, 3)      -- top-left of top-right sprite
    artP(15, 0, 4)     -- top-right of canvas
    artP(0, 7, 5)      -- bottom-left of top-left sprite
    artP(0, 8, 6)      -- top-left of bottom-left sprite
    artP(15, 15, 7)
    artP(7, 7, 8)
    artP(8, 8, 9)

    dump8(256, "TL")
    dump8(257, "TR")
    dump8(272, "BL")
    dump8(273, "BR")
end

function TIC()
    if done then return end
    done = true
    run()
    trace("PAINT-DONE")
    exit()
end

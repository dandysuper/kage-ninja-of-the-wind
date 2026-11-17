-- ============================================================================
--  p_chars - preview the character atlas, 7 per row at scale 2
--  Block indices come from blk16() so preview and renderer always agree.
-- ============================================================================

local built = false
local idx = {}

local function add(base, k) idx[#idx + 1] = blk16(base, k) end

local function build()
    for f = 0, 15 do add(256, f) end          -- player
    add(320, 0) add(320, 1) add(320, 2) add(320, 3)   -- oni
    add(328, 0) add(328, 1)                            -- tengu
    add(336, 0) add(336, 1)                            -- yurei
    add(344, 0) add(344, 1)                            -- rogue ninja
    add(352, 0) add(352, 1)                            -- kappa
    add(360, 0) add(360, 1)                            -- kitsune
    add(384, 0) add(384, 1) add(384, 2)                -- boss
end

function TIC()
    if not built then
        built = true
        genTerrain()
        genProps()
        genChars(0)
        build()
    end
    cls(1)
    for i, id in ipairs(idx) do
        local cx = ((i - 1) % 7) * 34 + 2
        local cy = flr((i - 1) / 7) * 34 + 2
        rect(cx, cy, 32, 32, 2)
        spr(id, cx, cy, V, 2, 0, 0, 2, 2)
    end
end

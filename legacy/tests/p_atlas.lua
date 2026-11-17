-- ============================================================================
--  p_atlas - preview driver: paint the whole sprite sheet, 30 tiles per row,
--            1:1 so the entire 512-slot atlas fits one screen.
-- ============================================================================

local TIC_ORIG = TIC
local built = false

function TIC()
    if not built then
        built = true
        genTerrain()
    end

    cls(1)
    for i = 0, 509 do
        local cx = (i % 30) * 8
        local cy = flr(i / 30) * 8
        if ((i % 30) + flr(i / 30)) % 2 == 0 then rect(cx, cy, 8, 8, 2) end
        spr(i, cx, cy, -1)
    end
end

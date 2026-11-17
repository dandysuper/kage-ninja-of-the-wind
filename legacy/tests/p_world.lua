-- ============================================================================
--  p_world - whole-world overview: one screen pixel per map tile
--
--  Draws the entire 240x136 world in a single frame so the shape of the
--  terrain, the caves and the regions can be judged at a glance. Colour rules:
--    air            -> clear (sky)
--    solid terrain  -> biome colour, brightened when exposed to air
--    liquids        -> blue / orange / green
--    decor tiles    -> dim biome colour
--    hazards        -> red
--  A marker shows the player spawn and each shrine.
-- ============================================================================

local built = false

local BIOME_COL = {
    [1] = J,  [2] = F,  [3] = J,  [4] = B,  [5] = N,
    [6] = S,  [7] = C,  [8] = F,  [9] = W,  [10] = VI,
}

local function tileColor(t)
    if t == 0 then return nil end
    if t >= 89 and t <= 94 then return S end          -- water
    if t >= 95 and t <= 97 then return O end          -- lava
    if t >= 98 and t <= 100 then return F end         -- sludge
    if t <= 80 then
        local b = flr((t - 1) / 8) + 1
        return BIOME_COL[b] or N
    end
    if t >= 81 and t <= 88 then return G end          -- platforms
    return nil                                        -- decor: handled below
end

local function clearDark(t) return t >= 101 and t <= 210 end

function TIC()
    if not built then
        built = true
        genTerrain()
        genProps()
        genChars(0)
        worldGen()

        cls(B)
        for y = 0, MAP_H - 1 do
            for x = 0, MAP_W - 1 do
                local t = mget(x, y)
                local c = tileColor(t)
                if c then
                    pix(x, y, c)
                elseif clearDark(t) then
                    -- faint marker for decor so landmarks are visible
                    local ex = (y % 2 == 0)
                    if ex then pix(x, y, K) end
                end
                if fget(mget(x, y), F_HAZARD) and t > 0 then pix(x, y, R) end
            end
        end

        -- spawn marker
        rect(World.startX - 1, World.startY - 1, 3, 3, W)
        -- shrine markers
        for _, s in ipairs(World.spawns) do
            if s.kind == "shrine" then rect(s.x - 1, s.y - 2, 3, 3, G) end
            if s.kind == "boss" then rect(s.x - 1, s.y - 1, 3, 3, PK) end
        end
        rectb(0, 0, 240, 136, K)
    end
end

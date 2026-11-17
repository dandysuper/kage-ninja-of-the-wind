-- ============================================================================
--  t_world - structural checks on the generated world
-- ============================================================================

local done = false

local function solidAt(x, y)
    local t = mget(x, y)
    if t == 0 then return false end
    return fget(t, F_SOLID) or (t >= 1 and t <= 80) or t == T.BRIDGE_A or t == T.BRIDGE_B
end

local function run()
    -- BOOT now builds the atlas and world through Game.boot(). Reuse that
    -- deterministic world when the driver is running in the integrated cart;
    -- older standalone fixtures still get the full explicit setup.
    if not (Game and Game.worldReady) then
        genTerrain()
        genProps()
        genChars(0)
        worldGen()
    end

    local solid, decor, hazard, liquid, maxTile = 0, 0, 0, 0, 0
    for y = 0, MAP_H - 1 do
        for x = 0, MAP_W - 1 do
            local t = mget(x, y)
            if t > maxTile then maxTile = t end
            if t > 0 then
                if t <= 80 then solid = solid + 1
                elseif t >= 89 and t <= 100 then liquid = liquid + 1
                else decor = decor + 1 end
                if fget(t, F_HAZARD) then hazard = hazard + 1 end
            end
        end
    end
    trace("tiles solid=" .. solid .. " decor=" .. decor .. " liquid=" .. liquid ..
        " hazard=" .. hazard .. " maxTile=" .. maxTile)
    trace("spawns=" .. #World.spawns .. " start=" .. World.startX .. "," .. World.startY)

    -- start must be in open air with ground underneath
    local sx, sy = World.startX, World.startY
    trace("start tile=" .. mget(sx, sy) .. " start+1=" .. mget(sx, sy + 1) ..
        " ground=" .. mget(sx, World.surfY[sx + 1]))
    local found = false
    for y = sy, sy + 8 do if solidAt(sx, y) then found = true break end end
    trace("ground within 8 below start: " .. tostring(found))

    -- no bottomless pits on the surface line: walking right from the start,
    -- every column must have something to stand on within 12 tiles
    local gaps = 0
    for x = 1, MAP_W - 2 do
        local gy = World.surfY[x + 1]
        local ok = false
        for y = gy, gy + 12 do if solidAt(x, y) or mget(x, y) ~= 0 then ok = true break end end
        if not ok then gaps = gaps + 1 end
    end
    trace("surface gaps=" .. gaps)

    -- tile ids must stay inside the painted atlas
    trace("maxTile ok: " .. tostring(maxTile <= 210))

    -- every declared spawn must sit in the map
    local badSpawn = 0
    for _, s in ipairs(World.spawns) do
        if s.x < 1 or s.x > MAP_W - 2 or s.y < 1 or s.y > MAP_H - 2 then badSpawn = badSpawn + 1 end
    end
    trace("badSpawns=" .. badSpawn)

    -- region check: how tall is the surface relief
    local lo, hi = 999, 0
    for x = 1, MAP_W do
        local v = World.surfY[x]
        if v < lo then lo = v end
        if v > hi then hi = v end
    end
    trace("surface relief y=" .. lo .. ".." .. hi)
    trace("WORLD-DONE")
end

function TIC()
    if done then return end
    done = true
    run()
    exit()
end

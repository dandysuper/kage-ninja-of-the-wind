-- ============================================================================
--  t_tiles - deterministic flag, overlap, and swept-AABB checks
-- ============================================================================

local TIC_ORIG = TIC
local done = false
local checks, fails = 0, 0
local saved = {}

local function ck(name, got, want)
    checks = checks + 1
    if got ~= want then
        fails = fails + 1
        trace("FAIL " .. name .. " got=" .. tostring(got) .. " want=" .. tostring(want))
    end
end

local function near(name, got, want, eps)
    checks = checks + 1
    eps = eps or 0.0001
    if abs(got - want) > eps then
        fails = fails + 1
        trace("FAIL " .. name .. " got=" .. tostring(got) .. " want=" .. tostring(want))
    end
end

local function put(x, y, id)
    if saved[x] == nil then saved[x] = {} end
    if saved[x][y] == nil then saved[x][y] = mget(x, y) end
    mset(x, y, id)
end

local function clearArea(x0, y0, x1, y1)
    for y = y0, y1 do for x = x0, x1 do mset(x, y, 0) end end
end

local function run()
    genTerrain()
    genProps()
    genChars(0)

    -- Flag registration and flag-driven overlap queries.  Put each tile in a
    -- known map cell first; the flag store belongs to the tile id, while the
    -- spatial query belongs to the cell that contains it.
    put(1, 1, 1)
    put(2, 1, T.BRIDGE_A)
    put(3, 1, T.FLOOR_WOOD)
    put(4, 1, T.SPIKE_BASE)
    ck("solid.terrain", Tiles.flagAtPx(TS + 1, TS + 1, F_SOLID), true)
    ck("solid.bridge", Tiles.flagAtPx(2 * TS + 1, TS + 1, F_SOLID), true)
    ck("solid.floor", Tiles.flagAtPx(3 * TS + 1, TS + 1, F_SOLID), true)
    ck("solid.spike-base", Tiles.flagAtPx(4 * TS + 1, TS + 1, F_SOLID), true)
    put(4, 4, T.WATER_BODY)
    fset(T.WATER_BODY, F_WATER, true)
    ck("flag.water", Tiles.rectHitsFlag({ x = 32.5, y = 32.5, w = 1, h = 1 }, F_WATER), true)
    put(5, 4, T.SPIKES)
    fset(T.SPIKES, F_HAZARD, true)
    ck("flag.hazard", Tiles.rectHitsFlag({ x = 40.5, y = 32.5, w = 1, h = 1 }, F_HAZARD), true)
    put(6, 4, T.LADDER_A)
    fset(T.LADDER_A, F_CLIMB, true)
    ck("flag.climb", Tiles.rectHitsFlag({ x = 48.5, y = 32.5, w = 1, h = 1 }, F_CLIMB), true)
    ck("solid.overlap", Tiles.rectHitsSolid({ x = TS + 1.5, y = TS + 1.5, w = 1, h = 1 }), true)
    ck("solid.outside", Tiles.rectHitsSolid({ x = 8.5, y = 1.5, w = 1, h = 1 }), false)
    ck("oob.atPx", Tiles.atPx(-1, -1), 0)
    ck("oob.flag", Tiles.flagAtPx(WORLD_W + 1, 1, F_SOLID), false)

    -- One-way upward pass, descending landing, and explicit drop-through.
    clearArea(10, 3, 20, 9)
    put(12, 6, T.PLAT_WOOD_L)
    local body = { x = 96.5, y = 47, w = 6, h = 14, vx = 0, vy = 0 }
    local up = Tiles.moveBody(body, 0, -8)
    ck("one-way.up.pass", up.hitY, false)
    body.y = 34
    local land = Tiles.moveBody(body, 0, 8)
    ck("one-way.land", land.hitY, true)
    ck("one-way.normal", land.normalY, -1)
    near("one-way.snap", body.y, 34)
    local drop = Tiles.moveBody(body, 0, 4, { dropThrough = true })
    ck("one-way.drop", drop.hitY, false)
    near("one-way.drop.y", body.y, 38)

    -- Swept wall and floor contact, including a multi-tile dash-sized step.
    clearArea(24, 3, 32, 12)
    for y = 4, 9 do put(28, y, T.SPIKE_BASE) end
    body = { x = 200, y = 40, w = 6, h = 14, vx = 4, vy = 0 }
    local wall = Tiles.moveBody(body, body.vx * 8, 0)
    ck("sweep.wall.hit", wall.hitX, true)
    ck("sweep.wall.normal", wall.normalX, -1)
    near("sweep.wall.x", body.x, 28 * TS - body.w)
    clearArea(34, 8, 40, 10)
    for x = 34, 40 do put(x, 10, T.BRIDGE_A) end
    body = { x = 34 * TS + 1, y = 10 * TS - body.h - 10, w = 6, h = 14, vx = 0, vy = 4 }
    local floor = Tiles.moveBody(body, 0, body.vy * 8)
    ck("sweep.floor.hit", floor.hitY, true)
    ck("sweep.floor.normal", floor.normalY, -1)
    ck("sweep.floor.grounded", floor.grounded, true)
    near("sweep.floor.y", body.y, 10 * TS - body.h)

    trace("CHECKS=" .. checks .. " FAILS=" .. fails)
end

function TIC()
    if done then return end
    done = true
    run()
    exit()
end

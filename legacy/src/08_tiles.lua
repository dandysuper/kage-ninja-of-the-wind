-- ============================================================================
--  08 - TILE COLLISION
--
--  Collision is flag-driven.  The registration below is the only tile-id
--  policy in this module; all later queries use the flag store.
-- ============================================================================

local Tiles = {}

function Tiles.registerCollisionFlags()
    for tileId = 1, 80 do fset(tileId, F_SOLID, true) end
    for tileId = 81, 88 do fset(tileId, F_ONEWAY, true) end
    fset(T.SPIKE_BASE, F_SOLID, true)
    for tileId = T.BRIDGE_A, T.FLOOR_WOOD_R do fset(tileId, F_SOLID, true) end
end

Tiles.registerCollisionFlags()

function Tiles.inBounds(tx, ty)
    return tx >= 0 and ty >= 0 and tx < MAP_W and ty < MAP_H
end

function Tiles.at(tx, ty)
    if not Tiles.inBounds(tx, ty) then return 0 end
    return mget(tx, ty)
end

-- Pixel coordinates are half-open: x=8 belongs to tile column 1.
function Tiles.atPx(px, py)
    if px == nil or py == nil then return 0 end
    return Tiles.at(flr(px / TS), flr(py / TS))
end

function Tiles.tileFlag(tx, ty, flag)
    if flag == nil or not Tiles.inBounds(tx, ty) then return false end
    return fget(mget(tx, ty), flag) == true
end

function Tiles.flagAtPx(px, py, flag)
    if flag == nil or px == nil or py == nil then return false end
    return Tiles.tileFlag(flr(px / TS), flr(py / TS), flag)
end

function Tiles.solidAtPx(px, py)
    return Tiles.flagAtPx(px, py, F_SOLID)
end

-- Tiny epsilon keeps exact tile edges out of the neighbouring cell.
function Tiles.rectHitsFlag(rect, flag)
    if rect == nil or flag == nil then return false end
    local x0, y0 = tonumber(rect.x), tonumber(rect.y)
    local w, h = tonumber(rect.w), tonumber(rect.h)
    if x0 == nil or y0 == nil or w == nil or h == nil or w <= 0 or h <= 0 then
        return false
    end
    local eps = 0.000001
    local x1, y1 = x0 + w, y0 + h
    local tx0 = flr(x0 / TS)
    local tx1 = flr((x1 - eps) / TS)
    local ty0 = flr(y0 / TS)
    local ty1 = flr((y1 - eps) / TS)
    for ty = ty0, ty1 do
        for tx = tx0, tx1 do
            if Tiles.tileFlag(tx, ty, flag) then return true end
        end
    end
    return false
end

function Tiles.rectHitsSolid(rect)
    return Tiles.rectHitsFlag(rect, F_SOLID)
end

function Tiles.rectHitsOneWay(rect)
    return Tiles.rectHitsFlag(rect, F_ONEWAY)
end

function Tiles.rectHitsFlagOr(rect, first, second)
    return Tiles.rectHitsFlag(rect, first) or Tiles.rectHitsFlag(rect, second)
end

function Tiles.wallSideForRect(rect, face)
    if rect == nil then return 0 end
    if face >= 0 and Tiles.rectHitsSolid({ x = rect.x + rect.w, y = rect.y, w = 1, h = rect.h }) then
        return 1
    end
    if face <= 0 and Tiles.rectHitsSolid({ x = rect.x - 1, y = rect.y, w = 1, h = rect.h }) then
        return -1
    end
    return 0
end

function Tiles.newMoveResult()
    return {
        x = 0, y = 0,
        dx = 0, dy = 0,
        hitX = false, hitY = false,
        blockedX = false, blockedY = false,
        tileHitX = false, tileHitY = false,
        worldHitX = false, worldHitY = false,
        normalX = 0, normalY = 0,
        nx = 0, ny = 0,
        impactX = 0, impactY = 0,
        axis = "none",
        grounded = false, onGround = false,
        wall = 0, onWall = false,
        oneWay = false,
        outOfBounds = false, outX = false, outY = false,
        fell = false,
    }
end

-- Axis-separated swept AABB movement.  The body is mutated in x/y; caller
-- owns velocity policy.  One-way tiles are descending-only and are skipped by
-- opts.dropThrough for a deliberate down+jump drop.
function Tiles.moveBody(body, dx, dy, opts)
    opts = opts or {}
    local result = Tiles.newMoveResult()
    if body == nil then return result end

    local w = tonumber(body.w) or 0
    local h = tonumber(body.h) or 0
    if w <= 0 or h <= 0 then
        result.x, result.y = body.x or 0, body.y or 0
        body.x, body.y = result.x, result.y
        return result
    end

    local maxX = max(0, WORLD_W - w)
    local maxY = max(0, WORLD_H - h)
    local startX = clamp(tonumber(body.x) or 0, 0, maxX)
    local startY = clamp(tonumber(body.y) or 0, 0, maxY)
    body.x, body.y = startX, startY
    if dx == nil then dx = body.vx or 0 end
    if dy == nil then dy = body.vy or 0 end
    dx, dy = tonumber(dx) or 0, tonumber(dy) or 0

    local desiredX = startX + dx
    local desiredY = startY + dy
    local boundedX = clamp(desiredX, 0, maxX)
    local boundedY = clamp(desiredY, 0, maxY)
    if boundedX ~= desiredX then
        result.outOfBounds, result.outX = true, true
        result.worldHitX, result.hitX = true, true
        result.normalX, result.nx = dx > 0 and -1 or 1, dx > 0 and -1 or 1
    end
    if boundedY ~= desiredY then
        result.outOfBounds, result.outY = true, true
        result.worldHitY, result.hitY = true, true
        result.normalY, result.ny = dy > 0 and -1 or 1, dy > 0 and -1 or 1
        if dy > 0 then result.fell = true end
    end

    local eps = 0.000001
    local x, y = boundedX, startY

    -- Horizontal sweep.
    if dx ~= 0 then
        local limit = boundedX
        local ty0 = flr(startY / TS)
        local ty1 = flr((startY + h - eps) / TS)
        if dx > 0 then
            local first = flr((startX + w) / TS)
            local last = flr((desiredX + w + eps) / TS)
            for tx = first, last do
                local tileLeft = tx * TS
                if startX + w <= tileLeft + eps and desiredX + w >= tileLeft - eps then
                    for ty = ty0, ty1 do
                        if Tiles.tileFlag(tx, ty, F_SOLID) then
                            local candidate = tileLeft - w
                            if candidate < limit then
                                limit = candidate
                                result.hitX, result.tileHitX = true, true
                                result.normalX, result.nx = -1, -1
                                result.wall = 1
                            end
                            break
                        end
                    end
                end
            end
        else
            local first = flr(startX / TS) - 1
            local last = flr((desiredX + eps) / TS)
            for tx = first, last, -1 do
                local tileRight = (tx + 1) * TS
                if startX >= tileRight - eps and desiredX <= tileRight + eps then
                    for ty = ty0, ty1 do
                        if Tiles.tileFlag(tx, ty, F_SOLID) then
                            local candidate = tileRight
                            if candidate > limit then
                                limit = candidate
                                result.hitX, result.tileHitX = true, true
                                result.normalX, result.nx = 1, 1
                                result.wall = -1
                            end
                            break
                        end
                    end
                end
            end
        end
        x = clamp(limit, 0, maxX)
    end
    body.x = x
    result.x = x

    -- Vertical sweep after horizontal movement, so corners cannot tunnel.
    local yLimit = boundedY
    if dy ~= 0 then
        local tx0 = flr(x / TS)
        local tx1 = flr((x + w - eps) / TS)
        if dy > 0 then
            local first = flr((startY + h) / TS)
            local last = flr((desiredY + h + eps) / TS)
            for ty = first, last do
                local tileTop = ty * TS
                -- One-way platforms only catch a body whose previous feet
                -- were at or above the platform top.
                if startY + h <= tileTop + eps and desiredY + h >= tileTop - eps then
                    for tx = tx0, tx1 do
                        local solid = Tiles.tileFlag(tx, ty, F_SOLID)
                        local oneWay = not opts.dropThrough and Tiles.tileFlag(tx, ty, F_ONEWAY)
                        if solid or oneWay then
                            local candidate = tileTop - h
                            if candidate < yLimit then
                                yLimit = candidate
                                result.hitY, result.tileHitY = true, true
                                result.normalY, result.ny = -1, -1
                                result.oneWay = result.oneWay or oneWay
                            end
                            break
                        end
                    end
                end
            end
        else
            local first = flr(startY / TS) - 1
            local last = flr((desiredY - eps) / TS)
            for ty = first, last, -1 do
                local tileBottom = (ty + 1) * TS
                if startY >= tileBottom - eps and desiredY <= tileBottom + eps then
                    for tx = tx0, tx1 do
                        if Tiles.tileFlag(tx, ty, F_SOLID) then
                            local candidate = tileBottom
                            if candidate > yLimit then
                                yLimit = candidate
                                result.hitY, result.tileHitY = true, true
                                result.normalY, result.ny = 1, 1
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    y = clamp(yLimit, 0, maxY)
    body.y = y
    result.y = y
    result.dx, result.dy = body.x - startX, body.y - startY
    result.blockedX, result.blockedY = result.hitX, result.hitY
    result.grounded = result.tileHitY and result.normalY < 0
    result.onGround = result.grounded
    result.onWall = result.tileHitX and result.wall ~= 0
    result.impactX, result.impactY = result.normalX, result.normalY
    if result.hitX and result.hitY then
        result.axis = "xy"
    elseif result.hitX then
        result.axis = "x"
    elseif result.hitY then
        result.axis = "y"
    end
    return result
end

Tiles.sweepMove = Tiles.moveBody
Tiles.sweepAABB = Tiles.moveBody
Tiles.moveAABB = Tiles.moveBody

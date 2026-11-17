-- ============================================================================
--  10 - CAMERA
--
--  Fixed-step, deterministic pixel follow camera. The 2.5D scene stays anchored
--  to the player while the primitive background receives Camera.x/y as its
--  parallax source.
-- ============================================================================

local Camera = {}

Camera.x, Camera.y = 0, 0
Camera.region, Camera.regionName = 1, ""
Camera.lookX, Camera.lookY = 0, 0
Camera.tint, Camera.changed = "none", false

Camera.reset = function(player)
    local centerX = player.x + player.w * 0.5
    local centerY = player.y + player.h * 0.5
    local maxX, maxY = max(0, WORLD_W - SCREEN_W), max(0, WORLD_H - SCREEN_H)

    Camera.lookX, Camera.lookY = 0, 0
    Camera.x = clamp(centerX - SCREEN_W * 0.5, 0, maxX)
    Camera.y = clamp(centerY - SCREEN_H * 0.5, 0, maxY)

    local column = clamp(flr(centerX / TS) + 1, 1, MAP_W)
    local oldRegion = Camera.region
    Camera.region = World.regOf[column] or 1
    local region = World.regions[Camera.region] or {}
    Camera.regionName = region.name or ""
    Camera.tint = region.tint or "none"
    Camera.changed = Camera.region ~= oldRegion

    palSetTint(Camera.tint)
    return Camera.changed, Camera.region
end

Camera.update = function(player, snap)
    local centerX = player.x + player.w * 0.5
    local centerY = player.y + player.h * 0.5
    local maxX, maxY = max(0, WORLD_W - SCREEN_W), max(0, WORLD_H - SCREEN_H)

    -- Keep anticipation deliberately small: enough to reveal travel direction,
    -- not enough to make the player appear to slide away from screen centre.
    local targetLookX = clamp((player.vx or 0) * 1.15, -14, 14)
    local targetLookY = clamp((player.vy or 0) * 0.55, -8, 8)
    local lookBlend = snap and 1 or 0.12
    Camera.lookX = lerp(Camera.lookX or 0, targetLookX, lookBlend)
    Camera.lookY = lerp(Camera.lookY or 0, targetLookY, lookBlend)

    local targetX = clamp(centerX + Camera.lookX - SCREEN_W * 0.5, 0, maxX)
    local targetY = clamp(centerY + Camera.lookY - SCREEN_H * 0.5, 0, maxY)
    local followBlend = snap and 1 or 0.15
    Camera.x = lerp(Camera.x or targetX, targetX, followBlend)
    Camera.y = lerp(Camera.y or targetY, targetY, 0.12)
    if snap then Camera.y = targetY end
    Camera.x = clamp(Camera.x, 0, maxX)
    Camera.y = clamp(Camera.y, 0, maxY)

    local column = clamp(flr(centerX / TS) + 1, 1, MAP_W)
    local oldRegion = Camera.region
    Camera.region = World.regOf[column] or 1
    local region = World.regions[Camera.region] or {}
    Camera.regionName = region.name or ""
    Camera.tint = region.tint or "none"
    Camera.changed = Camera.region ~= oldRegion

    palSetTint(Camera.tint)
    return Camera.changed, Camera.region
end

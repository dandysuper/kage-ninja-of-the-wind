-- ============================================================================
--  20 - RENDER
--
--  Immediate 240x136 presentation: region woodblock sky, three procedural
--  parallax planes, the playable map plane, the ninja, then a compact HUD.
-- ============================================================================

renderFrame = function(player)
    local function skyPalette(region)
        if region == 3 or region == 8 then return B, C, R, PK end
        if region == 5 then return S, W, B, N end
        if region == 6 then return K, R, O, C end
        if region == 7 then return VI, K, F, S end
        return B, S, W, G
    end

    local function drawSky(hi, mid, low, accent)
        local night = Camera.region == 6 or Camera.region == 7 or Camera.region == 8
        cls(hi)
        rect(0, 76, SCREEN_W, 28, mid)
        rect(0, 104, SCREEN_W, 32, low)
        for y = 0, 72, 6 do
            local wave = flr(sin((y + Camera.y * 0.08) * 0.19) * 3)
            for x = -4, SCREEN_W, 12 do
                local px = x + flr(Camera.x * 0.04) + wave
                rect(px, y + flr(Camera.y * 0.025), 6, 1, mid)
            end
        end
        local sx = 196 - flr(Camera.x * 0.025) % 42
        local sy = 20 - flr(Camera.y * 0.018) % 8
        circ(sx, sy, night and 5 or 7, night and N or accent)
        circb(sx, sy, night and 5 or 7, K)
        if night then
            circ(sx + 3, sy - 2, night and 5 or 7, hi)
        else
            pix(sx - 3, sy - 3, W) pix(sx - 2, sy - 3, W)
        end
    end

    local function drawFarMountains(face, shade)
        local base = 105 - flr(Camera.y * 0.045)
        local offset = flr(Camera.x * 0.10) % 72
        for i = -2, 5 do
            local x = i * 72 - offset
            local peak = base - 24 - flr(sin((i + Camera.region) * 1.71) * 8)
            tri(x - 8, base, x + 34, peak, x + 78, base, face)
            line(x + 3, base - 7, x + 34, peak, shade)
            line(x + 34, peak, x + 69, base - 10, shade)
            if Camera.region == 5 then
                line(x + 26, peak + 5, x + 34, peak, W)
                line(x + 34, peak, x + 42, peak + 7, W)
            end
        end
        rect(0, base + 1, SCREEN_W, SCREEN_H - base, shade)
    end

    local function drawMidSilhouettes(face, accent)
        local base = 112 - flr(Camera.y * 0.085)
        local offset = flr(Camera.x * 0.24) % 48
        for i = -2, 7 do
            local x = i * 48 - offset
            if Camera.region == 1 then
                rect(x + 14, base - 15, 2, 15, DK)
                rect(x + 10, base - 20, 10, 2, F)
                rect(x + 12, base - 17, 6, 2, face)
                rect(x + 11, base - 11, 12, 1, face)
            elseif Camera.region == 2 then
                rect(x + 13, base - 23, 2, 23, DK)
                rect(x + 25, base - 19, 2, 19, DK)
                for k = 0, 3 do
                    rect(x + 9, base - 6 - k * 5, 22, 1, face)
                end
                rect(x + 10, base - 23, 8, 2, J)
                rect(x + 22, base - 19, 8, 2, J)
            elseif Camera.region == 3 then
                circ(x + 18, base - 12, 9, face)
                circ(x + 29, base - 15, 7, face)
                rect(x + 22, base - 8, 3, 8, DK)
            elseif Camera.region == 4 or Camera.region == 8 then
                rect(x + 20, base - 26, 2, 26, DK)
                for k = 0, 3 do
                    local yy = base - 6 - k * 6
                    local half = 5 + k * 3
                    tri(x + 21 - half, yy, x + 21, yy - 8, x + 21 + half, yy, face)
                end
                if Camera.region == 8 then
                    rect(x + 8, base - 7, 14, 2, accent)
                    rect(x + 10, base - 7, 2, 7, DK)
                    rect(x + 18, base - 7, 2, 7, DK)
                    rect(x + 28, base - 7, 14, 2, accent)
                    rect(x + 30, base - 7, 2, 7, DK)
                    rect(x + 38, base - 7, 2, 7, DK)
                end
            elseif Camera.region == 5 then
                rect(x + 22, base - 28, 3, 28, DK)
                tri(x + 8, base - 9, x + 24, base - 30, x + 40, base - 9, face)
                rect(x + 20, base - 30, 7, 2, W)
            elseif Camera.region == 6 then
                tri(x + 6, base, x + 25, base - 31, x + 43, base, face)
                line(x + 25, base - 31, x + 19, base - 18, accent)
                line(x + 25, base - 31, x + 31, base - 16, accent)
            elseif Camera.region == 7 then
                for k = 0, 3 do
                    local xx = x + 9 + k * 7
                    line(xx, base, xx + (k % 2 == 0 and -2 or 2), base - 16 - k * 2, face)
                    rect(xx - 3, base - 15 - k * 2, 6, 2, face)
                end
            end
        end
    end

    local function drawNearWinds(face, accent)
        local shift = flr(Camera.x * 0.42)
        for y = 34, 104, 18 do
            local x = (y * 11 + shift * (1 + (y % 3))) % 310 - 45
            line(x, y, x + 28, y - 3, face)
            line(x + 6, y + 1, x + 22, y - 1, accent)
        end
        for i = 0, 3 do
            local x = 24 + i * 63 - shift % 63
            local y = 42 + (i % 2) * 19
            line(x, y, x + 12, y - 4, face)
            line(x + 5, y + 2, x + 17, y - 1, face)
        end
    end

    local hi, mid, low, accent = skyPalette(Camera.region)
    drawSky(hi, mid, low, accent)
    drawFarMountains(Camera.region == 6 and DK or B, Camera.region == 6 and R or K)
    drawMidSilhouettes(Camera.region == 7 and K or F, accent)
    drawNearWinds(Camera.region == 5 and B or DK, Camera.region == 3 and PK or N)

    local srcX = flr(Camera.x / TS)
    local srcY = flr(Camera.y / TS)
    local dstX = flr(Camera.x) - srcX * TS
    local dstY = flr(Camera.y) - srcY * TS
    local mapW = ceil((SCREEN_W - dstX) / TS) + 1
    local mapH = ceil((SCREEN_H - dstY) / TS) + 1
    map(srcX, srcY, mapW, mapH, dstX, dstY, 0)

    if player then
        local shadowX = flr(player.x + player.w * 0.5 - Camera.x)
        local shadowY = flr(player.y + player.h - Camera.y)
        ellib(flr(shadowX + player.w * 0.5), shadowY, max(2, player.w - 1), 1, V)

        local hide = player.invuln and player.invuln > 0
            and flr(player.invuln / 3) % 2 == 1
        if not hide then
            local sx = flr(player.x - Camera.x) - flr((16 - player.w) * 0.5)
            local sy = flr(player.y - Camera.y) - flr((16 - player.h) * 0.5)
            local frame = clamp(player.frame or PF.IDLE, 0, 15)
            spr(blk16(256, frame), sx, sy, 0, 1, player.face < 0 and 1 or 0, 0, 1, 1)
        end
    end

    local maxHearts = clamp(player and player.maxHearts or 3, 1, 5)
    local hearts = clamp(player and player.hearts or maxHearts, 0, maxHearts)
    for i = 0, maxHearts - 1 do
        spr(i < hearts and 451 or 452, 4 + i * 9, 4, 0)
    end

    local stamina = player and player.stamina or 0
    rect(4, 15, 42, 4, V)
    rectb(4, 15, 42, 4, K)
    local staminaW = flr(clamp(stamina, 0, 100) * 0.38)
    rect(6, 17, staminaW, 1, stamina < 20 and O or J)

    local ryo = player and player.ryo or 0
    spr(450, 52, 3, 0)
    print(tostring(ryo), 61, 4, N)

    local name = Camera.regionName or ""
    local nameX = max(92, SCREEN_W - #name * 4 - 6)
    rect(nameX - 3, 1, #name * 4 + 5, 11, V)
    print(name, nameX, 3, N)

    if Camera.changed then
        local bw = #name * 4 + 12
        local bx = flr((SCREEN_W - bw) * 0.5)
        rect(bx, 24, bw, 12, V)
        rectb(bx, 24, bw, 12, R)
        print(name, flr((SCREEN_W - #name * 4) * 0.5), 27, N)
    end
end

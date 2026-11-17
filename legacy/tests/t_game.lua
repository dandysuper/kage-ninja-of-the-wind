-- ============================================================================
--  t_game - deterministic lifecycle and playable-slice smoke test
--
--  The driver deliberately owns TIC so no real keyboard state is sampled.  It
--  still drives the production BOOT/Game path and replaces only presentation
--  with a recording handle, keeping the test deterministic in --cli mode.
-- ============================================================================

local gameTestDone = false

function TIC()
    if gameTestDone then return end
    gameTestDone = true

    local checks, fails = 0, 0
    local function ck(name, got, want)
        checks = checks + 1
        if got ~= want then
            fails = fails + 1
            trace("FAIL " .. name .. " got=" .. tostring(got) ..
                " want=" .. tostring(want))
        end
    end
    local function finite(v)
        return type(v) == "number" and v == v and abs(v) < 1000000000
    end
    local function neutral()
        Input.x, Input.y = 0, 0
        Input.left, Input.right = false, false
        Input.up, Input.down = false, false
        Input.jumpHeld, Input.atkHeld = false, false
        Input.jump, Input.atk = false, false
        Input.jumpBuf, Input.atkBuf = 0, 0
        Input.any = false
    end
    local function near(a, b)
        return finite(a) and finite(b) and abs(a - b) <= 0.0001
    end

    -- TIC normally invokes BOOT before the first TIC callback.  Call the
    -- lifecycle explicitly as the headless test contract requires; the world
    -- generation guard makes this second boot non-destructive.
    palApply()
    Game.boot()

    ck("game.ready", Game.ready, true)
    ck("game.worldReady", Game.worldReady, true)
    ck("world.regions.type", type(World.regions), "table")
    ck("world.regions.count", #World.regions, 8)
    ck("world.region.name", World.regions[1].name, "Bamboo Village")
    ck("world.region.tint", World.regions[6].tint, "ash")
    ck("world.spawns", #World.spawns > 0, true)
    ck("world.startX", type(World.startX), "number")
    ck("world.startY", type(World.startY), "number")

    local spawnX, spawnY = World.startX * TS, World.startY * TS
    ck("player.spawnX", Player.spawnX, spawnX)
    ck("player.spawnY", Player.spawnY, spawnY)
    ck("player.x", Player.x, spawnX)
    ck("player.y", Player.y, spawnY)
    ck("player.hearts", Player.hearts, 3)
    ck("player.maxHearts", Player.maxHearts, 3)
    ck("player.stamina", Player.stamina, 100)
    ck("player.ryo", Player.ryo, 0)
    ck("player.canDoubleJump", Player.canDoubleJump, false)
    ck("player.canDash", Player.canDash, false)
    ck("player.canWallCling", Player.canWallCling, false)
    ck("player.hazard", Player.hazard, false)
    ck("player.fell", Player.fell, false)

    ck("camera.x", finite(Camera.x), true)
    ck("camera.y", finite(Camera.y), true)
    ck("camera.region", Camera.region, 1)
    ck("camera.regionName", Camera.regionName, World.regions[1].name)
    ck("camera.tint", Camera.tint, "none")
    ck("camera.boundsX", Camera.x >= 0 and Camera.x <= WORLD_W - SCREEN_W, true)
    ck("camera.boundsY", Camera.y >= 0 and Camera.y <= WORLD_H - SCREEN_H, true)
    ck("render.handle", type(renderFrame), "function")

    -- Exercise the live tint writer and verify both palette banks stay in sync.
    palSetTint("dusk")
    palUpdateTint()
    local previousBank = vbank(0)
    local bank0 = peek(0x3FC0 + 2 * 3)
    vbank(1)
    local bank1 = peek(0x3FC0 + 2 * 3)
    vbank(previousBank)
    ck("palette.banks.sync", bank0, bank1)
    ck("palette.tint.changed", bank0 < 0x3D, true)

    -- Record the forward presentation handle instead of depending on CLI
    -- drawing output.  The real renderer remains installed after the test.
    local realRender = renderFrame
    local renderCalls, renderedPlayer = 0, nil
    renderFrame = function(player)
        renderCalls = renderCalls + 1
        renderedPlayer = player
    end

    neutral()
    for _ = 1, 6 do Game.frame() end
    ck("render.calls", renderCalls >= 6, true)
    ck("render.player", renderedPlayer == Player, true)
    ck("player.finite", finite(Player.x) and finite(Player.y) and
        finite(Player.vx) and finite(Player.vy), true)
    ck("camera.finite", finite(Camera.x) and finite(Camera.y) and
        finite(Camera.lookX) and finite(Camera.lookY), true)
    ck("player.bounds", Player.x >= 0 and Player.x <= WORLD_W - Player.w and
        Player.y >= 0 and Player.y <= WORLD_H - Player.h, true)
    ck("camera.bounds", Camera.x >= 0 and Camera.x <= WORLD_W - SCREEN_W and
        Camera.y >= 0 and Camera.y <= WORLD_H - SCREEN_H, true)

    -- Scripted right input must move the fixed-step controller without any
    -- keyboard sampling.  This is intentionally a short, bounded movement.
    local beforeMoveX = Player.x
    neutral()
    Input.x, Input.right = 1, true
    for _ = 1, 8 do Game.frame() end
    ck("input.movement", Player.x > beforeMoveX, true)
    ck("input.finite", finite(Player.x) and finite(Player.vx), true)

    -- A forced fall exercises the deterministic damage/recovery policy.  The
    -- controller normally derives this flag from a bottomless sweep.
    neutral()
    Player.hearts = 3
    Player.invuln = 0
    Player.fell = true
    Game.frame()
    ck("fall.damage", Player.hearts, 2)
    ck("fall.spawnX", near(Player.x, Player.spawnX), true)
    ck("fall.spawnY", near(Player.y, Player.spawnY), true)
    ck("fall.invulnerable", Player.invuln > 0, true)
    ck("fall.cleared", Player.fell, false)

    -- If a hazard tile is present, overlap it directly and require the same
    -- recoverable path.  The world generator normally supplies many such
    -- tiles; the conditional keeps the test valid for reduced fixtures.
    local hazardX, hazardY
    for y = 0, MAP_H - 1 do
        for x = 0, MAP_W - 1 do
            if fget(mget(x, y), F_HAZARD) then
                hazardX, hazardY = x, y
                break
            end
        end
        if hazardX then break end
    end
    if hazardX then
        Player.hearts = 3
        Player.invuln = 0
        Player.x = hazardX * TS
        Player.y = hazardY * TS - Player.h + 1
        Player.vx, Player.vy = 0, 0
        Game.frame()
        ck("hazard.damage", Player.hearts, 2)
        ck("hazard.spawnX", near(Player.x, Player.spawnX), true)
        ck("hazard.spawnY", near(Player.y, Player.spawnY), true)
        ck("hazard.invulnerable", Player.invuln > 0, true)
    else
        trace("hazard.recovery skipped (no hazard tile)")
    end

    -- Leave the module in the same palette state a normal boot would use.
    palSetTint("none")
    palUpdateTint()
    renderFrame = realRender

    trace("CHECKS=" .. checks .. " FAILS=" .. fails)
    trace("GAME-DONE")
    exit()
end

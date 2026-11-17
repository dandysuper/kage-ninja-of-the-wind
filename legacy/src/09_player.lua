-- ============================================================================
--  09 - PLAYER
--
--  A deterministic, fixed-step character controller.  The table is also the
--  public state object consumed by rendering, combat, and progression modules.
--  x/y are always the top-left corner of the AABB.
-- ============================================================================

local Player = {
    x = 0, y = 0, w = 6, h = 14,
    vx = 0, vy = 0,
    face = 1,
    onGround = false,
    onWall = false,
    state = "idle",
    frame = 0,
    animTime = 0,
    coyote = 0,
    jumpBuffer = 0,
    airJumps = 0,
    dashLeft = 0,
    dashReady = false,
    climbing = false,
    ledge = false,
    canDoubleJump = false,
    canDash = false,
    canWallCling = false,
    hearts = 3,
    maxHearts = 3,
    stamina = 100,
    ryo = 0,
    scrolls = 0,
    invuln = 0,
    hazard = false,
    fell = false,
    spawnX = 0,
    spawnY = 0,

    -- State-machine internals remain on the public object rather than adding
    -- chunk-level locals to the concatenated cart.
    wallSide = 0,
    landTimer = 0,
    ledgeSide = 0,
    dropThrough = false,
    dashUsed = false,
    _inputBufActive = false,
    _jumpWasHeld = false,
    _groundProbe = false,
}

function Player.reset(x, y)
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    Player.w, Player.h = 6, 14
    Player.x = clamp(x, 0, WORLD_W - Player.w)
    Player.y = clamp(y, 0, WORLD_H - Player.h)
    Player.spawnX, Player.spawnY = Player.x, Player.y
    Player.vx, Player.vy = 0, 0
    Player.face = 1
    Player.onGround = false
    Player.onWall = false
    Player.state = "idle"
    Player.frame = PF.IDLE
    Player.animTime = 0
    Player.coyote = 0
    Player.jumpBuffer = 0
    Player.airJumps = 0
    Player.dashLeft = 0
    Player.dashReady = false
    Player.climbing = false
    Player.ledge = false
    Player.wallSide = 0
    Player.ledgeSide = 0
    Player.landTimer = 0
    Player.dropThrough = false
    Player._inputBufActive = false
    Player._jumpWasHeld = false
    Player._groundProbe = false
    Player.invuln = 0
    Player.hazard = false
    Player.fell = false
    if Player.hearts == nil then Player.hearts = 3 end
    if Player.maxHearts == nil then Player.maxHearts = 3 end
    if Player.hearts > Player.maxHearts then Player.hearts = Player.maxHearts end
    if Player.stamina == nil then Player.stamina = 100 end
    if Player.ryo == nil then Player.ryo = 0 end
    if Player.scrolls == nil then Player.scrolls = 0 end
    if Player.canDoubleJump == nil then Player.canDoubleJump = false end
    if Player.canDash == nil then Player.canDash = false end
    if Player.canWallCling == nil then Player.canWallCling = false end
    Player.dashReady = Player.canDash == true

    -- A reset at a floor is immediately grounded, while a reset in the air
    -- remains airborne.  The next fixed step always re-probes the support.
    Player.onGround = Tiles.rectHitsFlag({ x = Player.x, y = Player.y + Player.h, w = Player.w, h = 0.5 }, F_SOLID)
        or Tiles.rectHitsFlag({ x = Player.x, y = Player.y + Player.h, w = Player.w, h = 0.5 }, F_ONEWAY)
    if Player.onGround then Player.coyote = COYOTE_TICKS end
    return Player
end

function Player.supportProbe()
    local foot = { x = Player.x, y = Player.y + Player.h, w = Player.w, h = 0.5 }
    local solid = Tiles.rectHitsFlag(foot, F_SOLID)
    local oneWay = Tiles.rectHitsFlag(foot, F_ONEWAY)
    Player._groundProbe = solid or oneWay
    return Player._groundProbe
end

function Player.findWall()
    local body = { x = Player.x, y = Player.y, w = Player.w, h = Player.h }
    local right = Tiles.rectHitsSolid({ x = body.x + body.w, y = body.y, w = 1, h = body.h })
    local left = Tiles.rectHitsSolid({ x = body.x - 1, y = body.y, w = 1, h = body.h })
    if right and left then
        if Player.face >= 0 then return 1 end
        return -1
    end
    if right then return 1 end
    if left then return -1 end
    return 0
end

function Player.findLedge()
    if Player.onGround or Player.vy < 0 then return 0, 0 end
    local side = Player.findWall()
    if side == 0 then return 0, 0 end
    local probeX = side > 0 and (Player.x + Player.w + 0.5) or (Player.x - 0.5)
    local probeY = Player.y + 2
    local id = Tiles.atPx(probeX, probeY)
    if id == 0 or not fget(id, F_SOLID) then return 0, 0 end
    local tx, ty = flr(probeX / TS), flr(probeY / TS)
    if not Tiles.tileFlag(tx, ty, F_SOLID) then return 0, 0 end

    -- Find the nearest upper edge of this wall.  A clear landing footprint
    -- distinguishes a grabbable ledge from a solid face with no space above.
    local topY = ty * TS
    for probe = ty - 1, ty - 3, -1 do
        if Tiles.tileFlag(tx, probe, F_SOLID) then topY = probe * TS else break end
    end
    -- A grabbable ledge has its top above the player's top edge but within one
    -- body height.  A one-tile horizontal floor beside the body has its top at
    -- the player's top edge and must never teleport the player upward.
    if not (topY < Player.y - 1 and topY > Player.y - Player.h) then
        return 0, 0
    end
    if not (Tiles.tileFlag(tx, ty + 1, F_SOLID) or Tiles.tileFlag(tx, ty + 2, F_SOLID)) then
        return 0, 0
    end
    local landingX = side > 0 and (tx * TS - Player.w) or ((tx + 1) * TS)
    local landing = { x = landingX, y = topY - Player.h, w = Player.w, h = Player.h }
    if Tiles.rectHitsSolid(landing) then return 0, 0 end
    return side, topY
end

function Player.canStand()
    local feet = Player.y + Player.h
    local stand = { x = Player.x, y = feet - 14, w = Player.w, h = 14 }
    return not Tiles.rectHitsSolid(stand)
end

function Player.setCrouch(down)
    if not down or not Player.onGround then
        if Player.h ~= 14 and Player.canStand() then
            local feet = Player.y + Player.h
            Player.h = 14
            Player.y = feet - Player.h
        end
        return
    end
    if Player.h ~= 8 then
        local feet = Player.y + Player.h
        local stand = { x = Player.x, y = feet - 8, w = Player.w, h = 8 }
        if not Tiles.rectHitsSolid(stand) then
            Player.h = 8
            Player.y = feet - Player.h
        end
    end
end

function Player.readInput(input)
    input = input or Input
    local x = tonumber(input.x) or 0
    if x == 0 then
        x = ((input.right and 1) or 0) - ((input.left and 1) or 0)
    end
    if x < -1 then x = -1 elseif x > 1 then x = 1 end
    local y = tonumber(input.y) or 0
    if y < -1 then y = -1 elseif y > 1 then y = 1 end
    return x, y, input.left == true, input.right == true, input.up == true,
        input.down == true, input.jump == true, input.jumpHeld == true,
        tonumber(input.jumpBuf) or 0
end

function Player.update(input)
    input = input or Input
    local moveX, moveY, leftHeld, rightHeld, upHeld, downHeld,
        jumpPressed, jumpHeld, inputJumpBuf = Player.readInput(input)

    -- Track a snapshot buffer as an edge without writing to the caller's
    -- table.  This is important for replay tapes and for the shared Input.
    if jumpPressed then
        Player.jumpBuffer = JUMP_BUFFER_TICKS
        Player._inputBufActive = true
    elseif inputJumpBuf > 0 and not Player._inputBufActive then
        Player.jumpBuffer = max(Player.jumpBuffer, inputJumpBuf)
        Player._inputBufActive = true
    elseif inputJumpBuf <= 0 then
        Player._inputBufActive = false
    end
    local wasGround = Player.onGround
    local support = Player.supportProbe()
    if wasGround and not support then
        -- Leaving a ledge grants a fresh coyote window on this transition.
        Player.coyote = COYOTE_TICKS
        Player.onGround = false
    elseif wasGround then
        Player.coyote = COYOTE_TICKS
    elseif Player.coyote > 0 then
        Player.coyote = Player.coyote - 1
    end

    if Player.ledge then
        local ledgeSide = Player.ledgeSide or Player.findWall()
        if Player.jumpBuffer > 0 and jumpPressed == false then
            -- A held buffered jump releases the ledge; an explicit down+jump
            -- below is handled by the normal drop branch.
        end
        if Player.jumpBuffer > 0 and downHeld then
            Player.jumpBuffer = 0
            Player.ledge = false
            Player.ledgeSide = 0
            Player.onGround = false
            Player.onWall = false
            Player.wallSide = 0
            Player.vy = 0.5
            Player.dropThrough = true
        elseif Player.jumpBuffer > 0 then
            Player.jumpBuffer = 0
            Player.ledge = false
            Player.ledgeSide = 0
            Player.onGround = false
            Player.onWall = false
            Player.wallSide = 0
            Player.face = ledgeSide > 0 and -1 or 1
            Player.vx = Player.face * RUN_MAX
            Player.vy = JUMP_VEL * (jumpHeld and 1 or 0.55)
            Player.coyote = 0
        else
            Player.vx = 0
            Player.vy = 0
            Player.onWall = ledgeSide ~= 0
            Player.wallSide = ledgeSide
            Player.state = "ledge"
            Player.frame = PF.WALL
            Player.animTime = Player.animTime + 1
            if Player.invuln > 0 then Player.invuln = Player.invuln - 1 end
            Player.hazard = Tiles.rectHitsFlag(Player, F_HAZARD)
            return Player
        end
    end

    -- A wall is useful for feedback even when the upgrade is locked.  Cling,
    -- slide, and wall jump are gated exclusively by canWallCling.
    local wallSide = Player.findWall()
    Player.wallSide = wallSide
    Player.onWall = wallSide ~= 0
    local canCling = Player.canWallCling and wallSide ~= 0 and not Player.onGround
    if canCling and (moveX == 0 or moveX == wallSide) then
        Player.climbing = true
        Player.vx = 0
        if Player.vy < 0 then Player.vy = 0 end
        if Player.vy > 0.85 then Player.vy = 0.85 end
        Player.stamina = max(0, Player.stamina - 0.12)
    else
        Player.climbing = false
    end

    -- Crouching always preserves the feet.  Expanding is deferred until a
    -- full-height headroom probe succeeds.
    Player.setCrouch(downHeld and Player.onGround)

    local groundedJump = Player.onGround or Player.coyote > 0
    local usedAction = false
    if Player.jumpBuffer > 0 and groundedJump and not (downHeld and Player.onGround) then
        Player.jumpBuffer = 0
        Player.vy = JUMP_VEL * (jumpHeld and 1 or 0.55)
        Player.onGround = false
        Player.coyote = 0
        Player.airJumps = 0
        usedAction = true
    elseif Player.jumpBuffer > 0 and canCling then
        Player.jumpBuffer = 0
        Player.face = wallSide > 0 and -1 or 1
        Player.vx = Player.face * RUN_MAX
        Player.vy = JUMP_VEL * (jumpHeld and 1 or 0.55)
        Player.onGround = false
        Player.onWall = false
        Player.climbing = false
        Player.wallSide = 0
        Player.coyote = 0
        Player.airJumps = 0
        Player.stamina = max(0, Player.stamina - 10)
        usedAction = true
    elseif Player.jumpBuffer > 0 and not Player.onGround and downHeld and Player.canDash
        and Player.dashLeft <= 0 and Player.dashReady and Player.stamina >= 18 then
        Player.jumpBuffer = 0
        Player.dashLeft = 8
        Player.dashReady = false
        Player.stamina = max(0, Player.stamina - 18)
        Player.vx = Player.face * DASH_SPEED
        Player.vy = 0
        Player.onGround = false
        Player.coyote = 0
        usedAction = true
    elseif Player.jumpBuffer > 0 and not Player.onGround and Player.canDoubleJump
        and Player.airJumps == 0 then
        Player.jumpBuffer = 0
        Player.airJumps = 1
        Player.vy = DOUBLE_JUMP_VEL * (jumpHeld and 1 or 0.55)
        usedAction = true
    end
    Player._jumpWasHeld = jumpHeld

    -- Grounded down+jump drops through a one-way platform.  It is not an air
    -- dash and it never consumes a solid floor.
    if downHeld and jumpPressed and Player.onGround then
        local under = { x = Player.x, y = Player.y + Player.h - 0.5, w = Player.w, h = 1.5 }
        if Tiles.rectHitsFlag(under, F_ONEWAY) then
            Player.jumpBuffer = 0
            Player.dropThrough = true
            Player.vy = 0.5
            Player.onGround = false
            Player.coyote = 0
        end
    end

    -- Horizontal acceleration/friction.  A locked dash or wall cling owns vx.
    if Player.dashLeft > 0 then
        Player.vx = Player.face * DASH_SPEED
        Player.vy = 0
        if moveX ~= 0 then Player.face = moveX end
    elseif not canCling then
        local target = moveX * RUN_MAX
        local accel = Player.onGround and RUN_ACCEL or AIR_ACCEL
        if moveX ~= 0 then
            Player.vx = approach(Player.vx, target, accel)
            Player.face = moveX
        else
            Player.vx = approach(Player.vx, 0, (Player.onGround and RUN_FRICTION or AIR_ACCEL * 0.65))
        end
    end

    -- Variable-height jump: a released button cuts upward momentum on the next
    -- rising frames, while the initial tap multiplier remains deterministic.
    if Player.vy < 0 and not jumpHeld and not usedAction then
        Player.vy = approach(Player.vy, 0, GRAVITY * 1.35)
    elseif Player.vy < 0 and not jumpHeld and usedAction and Player._jumpWasHeld then
        Player.vy = approach(Player.vy, 0, GRAVITY * 1.35)
    end

    if Player.dashLeft <= 0 and not canCling and not Player.climbing then
        if Player.onGround then
            Player.vy = 0
        else
            local gravity = abs(Player.vy) < 0.85 and GRAVITY_APEX or GRAVITY
            Player.vy = min(MAX_FALL, Player.vy + gravity)
        end
    elseif Player.climbing then
        Player.vy = moveY * RUN_MAX
    end

    local dropThroughMove = Player.dropThrough
    local moveResult = Tiles.moveBody(Player, Player.vx, Player.vy, { dropThrough = dropThroughMove })
    Player.dropThrough = false
    if moveResult.hitX then Player.vx = 0 end
    if moveResult.hitY and moveResult.normalY < 0 and not moveResult.outY then
        if not wasGround and Player.vy >= 0 then Player.landTimer = 6 end
        Player.vy = 0
        Player.onGround = true
        Player.coyote = COYOTE_TICKS
        Player.airJumps = 0
        if Player.canDash then Player.dashReady = true end
    elseif moveResult.hitY then
        Player.vy = 0
        Player.onGround = false
    elseif not dropThroughMove and Player.supportProbe() and Player.vy >= 0 then
        -- A grounded body can move horizontally with dy=0; retain support after
        -- the axis-separated sweep instead of briefly entering fall state.  A
        -- support snap is still a landing for animation purposes.
        if not wasGround then Player.landTimer = 6 end
        Player.vy = 0
        Player.onGround = true
        Player.coyote = COYOTE_TICKS
        Player.airJumps = 0
        if Player.canDash then Player.dashReady = true end
    else
        Player.onGround = false
        if Player.vy == 0 then Player.vy = GRAVITY end
    end
    if moveResult.fell then Player.fell = true end
    if Player.landTimer > 0 then Player.landTimer = Player.landTimer - 1 end
    if Player.dashLeft > 0 then Player.dashLeft = Player.dashLeft - 1 end
    if Player.jumpBuffer > 0 then Player.jumpBuffer = Player.jumpBuffer - 1 end
    if Player.invuln > 0 then Player.invuln = Player.invuln - 1 end

    -- Ledge capture happens after the normal sweep, but never while already
    -- grounded and only while descending beside a real solid face.
    if not Player.onGround and not Player.ledge and Player.vy >= 0 and Player.dashLeft <= 0 then
        local ledgeSide, topY = Player.findLedge()
        if ledgeSide ~= 0 then
            Player.ledge = true
            Player.ledgeSide = ledgeSide
            Player.onWall = true
            Player.wallSide = ledgeSide
            Player.climbing = false
            Player.vx, Player.vy = 0, 0
            if ledgeSide > 0 then
                Player.x = flr((Player.x + Player.w + 0.5) / TS) * TS - Player.w
            else
                Player.x = (flr((Player.x - 0.5) / TS) + 1) * TS
            end
            Player.y = topY - Player.h
            Player.face = ledgeSide > 0 and 1 or -1
        end
    end

    -- The ladder flag is intentionally independent from solid collision.
    Player.climbing = Player.climbing or (Tiles.rectHitsFlag(Player, F_CLIMB) and not Player.onGround)
    if Player.climbing and not canCling and moveY ~= 0 then Player.vy = moveY * RUN_MAX end

    Player.hazard = Tiles.rectHitsFlag(Player, F_HAZARD)
    if Player.hazard and Player.invuln > 0 then
        -- Keep the raw overlap visible; combat decides whether to consume it.
        Player.hazard = true
    end

    -- State selection and deterministic animation timing.
    Player.animTime = Player.animTime + 1
    local nextState, nextFrame
    if Player.ledge then
        nextState, nextFrame = "ledge", PF.WALL
    elseif Player.dashLeft > 0 then
        nextState, nextFrame = "dash", PF.DASH
    elseif Player.climbing or (Player.onWall and Player.canWallCling and not Player.onGround) then
        nextState, nextFrame = "wall", PF.WALL
    elseif Player.onGround and downHeld then
        nextState, nextFrame = "crouch", PF.CROUCH
    elseif not Player.onGround and Player.vy < 0 then
        nextState, nextFrame = "jump", PF.JUMP
    elseif not Player.onGround then
        nextState, nextFrame = "fall", PF.FALL
    elseif Player.landTimer > 0 then
        nextState, nextFrame = "land", PF.LAND
    elseif abs(Player.vx) > 0.08 then
        nextState = "run"
        nextFrame = PF.RUN1 + (flr(Player.animTime / 5) % 4)
    else
        nextState, nextFrame = "idle", PF.IDLE
    end
    Player.state, Player.frame = nextState, nextFrame
    if Player.frame < PF.IDLE or Player.frame > 15 then Player.frame = PF.IDLE end
    if Player.face ~= 1 and Player.face ~= -1 then Player.face = 1 end
    Player.stamina = clamp(Player.stamina + (Player.climbing and 0 or 0.18), 0, 100)
    if Player.stamina < 0 then Player.stamina = 0 end
    return Player
end

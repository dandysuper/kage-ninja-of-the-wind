-- ============================================================================
--  t_player - deterministic fixed-step controller checks
-- ============================================================================

local TIC_ORIG = TIC
local done = false
local checks, fails = 0, 0
local old = {}

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
    if old[x] == nil then old[x] = {} end
    if old[x][y] == nil then old[x][y] = mget(x, y) end
    mset(x, y, id)
end

local function clearArea(x0, y0, x1, y1)
    for y = y0, y0 + 20 do
        for x = x0, x1 do mset(x, y, 0) end
    end
end

local function input(x, y, jump, held, down)
    return {
        x = x or 0, y = y or 0, left = false, right = false, up = false,
        down = down or false, jumpHeld = held or false, jump = jump or false,
        jumpBuf = 0, atkHeld = false, atk = false, atkBuf = 0, any = false,
    }
end

local function floorAt(x0, x1, row)
    for x = x0, x1 do put(x, row, T.SPIKE_BASE) end
end

local function resetScenario(x, y, doubleJump, dash, wall)
    Player.canDoubleJump = doubleJump == true
    Player.canDash = dash == true
    Player.canWallCling = wall == true
    Player.reset(x, y)
end

local function step(tape, count)
    for _ = 1, (count or 1) do Player.update(tape) end
end

local function run()
    genTerrain()
    genProps()
    genChars(0)
    clearArea(2, 2, 45, 24)
    floorAt(4, 40, 10)

    -- Idle gravity and landing.
    resetScenario(5 * TS + 1, 8 * TS, false, false, false)
    ck("player.reset.ground", Player.onGround, false)
    step(input(), 4)
    ck("player.land.ground", Player.onGround, true)
    ck("player.land.state", Player.state, "land")
    ck("player.land.frame", Player.frame, PF.LAND)
    step(input(), 6)
    ck("player.land.settle", Player.onGround, true)
    step(input(), 10)
    ck("player.land.stable", Player.onGround, true)

    -- Acceleration cap, facing, and deterministic run frames.
    Player.vx = 0
    local right = input(1, 0, false, false, false)
    for _ = 1, 12 do Player.update(right) end
    ck("player.run.face", Player.face, 1)
    ck("player.run.cap", Player.vx <= RUN_MAX + 0.0001, true)
    ck("player.run.state", Player.state, "run")
    ck("player.frame.run", Player.frame >= PF.RUN1 and Player.frame <= PF.RUN4, true)

    -- Coyote and jump buffer.
    Player.reset(5 * TS + 1, 10 * TS - Player.h)
    Player.canDash = false
    Player.canDoubleJump = false
    Player.canWallCling = false
    Player.onGround = true
    Player.coyote = 0
    mset(5, 10, 0)
    step(input(), 2)
    local buffered = input(0, 0, true, true, false)
    Player.update(buffered)
    ck("player.coyote.buffer", Player.vy < 0, true)
    mset(5, 10, T.SPIKE_BASE)

    -- Hold versus tap height.
    resetScenario(5 * TS + 1, 10 * TS - Player.h, false, false, false)
    local hold = input(0, 0, true, true, false)
    for _ = 1, 10 do Player.update(hold) end
    local holdY = Player.y
    resetScenario(5 * TS + 1, 10 * TS - Player.h, false, false, false)
    Player.update(input(0, 0, true, false, false))
    for _ = 1, 9 do Player.update(input()) end
    local tapY = Player.y
    ck("player.variable.hold", holdY < tapY, true)

    -- Double jump lock and airtime reset.
    resetScenario(5 * TS + 1, 10 * TS - Player.h, true, false, false)
    Player.update(input(0, 0, true, true, false))
    local firstY = Player.y
    Player.update(input(0, 0, true, true, false))
    ck("player.double.enabled", Player.vy < 0 and Player.y < firstY + 4, true)
    ck("player.double.locked", Player.airJumps, 1)
    step(input(), 15)
    resetScenario(5 * TS + 1, 10 * TS - Player.h, true, false, false)
    Player.update(input(0, 0, true, true, false))
    step(input(), 20)
    ck("player.double.reset", Player.airJumps, 0)

    -- Air dash lock and landing unlock.
    resetScenario(5 * TS + 1, 7 * TS, false, true, false)
    Player.dashReady = true
    Player.update(input(0, -1, true, true, true))
    ck("player.dash.locked", Player.dashReady, false)
    ck("player.dash.active", Player.dashLeft > 0, true)
    local dashBefore = Player.dashLeft
    Player.update(input(0, -1, true, true, true))
    ck("player.dash.once", Player.dashLeft <= dashBefore, true)
    step(input(), 30)
    ck("player.dash.land", Player.onGround, true)
    ck("player.dash.unlock", Player.dashReady, true)

    -- Wall cling and wall jump.
    clearArea(20, 2, 27, 20)
    for y = 3, 9 do put(24, y, T.SPIKE_BASE) end
    resetScenario(24 * TS - Player.w, 5 * TS, false, false, true)
    Player.onGround = false
    Player.vy = 1
    step(input(1, 0, false, false, false), 3)
    ck("player.wall.cling", Player.onWall, true)
    ck("player.wall.state", Player.state, "wall")
    Player.update(input(1, 0, true, true, false))
    ck("player.wall.jump", Player.vy < 0, true)
    ck("player.wall.away", Player.face, -1)

    -- Crouch preserves feet and only expands with clear headroom.
    resetScenario(6 * TS + 1, 10 * TS - Player.h, false, false, false)
    local feet = Player.y + Player.h
    Player.update(input(0, 1, false, false, true))
    ck("player.crouch.height", Player.h, 8)
    near("player.crouch.feet", Player.y + Player.h, feet)
    put(6, 8, T.SPIKE_BASE)
    Player.update(input())
    ck("player.crouch.blocked", Player.h, 8)

    -- Ledge grab beside a raised solid edge.
    clearArea(30, 3, 40, 20)
    for y = 5, 9 do put(35, y, T.SPIKE_BASE) end
    for x = 35, 38 do put(x, 5, T.SPIKE_BASE) end
    resetScenario(35 * TS - Player.w, 6 * TS, false, false, false)
    Player.onGround = false
    Player.vy = 1
    Player.vx = 0
    step(input(), 2)
    ck("player.ledge.grab", Player.ledge, true)
    if not Player.ledge then
        local side, topY = Player.findLedge()
        trace("ledge debug side=" .. tostring(side) .. " topY=" .. tostring(topY) ..
            " y=" .. tostring(Player.y) .. " x=" .. tostring(Player.x))
    end

    -- Canonical hazard/fall flags and frame/face validity.
    clearArea(2, 2, 12, 15)
    put(4, 8, T.SPIKES)
    resetScenario(4 * TS + 1, 7 * TS, false, false, false)
    Player.update(input())
    ck("player.hazard", Player.hazard, true)
    ck("player.no-health-alias", Player.health, nil)
    resetScenario(4 * TS + 1, WORLD_H - Player.h - 1, false, false, false)
    step(input(0, 1, false, false, false), 4)
    ck("player.fell", Player.fell, true)
    for _ = 1, 30 do
        Player.update(input(0, 0, false, false, false))
        ck("player.frame.valid", Player.frame >= 0 and Player.frame <= 15, true)
        ck("player.face.valid", Player.face == 1 or Player.face == -1, true)
    end

    -- Input snapshot remains untouched.
    local tape = input(1, 0, true, true, false)
    local before = { tape.x, tape.jump, tape.jumpHeld, tape.jumpBuf }
    Player.update(tape)
    ck("player.snapshot.x", tape.x, before[1])
    ck("player.snapshot.jump", tape.jump, before[2])
    ck("player.snapshot.held", tape.jumpHeld, before[3])
    ck("player.snapshot.buf", tape.jumpBuf, before[4])

    trace("CHECKS=" .. checks .. " FAILS=" .. fails)
end

function TIC()
    if done then return end
    done = true
    run()
    exit()
end

-- ============================================================================
--  01 - CORE : constants, math, deterministic RNG, utilities, input
-- ============================================================================

-- ---- display / world geometry ---------------------------------------------
local SCREEN_W, SCREEN_H = 240, 136
local TS = 8                          -- tile size in pixels
local MAP_W, MAP_H = 240, 136         -- tile map dimensions (TIC-80 max)
local WORLD_W, WORLD_H = MAP_W * TS, MAP_H * TS

-- ---- physics tuning (units: pixels / frame @60fps) -------------------------
local GRAVITY = 0.30
local GRAVITY_APEX = 0.16             -- reduced gravity near jump apex
local MAX_FALL = 4.4
local RUN_ACCEL = 0.34
local RUN_MAX = 1.55
local RUN_FRICTION = 0.42
local AIR_ACCEL = 0.22
local JUMP_VEL = -4.05
local DOUBLE_JUMP_VEL = -3.55
local DASH_SPEED = 4.0
local COYOTE_TICKS = 7
local JUMP_BUFFER_TICKS = 7

-- ---- tile collision flags (see fset/fget) ---------------------------------
local F_SOLID = 0
local F_ONEWAY = 1
local F_WATER = 2
local F_HAZARD = 3
local F_CLIMB = 4
local F_BREAK = 5
local F_DECO = 6
local F_SLOPE = 7

-- ---- math -----------------------------------------------------------------
local flr, ceil, abs, sqrt = math.floor, math.ceil, math.abs, math.sqrt
local sin, cos, atan = math.sin, math.cos, math.atan
local min, max, fmod = math.min, math.max, math.fmod
local PI = math.pi
local TAU = PI * 2
local INV60 = 1 / 60

local function sgn(v) if v > 0 then return 1 elseif v < 0 then return -1 end return 0 end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function lerp(a, b, t) return a + (b - a) * t end
local function mid(a, b, c) return max(min(a, b), min(max(a, b), c)) end
-- move v toward target by at most step
local function approach(v, target, step)
    if v < target then return min(v + step, target) end
    return max(v - step, target)
end
local function dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end
local function dist2(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return dx * dx + dy * dy end
local function sign2(v) return v >= 0 and 1 or -1 end
-- wrap v into [0,m)
local function wrap(v, m) v = fmod(v, m) if v < 0 then v = v + m end return v end
-- smoothstep-ish ease
local function ease(t) t = clamp(t, 0, 1) return t * t * (3 - 2 * t) end

-- ---- deterministic RNG (does not rely on math.randomseed) ------------------
local rngS = 1
local function rngSeed(s) rngS = (s % 2147483647) if rngS <= 0 then rngS = rngS + 2147483646 end end
local function rngRaw()                       -- xorshift-ish LCG, 64-bit safe
    rngS = (rngS * 1103515245 + 12345) % 2147483647
    return rngS
end
local function rngF() return rngRaw() / 2147483647 end                  -- [0,1)
local function rngI(n) return rngRaw() % n end                          -- [0,n)
local function rngR(a, b) return a + (rngRaw() / 2147483647) * (b - a) end
local function rngPick(t) return t[1 + rngRaw() % #t] end
local function rngChance(p) return (rngRaw() / 2147483647) < p end

-- ---- misc helpers ---------------------------------------------------------
local function blit16Index(n) return n end -- placeholder for readability

-- cheap string repeat for HUD separators
local function rep(s, n) return string.rep(s, n) end

-- draw a 16x16 sprite (4 consecutive 8x8 tiles in a 2x2 block)
-- idx must be the top-left tile index of the block
local function spr16(idx, x, y, key)
    spr(idx, x, y, key, 1, 0, 0, 2, 2)
end

-- ============================================================================
--  INPUT
--  Held states plus one-frame "pressed" edges and a few ticks of buffering
--  (buffering is what makes platformer jumps feel responsive).
-- ============================================================================
local Input = {
    x = 0, y = 0,          -- -1..1
    left = false, right = false, up = false, down = false,
    jumpHeld = false, atkHeld = false,
    jump = false,          -- pressed this frame
    atk = false,
    jumpBuf = 0, atkBuf = 0,
    any = false,
}

-- Action buttons: jump = Z (4) / A (6), attack = X (5) / S (7).
local function btnJump() return btn(4) or btn(6) end
local function btnAtk() return btn(5) or btn(7) end

local function inputUpdate()
    local l, r = btn(0), btn(1)
    Input.left, Input.right = l, r
    Input.up, Input.down = btn(2), btn(3)
    Input.x = (r and 1 or 0) - (l and 1 or 0)

    local j = btnJump()
    Input.jump = j and not Input.jumpHeld
    Input.jumpHeld = j
    local a = btnAtk()
    Input.atk = a and not Input.atkHeld
    Input.atkHeld = a

    if Input.jump then Input.jumpBuf = JUMP_BUFFER_TICKS
    elseif Input.jumpBuf > 0 then Input.jumpBuf = Input.jumpBuf - 1 end
    if Input.atk then Input.atkBuf = JUMP_BUFFER_TICKS
    elseif Input.atkBuf > 0 then Input.atkBuf = Input.atkBuf - 1 end

    Input.any = Input.jump or Input.atk or l or r or Input.up or Input.down
end
local function inputConsumeJump() Input.jumpBuf = 0 end
local function inputConsumeAtk() Input.atkBuf = 0 end

-- ---- global tick counter ---------------------------------------------------
local Frame = 0
local function ticks() return Frame end
local function secs() return Frame * INV60 end

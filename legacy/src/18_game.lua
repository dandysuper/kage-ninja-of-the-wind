-- ============================================================================
--  18 - GAME LIFECYCLE
--
--  Owns boot order, progression defaults, deterministic recovery, and the
--  per-frame update order.  The renderer is deliberately a forward handle:
--  20_render assigns it after this module is concatenated.
-- ============================================================================

local renderFrame
local Game = {}

function Game.boot()
    -- Build art before placing map decorations and before the first render.
    -- The guard makes BOOT safe to invoke more than once (for example from a
    -- headless test driver) without duplicating map state or spawn records.
    if not Game.worldReady then
        genTerrain()
        genProps()
        genChars(0)
        worldGen()
        Game.worldReady = true
    end

    -- Reset motion first, then seed progression so reset cannot overwrite the
    -- slice's baseline unlocks or inventory.
    Player.reset(World.startX * TS, World.startY * TS)
    Player.spawnX = World.startX * TS
    Player.spawnY = World.startY * TS
    Player.canDoubleJump = false
    Player.canDash = false
    Player.canWallCling = false
    Player.dashReady = false
    Player.maxHearts = 3
    Player.hearts = 3
    Player.stamina = 100
    Player.ryo = 0
    Player.scrolls = 0
    Player.invuln = 0
    Player.hazard = false
    Player.fell = false

    Camera.reset(Player)
    palSetTint(World.regions[1].tint)
    palUpdateTint()
    Game.ready = true
end

function Game.frame()
    if not Game.ready then Game.boot() end

    Player.update(Input)
    Camera.update(Player)
    palUpdateTint()

    -- Environmental damage is intentionally simple: one hit per invulnerability
    -- window, immediate recovery at the deterministic spawn, and full hearts on
    -- a life loss.  Combat and enemy contact are owned by later systems.
    if Player.invuln == 0 and (Player.hazard or Player.fell) then
        Player.hearts = max(0, Player.hearts - 1)
        Player.reset(Player.spawnX, Player.spawnY)
        Player.invuln = 90
        Camera.reset(Player)
        if Player.hearts <= 0 then
            Player.maxHearts = max(3, Player.maxHearts)
            Player.hearts = Player.maxHearts
        end
    end

    if renderFrame then renderFrame(Player) end
end

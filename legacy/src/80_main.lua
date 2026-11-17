-- ============================================================================
--  80 - MAIN : cartridge entry points
-- ============================================================================

function BOOT()
    palApply()
    if Game and Game.boot then Game.boot() end
end

function TIC()
    Frame = Frame + 1
    inputUpdate()
    if Game and Game.frame then
        Game.frame()
    else
        cls(V)
        print("KAGE - modules loading", 40, 64, W)
    end
end

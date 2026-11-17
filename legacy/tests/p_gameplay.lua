-- ============================================================================
--  p_gameplay - integrated game preview
--
--  The preview delegates every frame to the production TIC entry point. BOOT has
--  already generated the atlas/world, so frame one is the finished game view.
-- ============================================================================

local productionTIC = TIC

function TIC()
    productionTIC()
end

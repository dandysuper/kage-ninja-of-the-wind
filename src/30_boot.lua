-- ============================================================================
--  30 BOOT - one-time initialisation: palette, textures, sprites, sound
--  RAM (Audio.init), world.
-- ============================================================================
Boot = { done = false }

function Boot.graphics()
  Pal.apply()
  Gfx.paintTiles()
  Gfx.fillBands()
  Art.chars()
  Art.world()
  Art.mobs()
  Art.items()
  Gfx.flush()
end

function Boot.world()
  Build_initMats()
  Objects_init()
  W.gen()
  Towns_gen()
  W.genRoads()
  Objects_scatter()
  if Towns_post then Towns_post() end
  W.commit()
  Render.chunkBounds()
end

function Boot.all()
  if Boot.done then return end
  local t0 = time()
  Boot.graphics()
  Audio.init()
  local t1 = time()
  Boot.world()
  local t2 = time()
  Boot.ms = { gfx = t1 - t0, world = t2 - t1 }
  Boot.done = true
end

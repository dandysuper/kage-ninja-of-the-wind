-- render the world from a few camera positions/angles and dump frames
function BOOT() end
local function scene(tag, x, y, a)
  Cam.x, Cam.y = x, y
  local i = cidx(flr(x / 8), flr(y / 8))
  Cam.z = math.max(0, WH[i])
  Cam.a = a
  vbank(1) cls(0) vbank(0)
  cls(C_NIGHT)
  Render.begin()
  local t0 = time()
  Render.world()
  -- objects in visible chunks
  for _, k in ipairs(Render.visChunks) do
    local l = OLIST[k]
    if l then
      for ci in pairs(l) do
        local o = WO[ci]
        if o > 0 then
          local d = OBJ[o]
          local ox, oy = objPos(ci)
          local spr = d.spr or (d.anim and d.anim[1])
          if spr and SPR[spr] then
            Render.bill(SPR[spr], ox, oy, WH[ci], false, d.pm)
          end
        end
      end
    end
  end
  Render.setPM(nil)
  -- the ninja at the camera focus
  Render.bill(SPR.n_f_idle, x, y, Cam.z)
  local t1 = time()
  Test.log(string.format("%s: %.2f ms tris=%d bills=%d chunks=%d", tag, t1 - t0, Render.stats.tris, Render.stats.bills, Render.stats.chunks))
  Test.dump(tag)
end
function TIC()
  Boot.all()
  Test.log(string.format("boot gfx=%.0fms world=%.0fms", Boot.ms.gfx, Boot.ms.world))
  local s = POI.start
  scene("v_start45", s.x, s.y, math.pi / 4)
  scene("v_start0", s.x, s.y, 0)
  scene("v_start135", s.x, s.y + 10, math.pi * 3 / 4)
  scene("v_paddy", 80 * 8, 88 * 8, math.pi / 4)
  scene("v_bamboo", 30 * 8, 56 * 8, math.pi / 4)
  scene("v_fuyu", 118 * 8, 22 * 8, math.pi / 4)
  scene("v_coast", 200 * 8, 44 * 8, math.pi / 4)
  -- whole world map: map texture minified, 1px per cell
  cls(0)
  ttri(0, 0, 240, 0, 0, 112, 4, 4, 1924, 4, 4, 900, 1)
  ttri(240, 0, 240, 112, 0, 112, 1924, 4, 1924, 900, 4, 900, 1)
  Test.dump("worldmap")
  Test.finish()
end

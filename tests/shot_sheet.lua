-- render the sprite atlas (y 64..255) and the map tiles at 1x for inspection
function BOOT() end
function TIC()
  Boot.graphics()
  local used = 0
  for i = 0, 127 do used = used + (Gfx.sky[i] - 64) end
  Test.log("atlas skyline used px: " .. used .. " / " .. (128 * 192) .. "  max y=" .. math.max(table.unpack(Gfx.sky)) .. " free tiles=" .. #Gfx.freeTiles)
  vbank(1) cls(0) vbank(0)
  cls(C_GRAY)
  -- left: sprite region (128x192) shown at 1x
  for y = 0, 191 do
    for x = 0, 127 do
      local c = sget(x, y + 64)
      if c ~= 0 then pix(x, y - 0, c) end
    end
  end
  -- right: map tiles 0..127 (128x64)
  for y = 0, 63 do
    for x = 0, 111 do
      pix(128 + x, y, sget(x, y))
    end
  end
  Test.dump("sheet")
  -- zoomed ninja frames
  cls(C_GRAY)
  local names = { "n_s_idle", "n_s_walk1", "n_s_walk2", "n_s_jump", "n_s_fall", "n_s_slash1", "n_s_slash2", "n_swim",
    "n_f_idle", "n_f_walk1", "n_f_walk2", "n_b_idle", "n_b_walk1", "n_b_walk2", "n_climb", "n_glide" }
  local x, y = 2, 2
  for _, n in ipairs(names) do
    local r = SPR[n]
    if r then
      if x + r[3] * 2 > 238 then x = 2 y = y + 46 end
      blit(r, x, y, false, 2)
      x = x + r[3] * 2 + 4
    end
  end
  Test.dump("ninja")
  cls(C_GREEN)
  local mob = { "vil_f1", "vil_s1", "vil_s2", "wom_f1", "eld_f1", "grd_f1", "kid_f1", "lady_f1", "ban_s1", "ban_atk",
    "wolf1", "wolf2", "boar1", "kap1", "ten1", "ten2", "yur1", "wisp1", "oni1", "oni_atk", "spi1", "fox1", "oro1", "oro2", "cat1" }
  x, y = 2, 2
  for _, n in ipairs(mob) do
    local r = SPR[n]
    if r then
      if x + r[3] * 2 > 238 then x = 2 y = y + 54 end
      blit(r, x, y, false, 2)
      x = x + r[3] * 2 + 3
    end
  end
  Test.dump("mobs")
  cls(C_GRAY)
  x, y = 2, 2
  local names = {}
  for k in pairs(ITEM) do names[#names + 1] = "i_" .. k end
  for _, k in ipairs({ "ryo", "seed", "orbi", "heart", "heart3", "heart2", "heart1", "heart0", "bowl", "key_z", "key_x", "key_a", "key_s",
    "tab_tools", "tab_light", "tab_surv", "tab_combat", "tab_dress", "pin", "towerico", "shrineico", "townico", "bossico", "skull" }) do names[#names + 1] = k end
  table.sort(names)
  for _, n in ipairs(names) do
    local r = SPR[n]
    if r then
      blit(r, x, y, false, 2)
      x = x + 19
      if x > 222 then x = 2 y = y + 19 end
    end
  end
  Test.dump("icons")
  Test.finish()
end

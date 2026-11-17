-- ============================================================================
--  02 PALETTE - 16 colours (feudal Japan woodblock), day/night tint for
--  VRAM bank 0, palette-map helpers used to recolour sprites per draw call
--  (the palette map at 0x3FF0 is applied by spr/ttri at draw time).
-- ============================================================================
C_INK, C_NIGHT, C_INDIGO, C_BLUE, C_GRAY, C_DKGRN, C_GREEN, C_LIME = 0, 1, 2, 3, 4, 5, 6, 7
C_BROWN, C_WOOD, C_TAN, C_CREAM, C_WHITE, C_RED, C_PINK, C_GOLD = 8, 9, 10, 11, 12, 13, 14, 15

Pal = {
  base = {
    0x0d0b14, 0x25213b, 0x3d4377, 0x3f7cbf, 0x8288a0, 0x1f4d3a, 0x3e8c43, 0x9fd25c,
    0x5c3a2d, 0x9b6541, 0xd6a76c, 0xf3e3c3, 0xfbf8f0, 0xcc3340, 0xf39cb6, 0xf4c94e,
  },
  tint = { 1, 1, 1 }, -- current multiplier for bank 0
  map = {},
}

local function palWrite(t)
  for i = 0, 15 do
    local c = Pal.base[i + 1]
    local r, g, b = (c >> 16) & 255, (c >> 8) & 255, c & 255
    if t then
      r = math.min(255, math.floor(r * t[1]))
      g = math.min(255, math.floor(g * t[2]))
      b = math.min(255, math.floor(b * t[3]))
    end
    poke(0x3FC0 + i * 3, r)
    poke(0x3FC0 + i * 3 + 1, g)
    poke(0x3FC0 + i * 3 + 2, b)
  end
end

function Pal.apply()
  vbank(1) palWrite(nil)
  vbank(0) palWrite(Pal.tint)
end

-- tint bank 0 only (the world); HUD on bank 1 stays true-colour
function Pal.setTint(r, g, b)
  local t = Pal.tint
  if math.abs(t[1] - r) + math.abs(t[2] - g) + math.abs(t[3] - b) < 0.004 then return end
  t[1], t[2], t[3] = r, g, b
  vbank(0) palWrite(t)
end

-- palette map: colour i drawn as m[i] (m is a 0-based table of 16 entries)
function Pal.remap(m)
  for i = 0, 15 do poke4(0x7FE0 + i, m[i] or i) end
end
function Pal.reset()
  for i = 0, 15 do poke4(0x7FE0 + i, i) end
end
function Pal.solid(c)
  for i = 0, 15 do poke4(0x7FE0 + i, c) end
end
-- build a remap from pairs: Pal.mk{[from]=to,...}
function Pal.mk(t)
  local m = {}
  for i = 0, 15 do m[i] = t[i] or i end
  return m
end

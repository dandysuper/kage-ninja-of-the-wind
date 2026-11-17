-- ============================================================================
--  Test harness, prepended to every driver by tools/test.sh (after the game
--  modules, so drivers can reach every module table).
--    Test.log(s)        trace a line
--    Test.ok(c, msg)    assertion; prints PASS/FAIL, counts failures
--    Test.dump(tag)     framebuffer (vbank 0 + vbank 1 overlay) -> build/shots/<tag>.png
--    Test.finish()      summary + exit()
-- ============================================================================
Test = { fails = 0, passes = 0 }
function Test.log(s) trace(tostring(s) .. "\n") end
function Test.ok(c, msg)
  if c then
    Test.passes = Test.passes + 1
  else
    Test.fails = Test.fails + 1
    Test.log("FAIL " .. msg)
  end
end
local DIG = "0123456789abcdefghijklmnopqrstuv"
local function palhex()
  local p = {}
  for i = 0, 47 do p[#p + 1] = string.format("%02x", peek(0x3FC0 + i)) end
  return table.concat(p)
end
function Test.dump(tag)
  local o = { "DUMP-BEGIN " .. tag .. "\n" }
  vbank(1)
  local tr = peek(0x3FF8) % 16
  local p1 = palhex()
  local v1 = {}
  for i = 0, 240 * 136 - 1 do v1[i] = peek4(i) end
  vbank(0)
  o[#o + 1] = "PAL0 " .. palhex() .. "\n"
  o[#o + 1] = "PAL1 " .. p1 .. "\n"
  for y = 0, 135 do
    local t = {}
    for x = 0, 239 do
      local i = y * 240 + x
      local c = v1[i]
      if c ~= tr then
        t[#t + 1] = DIG:sub(c + 17, c + 17)
      else
        local c0 = peek4(i)
        t[#t + 1] = DIG:sub(c0 + 1, c0 + 1)
      end
    end
    o[#o + 1] = table.concat(t) .. "\n"
  end
  o[#o + 1] = "DUMP-END\n"
  trace(table.concat(o))
end
function Test.finish()
  Test.log(string.format("RESULT passes=%d fails=%d", Test.passes, Test.fails))
  exit()
end

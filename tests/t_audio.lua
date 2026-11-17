-- ============================================================================
--  t_audio: checks the audio module and records the sound registers every
--  frame for tools/audio.py, which re-synthesizes them into WAV previews,
--  piano rolls and spectrograms (build/audio/).
--    WAVES <512 hex>          waveform RAM after Audio.init
--    SEG <name> <frames>      start of a recorded segment
--    R <4 x fffvwlr>          per frame and channel: freq, volume, wave, L, R
-- ============================================================================
local REGS, STEREO, WAVE_RAM = 0x0FF9C, 0x14000, 0x0FFE4
local function hex(a, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.format("%02x", peek(a + i)) end
  return table.concat(t)
end

Audio.init()
Music.human = false
Test.ok(Audio.ready, "audio ready")
for _, e in ipairs(Audio.errors) do Test.log("FAIL data: " .. e) end
Test.ok(#Audio.errors == 0, "song data has no errors")
for _, n in ipairs(Sfx.NAMES) do Test.ok(Audio.has(n), "effect defined: " .. n) end
Test.ok(peek(WAVE_RAM + 4 * 16) == 0xFF and peek(WAVE_RAM + 4 * 16 + 8) == 0, "square wave in RAM")
Test.ok(peek(WAVE_RAM) == 0 and peek(WAVE_RAM + 16) == 0xFF, "noise waves in RAM")
trace("WAVES " .. hex(WAVE_RAM, 256) .. "\n")

local waveIdx = {}
for i = 15, 0, -1 do
  local t = {}
  for k = 0, 15 do t[#t + 1] = string.char(peek(WAVE_RAM + i * 16 + k)) end
  waveIdx[table.concat(t)] = i
end

local function record()
  local out = { "R " }
  local st = peek(STEREO) | (peek(STEREO + 1) << 8) | (peek(STEREO + 2) << 16) | (peek(STEREO + 3) << 24)
  for c = 0, 3 do
    local b = REGS + c * 18
    local lo, hi = peek(b), peek(b + 1)
    local w = {}
    for k = 0, 15 do w[#w + 1] = string.char(peek(b + 2 + k)) end
    local wi = waveIdx[table.concat(w)] or 0
    out[#out + 1] = string.format("%03x%x%x%x%x", lo | ((hi & 15) << 8), hi >> 4, wi, (st >> (c * 8)) & 15, (st >> (c * 8 + 4)) & 15)
  end
  trace(table.concat(out) .. "\n")
end

-- ---------------------------------------------------------------------------
-- segment plan
-- ---------------------------------------------------------------------------
local plan = {}
local function seg(name, frames, start, check) plan[#plan + 1] = { name = name, frames = frames, start = start, check = check } end
local function quiet()
  Music.play(nil)
  Sfx.busy, Sfx.jpl, Sfx.queue = 0, nil, {}
  for ch = 0, 3 do sfx(-1, 0, -1, ch) end
end

for _, n in ipairs(Sfx.NAMES) do
  seg("sfx_" .. n, 100, function() quiet() Sfx.play(n) end)
end
for _, n in ipairs({ "complete", "tower", "victory" }) do
  seg("jingle_" .. n, 330, function() quiet() Sfx.play(n) end)
end
local order = { "field", "night", "snow", "title", "town", "boss", "oni" }
for _, n in ipairs(order) do
  local tr = Audio.track(n)
  Test.ok(tr and tr.n > 0, "track compiled: " .. n)
  seg("music_" .. n, tr.n * tr.spf + 360, function() quiet() Music.play(n) end)
end
seg("mix_jingle_over_field", 600, function() quiet() Music.play("field") end, function(f)
  if f == 180 then Sfx.play("complete") end
  if f == 200 then
    Test.ok(Sfx.jpl ~= nil, "jingle playing")
    Sfx.play("swing")
  end
  if f == 590 then Test.ok(Sfx.jpl == nil and Music.pl ~= nil, "music resumed after jingle") end
end)
seg("mix_fade_field_town", 300, function() quiet() Music.play("field") end, function(f)
  if f == 120 then Music.play("town") end
  if f == 130 then Test.ok(Music.playing == "field" and Music.fadeT > 0, "fading out field") end
  if f == 200 then Test.ok(Music.playing == "town", "town started after fade") end
end)

-- region -> track mapping
local function region(r, safe, t)
  Game.region, Game.safe, Clock.t = r, safe, t
  Music.region()
  return Music.cur
end
quiet()
Test.ok(region(RG_SAKURA, false, 0.3) == "field", "day field")
Test.ok(region(RG_SAKURA, true, 0.3) == "town", "town")
Test.ok(region(RG_SNOW, false, 0.3) == "snow", "snow region")
Test.ok(region(RG_HAUNT, false, 0.3) == "night", "haunted wood")
Test.ok(region(RG_ONI, false, 0.3) == "oni", "onigashima")
Test.ok(region(RG_PLAINS, true, 0.8) == "night", "night beats town")
Shrine.trial = {}
Test.ok(region(RG_PLAINS, false, 0.3) == "boss", "trial keeps battle music")
Shrine.trial = nil
-- priority: a low priority effect does not cut a higher one
quiet()
Sfx.play("hurt")
Sfx.play("blip")
Test.ok(Sfx.last == "hurt", "blip does not cut hurt")
Sfx.play("roar")
Test.ok(Sfx.last == "roar", "roar cuts hurt")
-- levels
Audio.setLevels(1, 2)
Test.ok(pmem(255) >> 8 == 0xA0D and Music.vol < Sfx.vol, "levels stored")
Audio.setLevels(3, 3)

local cur, f, idx = nil, 0, 0
local total = 0
for _, s in ipairs(plan) do total = total + s.frames end
Test.log(string.format("recording %d segments, %d frames (%.1f s)", #plan, total, total / 60))
local t0 = time()

function TIC()
  if not cur or f >= cur.frames then
    idx = idx + 1
    cur = plan[idx]
    if not cur then
      quiet()
      Test.log(string.format("recorded in %.1f s", (time() - t0) / 1000))
      Test.finish()
      return
    end
    f = 0
    trace("SEG " .. cur.name .. " " .. cur.frames .. "\n")
    cur.start()
  end
  record()
  Music.update()
  if cur.check then cur.check(f) end
  f = f + 1
end

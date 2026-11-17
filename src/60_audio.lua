-- ============================================================================
--  60 AUDIO - everything is generated in code at boot, no binary cart
--  sections: 16 waveforms and the SFX slots are poked into sound RAM, the
--  music is a step sequencer on channels 0-2 and effects play on channel 3.
--
--    Sfx.play(name)     one-shot effect (Sfx.NAMES). "complete", "tower" and
--                       "victory" are jingles: they pause the music (ch 0-2)
--    Music.play(track)  title field night snow town oni boss, nil = stop;
--                       the same track is a no-op, others fade over
--    Music.region()     track for the player's region / town / time / battle
--    Music.update()     once per frame from Game.tick (timers + sequencers)
--    Audio.init()       from Boot.all; Audio.errors lists bad song data
--    Audio.setLevels(m, s)  music / effects volume 0-3 (System tab, pmem 255)
--
--  SFX slot (0x100E4 + id*66, verified on 1.3.1): 30 ticks x 2 bytes =
--  (15 - loudness) | wave << 4, arpeggio | pitch << 4; byte 60 = octave |
--  pitch16x << 3 | speed << 4 | reverse << 7; 61 = note; 62-65 = loops
--  (wave, volume, arpeggio, pitch) start | size << 4. Note numbers given to
--  sfx() must be Lua integers (a float raises "invalid note"); 57 = A4.
--  Slots 0-14 hold the music instruments, 16-55 the effects.
--
--  Envelope strings, one char per tick (spaces ignored):
--    v loudness 0-f, padded with 0     w waveform 0-f
--    a arpeggio 0-f semitones          p pitch 0-7 up, A-H = -1..-8
--  w/a/p repeat their last char. s = speed (-n: n+1 frames per tick),
--  x = pitch steps of 16 Hz instead of 1 Hz, r = arpeggio goes down,
--  loop = { v = { start, size }, p = ... }.
--
--  Song strings, one token per step: "D4" note ("!" louder, "?" softer),
--  "-" hold, "." rest (sustained voices play their release), a single
--  letter = hit from the track's kit. Bars are one line each.
-- ============================================================================
Audio = { ready = false, errors = {}, music = 3, sfx = 3, LEVELS = { [0] = "Off", "Low", "Mid", "High" } }
Sfx = {
  NAMES = { "swing", "hit", "kill", "hurt", "die", "jump", "djump", "land", "slam", "throw", "clank", "chop", "mine", "fall",
    "pick", "coin", "chest", "craft", "eat", "equip", "place", "fire", "heal", "upgrade", "quest", "complete", "tower",
    "kodama", "menu", "select", "open", "close", "error", "talk", "blip", "growl", "roar", "blink", "splash", "tired",
    "whisper", "cat", "victory" },
  vol = 1, busy = 0, pri = 0, t = 0, lastT = -99, queue = {},
}
Music = { cur = nil, vol = 1, fadeT = 0, human = true }

;(function()
  local WAVE_RAM, SFX_RAM, FADE, LEVEL = 0x0FFE4, 0x100E4, 40, { [0] = 0, 0.35, 0.65, 1 }

  -- --------------------------------------------------------------------------
  -- waveforms (32 x 4-bit). All 0 = white noise, all F = metallic noise.
  -- --------------------------------------------------------------------------
  local function harm(amps)
    local s, lo, hi = {}, 1e9, -1e9
    for k = 0, 31 do
      local v = 0
      for n, a in ipairs(amps) do v = v + a * sin(TAU * n * k / 32) end
      s[k] = v
      lo, hi = min(lo, v), max(hi, v)
    end
    return function(k) return flr((s[k] - lo) / (hi - lo) * 15 + 0.5) end
  end
  local WAVES = {
    [0] = function() return 0 end,                  -- white noise
    [1] = function() return 15 end,                 -- metallic noise
    [2] = harm({ 1 }),                              -- sine
    [3] = function(k) return k < 16 and k or 31 - k end, -- triangle
    [4] = function(k) return k < 16 and 15 or 0 end, -- square
    [5] = function(k) return k < 8 and 15 or 0 end, -- pulse 25%
    [6] = function(k) return k < 4 and 15 or 0 end, -- pulse 12.5%
    [7] = function(k) return k // 2 end,            -- saw
    [8] = harm({ 1, .81, .54, .25, 0, .17, .23, .2 }), -- koto attack (string plucked at 1/5)
    [9] = harm({ 1, .4, .12, .04 }),                -- koto body
    [10] = harm({ 1, .22, .1, .04 }),               -- shakuhachi
    [11] = harm({ 1, .7, .8, .5, .6, .3, .4, .2 }), -- shamisen
    [12] = harm({ 1, 0, .6, 0, .45, 0, 0, .3 }),    -- bell
    [13] = harm({ 1, 0, .2 }),                      -- drum body
    [14] = harm({ 1, .75, .55, .4, .25, .15 }),     -- bass
    [15] = harm({ 1, .45, .3, .12, .08 }),          -- fue (bamboo flute)
  }

  -- --------------------------------------------------------------------------
  -- instruments (music) and effects
  -- --------------------------------------------------------------------------
  local INST = {
    koto   = { id = 0, s = -1, w = "789", v = "fdcba 99887 76655 54443 33222 1111", p = "210" },
    shaku  = { id = 2, s = -1, w = "0a", v = "48abc cccbb bbccb baa", p = "CBA00 00000 0232 0BCB", rel = "shakuR",
      loop = { v = { 10, 8 }, p = { 10, 8 } } },
    shakuR = { id = 3, s = -1, w = "a", v = "a8643 21", p = "00ABC" },
    bass   = { id = 4, s = -2, w = "e", v = "fedcc bbaa9 98877 66554 43322 111", p = "4210" },
    taiko  = { id = 5, s = 0, x = true, w = "00d", v = "fcfed cba98 76554 43322 111", a = "fc0", p = "00543 22110 000AA B" },
    rim    = { id = 6, s = 0, w = "1d", v = "f9521" },
    kane   = { id = 7, s = 0, w = "1c", v = "db987 65432 11", a = "00606 06060 6060" },
    clap   = { id = 8, s = 0, w = "04", v = "fa41" },
    furin  = { id = 9, s = -2, w = "c", v = "bfedc baa99 88776 65544 33322 2111", p = "0000 1210ABA0", loop = { p = { 4, 8 } } },
    sham   = { id = 10, s = 0, x = true, w = "7b", v = "fdba9 88776 65544 43332 22111 10", p = "10" },
    fue    = { id = 11, s = -1, w = "0f", v = "6acdd dcccc ccddc c", p = "BA000 00000 0330CC", rel = "fueR",
      loop = { v = { 10, 6 }, p = { 10, 6 } } },
    fueR   = { id = 12, s = -1, w = "f", v = "b8532 1", p = "0ABCD" },
    bonsho = { id = 13, s = -4, w = "1c", v = "feedc dcbcb abab9 a9898 78765 4321", a = "c0" },
    wind   = { id = 14, s = -4, w = "0", v = "12345 66777 76655 44332 211", a = "01234 56776 54321 0" },
  }

  -- id, waveform/envelopes, base note (57 = A4), vol 0-15, pri (higher cuts
  -- lower), jit = random +-semitones per play
  local SFXD = {
    swing   = { id = 16, s = 0, w = "0", v = "59cef db975 4321", a = "02468 9abba 98765", note = 60, vol = 11, pri = 2, jit = 2 },
    hit     = { id = 17, s = 0, x = true, w = "10ddddd", v = "ffeca 86432 1", a = "c70", p = "00432 10AB", note = 33, vol = 15, pri = 2, jit = 1 },
    kill    = { id = 18, s = -1, w = "440", v = "fefed cba98 76543 21", a = "c7fed cba98 76543 210", note = 48, vol = 15, pri = 3 },
    hurt    = { id = 19, s = 0, r = true, w = "05", v = "ffedc ba987 65432 1", a = "00123 45678 9ab", note = 64, vol = 15, pri = 3 },
    die     = { id = 20, s = -2, r = true, w = "89", v = "fca98 eb987 da876 c9765 b8654 a8642", a = "00000 33333 55555 77777 aaaaa ccccc", note = 62, vol = 14, pri = 4 },
    jump    = { id = 21, s = 0, x = true, w = "005", v = "46876 54321", p = "00012 34567", note = 48, vol = 10, pri = 2, jit = 1 },
    djump   = { id = 22, s = 0, x = true, w = "05", v = "59a98 76543 21", a = "000cc 00cc0", p = "01234 567", note = 60, vol = 10, pri = 2 },
    land    = { id = 23, s = 0, w = "0", v = "9631", note = 33, vol = 9, pri = 1, jit = 2 },
    slam    = { id = 24, s = -1, x = true, w = "10d", v = "fffed cba98 76543 21", a = "ff0", p = "00543 22110 0AABB C", note = 38, vol = 15, pri = 3 },
    throw   = { id = 25, s = 0, w = "00111", v = "8c964 321", a = "03ccc", note = 72, vol = 11, pri = 2, jit = 2 },
    clank   = { id = 26, s = 0, w = "11c", v = "fdcba 98765 43322 11", a = "00060 60606 06060 6", note = 76, vol = 13, pri = 2, jit = 1 },
    chop    = { id = 27, s = 0, x = true, w = "0d", v = "fd953 1", p = "03210", note = 45, vol = 14, pri = 2, jit = 1 },
    mine    = { id = 28, s = 0, w = "1c", v = "feb97 65432 1", a = "00070 70", note = 69, vol = 12, pri = 2, jit = 1 },
    fall    = { id = 29, s = -1, x = true, w = "55555 50", v = "34567 8ffed cba98 76543 21", a = "00000 0fca8 65432 10", p = "01021 30", note = 36, vol = 14, pri = 3 },
    pick    = { id = 30, s = 0, w = "5", v = "cac8c a8642 1", a = "00007", note = 64, vol = 11, pri = 2 },
    coin    = { id = 31, s = 0, w = "4", v = "ccccf edcba 98765 4321", a = "00005", note = 71, vol = 11, pri = 2 },
    chest   = { id = 32, s = -1, w = "555c", v = "4650f cafca fcafe dcba9 87654 321", a = "01000 00222 777c", note = 62, vol = 13, pri = 3 },
    craft   = { id = 33, s = 0, w = "11100 0111000 c", v = "c6200 0c6200 0fdbe cafed cba98 7654", a = "00000 00000 00000 777c", note = 64, vol = 12, pri = 2 },
    eat     = { id = 34, s = 0, w = "0", v = "9b520 00ac6 20009 b521", a = "00000 00222 20001", note = 45, vol = 12, pri = 2 },
    equip   = { id = 35, s = 0, x = true, w = "1111c", v = "48cfe dcba9 87654 321", a = "0000c", p = "01233", note = 72, vol = 10, pri = 2 },
    place   = { id = 36, s = 0, w = "003", v = "c6c84 21", a = "00c", note = 38, vol = 11, pri = 2 },
    fire    = { id = 37, s = -1, w = "0", v = "2468a ccba9 87867 56453 42312 1", a = "01234 56789 99c9c 9c9c9 c9c9c 9", note = 41, vol = 12, pri = 2 },
    heal    = { id = 38, s = -1, w = "2", v = "a86ca 8ecaf db987 65432 1", a = "00022 2777c", note = 62, vol = 12, pri = 3 },
    upgrade = { id = 39, s = -2, w = "c", v = "fcafc afcaf cafca fedcb a9876 54321", a = "00022 25557 7799 9c", note = 62, vol = 13, pri = 3 },
    quest   = { id = 40, s = -2, w = "89", v = "fca8f ca8fe dcba9 87654 321", a = "00005 5557", note = 57, vol = 13, pri = 3 },
    kodama  = { id = 41, s = 0, w = "d", v = "c00b0 0c00a 00b00 90080 06004 00200", a = "00030 01004 00200 50030 01004 00200", note = 72, vol = 12, pri = 3 },
    menu    = { id = 42, s = 0, w = "4", v = "852", note = 76, vol = 8, pri = 1 },
    select  = { id = 43, s = 0, w = "4", v = "ccaa9 86421", a = "007", note = 69, vol = 10, pri = 2 },
    open    = { id = 44, s = 0, w = "5", v = "68acc a8642 1", a = "00055 57", note = 62, vol = 10, pri = 1 },
    close   = { id = 45, s = 0, r = true, w = "5", v = "ca8ca 86421", a = "00055 57", note = 74, vol = 10, pri = 1 },
    error   = { id = 46, s = 0, w = "4", v = "ccc00 ccc", a = "00000 111", note = 40, vol = 11, pri = 2 },
    talk    = { id = 47, s = 0, x = true, w = "335", v = "6aba8 6421", p = "00123 32", note = 57, vol = 10, pri = 2, jit = 2 },
    blip    = { id = 48, s = 0, w = "5", v = "63", note = 69, vol = 6, pri = 1, jit = 3 },
    growl   = { id = 49, s = 0, w = "01010 10101 01010 1", v = "69bcc ba987 65432 1", a = "01210 12101 2101", note = 28, vol = 11, pri = 2 },
    roar    = { id = 50, s = -2, x = true, w = "07070 70707 07070 70707 07070", v = "8bdff ffeed dccbb a9876 54321",
      a = "c0c0c 0c0c0 c0c0c 0c0c0 c0c0c", p = "0011 00AA 0011 00AA 0011 00AA", note = 36, vol = 15, pri = 3 },
    blink   = { id = 51, s = 0, w = "25", v = "ccba9 8642", a = "047cf c740", note = 72, vol = 10, pri = 2 },
    splash  = { id = 52, s = -1, w = "0", v = "feca9 a8786 56432 1", a = "98765 43210", note = 52, vol = 13, pri = 2 },
    tired   = { id = 53, s = -1, w = "0", v = "03542 10003 5421", note = 48, vol = 10, pri = 2 },
    whisper = { id = 54, s = -3, w = "00220 02200 22002 20022 0", v = "12345 66777 66554 43322 11",
      a = "00660 06600 66006 60066 0", p = "01210 ABA01 210AB A0121 0", note = 53, vol = 9, pri = 3 },
    cat     = { id = 55, s = -1, x = true, w = "556", v = "48cdd dccba 97531", a = "02457 77542 0", p = "00000 00000 0ABC", note = 60, vol = 11, pri = 2 },
  }

  -- --------------------------------------------------------------------------
  -- songs
  -- --------------------------------------------------------------------------
  -- the main theme in D Yo (D E G A B); night / title play it in D In
  -- (E -> Eb, B -> Bb), the same melody turned dark
  local THEME = {
    lead = {
      A = [[
        A4 - - - B4 - D5 -
        B4 - A4 - - - - -
        G4 - A4 - B4 - A4 G4
        E4 - - - - - . .
        A4 - - - B4 - D5 -
        E5 - - - D5 - B4 -
        A4 - B4 - G4 - E4 -
        D4 - - - - - . .]],
      B = [[
        D5 - - - E5 - D5 B4
        A4 - - - - - B4 -
        D5 - E5 - G5 - E5 D5
        B4 - - - - - . .
        A4 - B4 - D5 - B4 A4
        G4 - - - E4 - G4 -
        A4 - - - - - - -
        - - - - . . . .]],
      B2 = [[
        D5 - - E5 D5 - B4 A4
        B4 - - - - - D5 -
        E5 - G5 - A5 - G5 E5
        D5 - - - - - . .
        B4 - D5 - E5 - D5 B4
        A4 - - - G4 - E4 -
        D4 - - - - - - -
        - - - - . . . .]],
    },
    koto = {
      A = [[
        D3 . A3 . D4 . . .
        D3 . A3 . E4 . D4 .
        G3 . D4 . G4 . . .
        E3 . B3 . E4 . G4 .
        D3 . A3 . D4 . . .
        G3 . D4 . G4 . A4 .
        A3 . D4 . A4 . G4 .
        D3 . A3 . D4 . A3 .]],
      B = [[
        G3 D4 G4 A4 B4 . A4 .
        D3 A3 D4 E4 A4 . E4 .
        E3 B3 E4 G4 B4 . G4 .
        E3 B3 E4 . B3 . G3 .
        D3 A3 D4 E4 A4 . D4 .
        G3 D4 G4 A4 D5 . A4 .
        A3 D4 A4 . D4 . A3 .
        A3 D4 G4 . D4 . A3 .]],
      A2 = [[
        D3 A3 D4 . A4 . B4 D5
        B4 . A4 . D4 . A3 .
        G3 D4 G4 . A4 B4 A4 G4
        E4 . B3 . E3 . . .
        D3 A3 D4 . A4 . B4 D5
        E5 . D5 B4 G4 . D4 .
        A3 D4 A4 B4 G4 . E4 .
        D4 . A3 . D3 . . .]],
    },
    low = {
      A = [[
        D2 . . . . . . .
        . . . . d . . .
        G2 . . . . . . .
        E2 . . . d . . .
        D2 . . . . . . .
        G2 . . . d . . .
        A2 . . . . . . .
        D2 . . . d . k k]],
      B = [[
        G2 . . . d . . .
        D2 . . . . . . .
        E2 . . . d . . .
        E2 . . . . . k .
        D2 . . . d . . .
        G2 . . . . . . .
        A2 . . . d . . .
        A2 . . . d . d d]],
      A2 = [[
        D2 . . . d . . .
        . . . . d . k .
        G2 . . . d . . .
        E2 . . . d . k k
        D2 . . . d . . .
        G2 . . . d . k .
        A2 . . . d . . .
        D2 . . . d . d .]],
    },
  }
  THEME.koto.B2, THEME.low.B2 = THEME.koto.B, THEME.low.B

  -- town: a festival (matsuri) tune in G Yo (G A C D E)
  local TOWN = {
    fue = {
      A = [[
        D5 - E5 D5 C5 - A4 -
        G4 - A4 - C5 - - -
        D5 - E5 - G5 - E5 D5
        E5 - - - - - . .
        G5 - E5 D5 E5 - D5 C5
        A4 - C5 - D5 - - -
        C5 - A4 G4 A4 - C5 A4
        G4 - - - - - . .]],
      B = [[
        E5 - D5 - C5 - D5 -
        E5 - G5 - E5 - D5 -
        C5 - D5 - A4 - G4 -
        A4 - - - - - . .
        E5 - D5 - C5 - D5 -
        E5 - G5 - A5 - G5 E5
        D5 - C5 - A4 - C5 -
        G4 - - - - - . .]],
    },
    sham = {
      A = [[
        G3 . D4 G4 . D4 G4 .
        G3 . D4 G4 . D4 A4 .
        C4 . G4 C5 . G4 C5 .
        C4 . G4 C5 . G4 E4 .
        G3 . D4 G4 . D4 G4 .
        D4 . A4 D5 . A4 D5 .
        C4 . G4 C5 . G4 A4 .
        G3 . D4 G4 D4 . G3 .]],
      B = [[
        C4 . G4 C5 . G4 C5 .
        C4 . G4 C5 . G4 E4 .
        D4 . A4 D5 . A4 D5 .
        D4 . A4 D5 . A4 C5 .
        C4 . G4 C5 . G4 C5 .
        A3 . E4 A4 . E4 A4 .
        D4 . A4 D5 . A4 D5 .
        G3 . D4 G4 D4 . G3 .]],
      A2 = [[
        D4 . E4 D4 C4 . A3 .
        G3 . A3 . C4 D4 C4 .
        D4 . E4 . G4 . E4 D4
        E4 . G4 . E4 . D4 .
        G4 . E4 D4 E4 . D4 C4
        A3 . C4 . D4 . A3 .
        C4 . A3 G3 A3 . C4 A3
        G3 . D4 . G3 . . .]],
    },
    drum = {
      A = [[
        D . k k D . k .
        D . k . D k c .
        D . k k D . k .
        D . k . D D k k
        D . k k D . k .
        D . k . D k c .
        D . k k D . k .
        D D k k D . c c]],
      B = [[
        D . k k D . k .
        D . k . D k c .
        D . k k D . k .
        D . k . D D k k
        D . k k D . k .
        D . k . D k c .
        D . k k D k D k
        D D k k D D c .]],
    },
  }
  TOWN.drum.A2 = TOWN.drum.A

  -- battle: E In (E F A B C), 16th-note steps
  local BOSS = {
    ost = {
      A = [[
        E3 . E3 E4 . E3 F3 . E3 . E3 B3 . E3 C4 B3
        E3 . E3 E4 . E3 F3 . E3 . A3 . F3 . E3 .
        E3 . E3 E4 . E3 F3 . E3 . E3 B3 . E3 C4 B3
        E3 . E3 E4 . E3 F3 . A3 . B3 . C4 . B3 .
        E3 . E3 E4 . E3 F3 . E3 . E3 B3 . E3 C4 B3
        E3 . E3 E4 . E3 F3 . E3 . A3 . F3 . E3 .
        F3 . F3 F4 . F3 A3 . F3 . F3 C4 . F3 B3 A3
        E3 . E3 E4 . E3 F3 . E3 B3 C4 B3 A3 F3 E3 .]],
      B = [[
        A2 . A2 A3 . A2 B2 . A2 . A2 E3 . A2 F3 E3
        A2 . A2 A3 . A2 B2 . A2 . C3 . B2 . A2 .
        A2 . A2 A3 . A2 B2 . A2 . A2 E3 . A2 F3 E3
        A2 . A2 A3 . A2 B2 . C3 . E3 . F3 . E3 .
        F2 . F2 F3 . F2 A2 . F2 . F2 C3 . F2 E3 C3
        F2 . F2 F3 . F2 A2 . F2 . B2 . A2 . F2 .
        E2 . E2 E3 . E2 F2 . E2 . E2 B2 . E2 C3 B2
        E2 . E2 E3 . E2 F2 . B2 . C3 . E3 . F3 .]],
    },
    lead = {
      A = [[
        B4 - - - - - - - - - - - C5 - B4 -
        A4 - - - - - - - F4 - - - E4 - - -
        E5 - - - - - - - F5 - - - E5 - C5 -
        B4 - - - - - - - - - - - . . . .
        B4 - - - C5 - - - E5 - - - F5 - - -
        E5 - - - - - - - C5 - B4 - A4 - - -
        F4 - - - - - - - E4 - F4 - A4 - B4 -
        E4 - - - - - - - - - - - . . . .]],
      B = [[
        C5 - - - - - - - B4 - - - A4 - - -
        F4 - - - - - - - E4 - - - - - - -
        C5 - - - B4 - - - C5 - - - E5 - - -
        F5 - - - - - - - E5 - - - . . . .
        A5 - - - - - - - F5 - - - E5 - - -
        C5 - - - - - - - B4 - - - A4 - - -
        B4 - - - C5 - - - B4 - - - F4 - - -
        E4 - - - - - - - - - - - . . . .]],
    },
    drum = {
      A = [[
        D . . D . . D . D . k . D k D k
        D . . D . . D . D . k . D . k k
        D . . D . . D . D . k . D k D k
        D . . D . . D . D D k k D D k k
        D . . D . . D . D . k . D k D k
        D . . D . . D . D . k . D . k k
        D . . D . . D . D . k . D k D k
        D . k . D . k . D D D D D D D D]],
      B = [[
        D . c D . . D . D . k . D k D k
        D . . D . . D . D . k . D . k k
        D . c D . . D . D . k . D k D k
        D . . D . . D . D D k k D D k k
        D . c D . . D . D . k . D k D k
        D . . D . . D . D . k . D . k k
        D . c D . . D . D . k . D k D k
        D . k . D . k k D D k k D D D D]],
    },
  }

  local IN = { [4] = 3, [11] = 10 }
  local KIT = {
    field = { d = { "taiko", "D2", 10 }, k = { "rim", "D5", 7 } },
    night = { d = { "furin", "A5", 6 }, k = false },
    snow  = { d = { "wind", "E4", 7 }, k = { "furin", "D6", 5 } },
    title = { d = { "taiko", "D2", 14 }, k = { "kane", "E6", 7 } },
    town  = { D = { "taiko", "G2", 10 }, k = { "rim", "D5", 8 }, c = { "kane", "E6", 6 } },
    boss  = { D = { "taiko", "E2", 12 }, k = { "rim", "E5", 9 }, c = { "kane", "F6", 7 } },
    oni   = { D = { "taiko", "E2", 10 }, k = { "rim", "E5", 6 }, c = { "bonsho", "E3", 9 } },
    jingle = { T = { "taiko", "D2", 13 }, b = { "furin", "D6", 10 } },
  }
  local YO_D, YO_G, IN_E = { 2, 4, 7, 9, 11 }, { 7, 9, 0, 2, 4 }, { 4, 5, 9, 11, 0 }

  local TRACKS = {
    field = { spf = 16, order = { "A", "B", "A2", "B2" }, kit = KIT.field, scale = YO_D, voices = {
      { ch = 0, pat = THEME.koto, inst = "koto", vol = 9, jit = 1 },
      { ch = 1, pat = THEME.lead, inst = "shaku", vol = 10 },
      { ch = 2, pat = THEME.low, inst = "bass", vol = 12 } } },
    night = { spf = 20, order = { "A2", "B", "A2", "B2" }, kit = KIT.night, scale = YO_D, mode = IN, voices = {
      { ch = 0, pat = THEME.koto, inst = "koto", vol = 9, spd = -2, jit = 1 },
      { ch = 1, pat = THEME.lead, inst = "shaku", vol = 8 },
      { ch = 2, pat = THEME.low, inst = "bass", vol = 10 } } },
    snow = { spf = 18, order = { "A2", "B2", "A2", "B" }, kit = KIT.snow, scale = YO_D, voices = {
      { ch = 0, pat = THEME.koto, inst = "furin", vol = 7, oct = 1, jit = 1 },
      { ch = 1, pat = THEME.lead, inst = "shaku", vol = 8 },
      { ch = 2, pat = THEME.low, inst = "bass", vol = 10 } } },
    title = { spf = 18, order = { "A", "B" }, kit = KIT.title, scale = YO_D, mode = IN, voices = {
      { ch = 0, pat = THEME.koto, inst = "koto", vol = 10, spd = -2 },
      { ch = 1, pat = THEME.lead, inst = "shaku", vol = 11 },
      { ch = 2, pat = THEME.low, inst = "bass", vol = 12 } } },
    town = { spf = 13, order = { "A", "B", "A2", "B" }, kit = KIT.town, scale = YO_G, voices = {
      { ch = 0, pat = TOWN.sham, inst = "sham", vol = 12, jit = 1 },
      { ch = 1, pat = TOWN.fue, inst = "fue", vol = 9 },
      { ch = 2, pat = TOWN.drum, vol = 1 } } },
    boss = { spf = 7, order = { "A", "B" }, kit = KIT.boss, scale = IN_E, voices = {
      { ch = 0, pat = BOSS.ost, inst = "sham", vol = 12, jit = 1 },
      { ch = 1, pat = BOSS.lead, inst = "fue", vol = 10 },
      { ch = 2, pat = BOSS.drum, vol = 1 } } },
    oni = { spf = 10, order = { "A", "B" }, kit = KIT.oni, scale = IN_E, voices = {
      { ch = 0, pat = BOSS.ost, inst = "sham", vol = 10, jit = 1 },
      { ch = 2, pat = BOSS.drum, vol = 1 } } },
  }

  -- jingles: one part "J", channels 0-2 while the music waits
  local JINGLES = {
    complete = { spf = 6, pad = true, order = { "J" }, kit = KIT.jingle, scale = YO_D, voices = {
      { ch = 0, inst = "koto", vol = 13, pat = { J = "A4 . D5 . E5 . A5 . . . . . D6 . . . . . . . . . . ." } },
      { ch = 1, inst = "koto", vol = 10, pat = { J = "D4 . . . A4 . . . . . . . A5 . . . . . . . . . . ." } },
      { ch = 2, vol = 1, pat = { J = ". . . . . . . . . . . . b . . . . . . . . . . ." } } } },
    tower = { spf = 3, pad = true, order = { "J" }, kit = KIT.jingle, scale = YO_D, voices = {
      { ch = 0, inst = "koto", vol = 12, pat = { J = "D4 E4 G4 A4 B4 D5 E5 G5 A5 B5 D6" } },
      { ch = 1, inst = "shaku", vol = 11, pat = { J = ". . . . . . . . . . . A5 - - - - - - - - - - - - - - - D6 - - - - - - - - - - - - - - - - - - - - - - - . . . ." } },
      { ch = 2, vol = 1, pat = { J = ". . . . . . . . . . . T . . . . b" } } } },
    victory = { spf = 8, pad = true, order = { "J" }, kit = KIT.jingle, scale = YO_D, voices = {
      { ch = 0, inst = "koto", vol = 12, pat = { J = "D4 A4 D5 . G4 D5 G5 . A4 E5 A5 . B4 . A4 . D4 A4 D5 A5 D6 . . . . . . . . . . ." } },
      { ch = 1, inst = "fue", vol = 12, pat = { J = "D5 - E5 - G5 - - - A5 - - - B5 - A5 - D6 - - - - - - - - - - - - - . ." } },
      { ch = 2, vol = 1, pat = { J = "T . . . T . . . T . . . T . T T T . . . . . . . b . . . . . . ." } } } },
  }

  -- --------------------------------------------------------------------------
  -- data -> RAM
  -- --------------------------------------------------------------------------
  local function err(s) Audio.errors[#Audio.errors + 1] = s end

  local function env(name, s, pad, signed)
    local out, last = {}, 0
    s = (s or ""):gsub("%s", "")
    if #s > 30 then err(name .. ": envelope longer than 30 ticks") end
    for t = 0, 29 do
      local c = s:sub(t + 1, t + 1)
      local v
      if c == "" then v = pad or last
      elseif signed and c:match("%u") then v = 64 - c:byte()
      else v = tonumber(c, 16) or 0 end
      out[t], last = v, v
    end
    return out
  end

  -- frames until the volume envelope is silent for good (looping = nil)
  local function frames(d, V)
    if d.loop and d.loop.v then return nil end
    local last = -1
    for t = 0, 29 do if V[t] > 0 then last = t end end
    local s = d.s or 0
    if s >= 0 then return (last + 1 + s) // (1 + s) end
    return (last + 1) * (1 - s)
  end

  local function pokeSfx(name, d)
    local a = SFX_RAM + d.id * 66
    local W, V, A, P = env(name, d.w), env(name, d.v, 0), env(name, d.a), env(name, d.p, nil, true)
    for t = 0, 29 do
      poke(a + t * 2, (15 - V[t]) | (W[t] << 4))
      poke(a + t * 2 + 1, A[t] | ((P[t] & 15) << 4))
    end
    poke(a + 60, 4 | (d.x and 8 or 0) | (((d.s or 0) & 7) << 4) | (d.r and 128 or 0))
    poke(a + 61, 0)
    local L = d.loop or {}
    for k, key in ipairs({ "w", "v", "a", "p" }) do
      local l = L[key]
      poke(a + 61 + k, l and (l[1] | (l[2] << 4)) or 0)
    end
    d.len = frames(d, V)
  end

  local NOTE = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
  local function noteNum(tok)
    local l, acc, o = tok:match("^([A-G])([#b]?)(%d)")
    if not l then return nil end
    return tonumber(o) * 12 + NOTE[l] + (acc == "#" and 1 or acc == "b" and -1 or 0)
  end
  local ACC = { ["!"] = 2, ["?"] = -3 }

  local function inScale(scale, n)
    for _, pc in ipairs(scale) do if n % 12 == pc then return true end end
    return false
  end

  -- track definition -> { spf, n, voices = { { ch, ev = { [step] = event } } } }
  local function compile(name, def)
    local plen, toks = {}, {}
    for vi, v in ipairs(def.voices) do
      toks[vi] = {}
      for _, part in ipairs(def.order) do
        local list = {}
        for tok in (v.pat[part] or ""):gmatch("%S+") do list[#list + 1] = tok end
        toks[vi][part] = list
        plen[part] = max(plen[part] or 0, #list)
      end
    end
    local n = 0
    for _, part in ipairs(def.order) do n = n + plen[part] end
    local tr = { name = name, spf = def.spf, n = n, voices = {} }
    for vi, v in ipairs(def.voices) do
      local seq = {}
      for _, part in ipairs(def.order) do
        local list = toks[vi][part]
        if not def.pad and #list > 0 and #list ~= plen[part] then
          err(fmt("%s voice %d part %s: %d steps, expected %d", name, vi, part, #list, plen[part]))
        end
        for i = 1, plen[part] do seq[#seq + 1] = list[i] or "." end
      end
      local inst = v.inst and INST[v.inst]
      local rel = inst and inst.rel and INST[inst.rel]
      local ev = {}
      for i = 1, n do
        local tok = seq[i]
        local nn = noteNum(tok)
        local acc = ACC[tok:sub(-1)] or 0
        if nn then
          if def.scale and not inScale(def.scale, nn) then err(fmt("%s voice %d step %d: %s not in scale", name, vi, i, tok)) end
          if def.mode and def.mode[nn % 12] then nn = nn - nn % 12 + def.mode[nn % 12] end
          if inst then
            ev[i - 1] = { inst = inst.id, note = nn + 12 * (v.oct or 0), vol = v.vol + acc, spd = v.spd or inst.s, jit = v.jit, rel = rel }
          else
            err(fmt("%s voice %d: note without instrument", name, vi))
          end
        elseif tok ~= "." and tok ~= "-" then
          local k = def.kit and def.kit[tok:sub(1, 1)]
          if k == nil then err(fmt("%s voice %d step %d: bad token %s", name, vi, i, tok))
          elseif k then
            local ki = INST[k[1]]
            ev[i - 1] = { inst = ki.id, note = noteNum(k[2]), vol = k[3] + acc, spd = ki.s }
          end
        end
      end
      -- sustained voices: a rest after a note plays the release instrument
      if rel then
        for i = 1, n do
          if seq[i] == "." then
            local j = i
            repeat j = (j - 2) % n + 1 until seq[j] ~= "-" or j == i
            local e = ev[j - 1]
            if e and noteNum(seq[j]) then ev[i - 1] = { inst = rel.id, note = e.note, vol = e.vol, spd = rel.s } end
          end
        end
      end
      tr.voices[#tr.voices + 1] = { ch = v.ch, ev = ev }
    end
    return tr
  end

  local SONGS, JING = {}, {}

  function Audio.init()
    Audio.errors = {}
    for i = 0, 15 do
      local f = WAVES[i]
      for k = 0, 15 do poke(WAVE_RAM + i * 16 + k, f(2 * k) | (f(2 * k + 1) << 4)) end
    end
    for name, d in pairs(INST) do pokeSfx(name, d) end
    for name, d in pairs(SFXD) do pokeSfx(name, d) end
    for name, def in pairs(TRACKS) do SONGS[name] = compile(name, def) end
    for name, def in pairs(JINGLES) do JING[name] = compile(name, def) end
    Audio.ready = true
    local s = pmem(255)
    if s >> 8 == 0xA0D then Audio.setLevels(s & 3, (s >> 2) & 3) else Audio.setLevels(3, 3) end
  end

  function Audio.setLevels(m, s)
    Audio.music, Audio.sfx = m, s
    Music.vol, Sfx.vol = LEVEL[m], LEVEL[s]
    pmem(255, (0xA0D << 8) | m | (s << 2))
    if m == 0 and not Sfx.jpl then for ch = 0, 2 do sfx(-1, 0, -1, ch) end end
  end

  function Audio.has(name) return SFXD[name] ~= nil or JINGLES[name] ~= nil end
  function Audio.track(name) return SONGS[name] end
  Audio.TRACKS = TRACKS

  -- --------------------------------------------------------------------------
  -- playback
  -- --------------------------------------------------------------------------
  local function silence(c0, c1)
    for ch = c0, c1 do sfx(-1, 0, -1, ch) end
  end

  local function tickPlayer(pl, gain)
    local tr = pl.tr
    if pl.t == 0 then
      for vi, v in ipairs(tr.voices) do
        local e = v.ev[pl.step]
        if e then
          local vol = e.vol
          if e.jit and Music.human then vol = vol + rnd(-e.jit, e.jit) end
          vol = min(15, flr(vol * gain + 0.5))
          if vol > 0 then sfx(e.inst, e.note, -1, v.ch, vol, e.spd) end
          pl.sus[vi] = e.rel and vol > 0 and { e, vol } or nil
        end
      end
      pl.step = pl.step + 1
      if pl.step >= tr.n then
        if pl.loop then pl.step = 0 else pl.done = true end
      end
    end
    pl.t = (pl.t + 1) % tr.spf
  end

  -- end sustained notes softly (track fades out)
  local function release(pl)
    for vi, v in ipairs(pl.tr.voices) do
      local s = pl.sus[vi]
      if s then sfx(s[1].rel.id, s[1].note, -1, v.ch, s[2], s[1].rel.s) end
      pl.sus[vi] = nil
    end
  end

  local function startTrack(name)
    Music.pl = SONGS[name] and { tr = SONGS[name], step = 0, t = 0, loop = true, sus = {} } or nil
    Music.playing = Music.pl and name or nil
    Music.fadeT = 0
    if not Sfx.jpl then silence(0, 2) end
  end

  function Music.play(track)
    if not Audio.ready then Music.cur = track return end
    if track ~= nil and not SONGS[track] then return end
    if track == Music.cur then return end
    Music.cur = track
    if track == nil or track == "boss" or not Music.pl then
      startTrack(track)
    elseif track == Music.playing then
      Music.fadeT = 0
    elseif Music.fadeT == 0 then
      Music.fadeT = FADE
      if not Sfx.jpl then release(Music.pl) end
    end
  end

  function Music.region()
    if Game and Game.state == "finale" then return Music.play("title") end
    local b = Boss and Boss.cur
    if (b and b.alive) or (Shrine and Shrine.trial) then return Music.play("boss") end
    local r = Game and Game.region and REG[Game.region]
    local m = r and r.music or 1
    if (Clock and Clock.isNight()) or m == 4 then Music.play("night")
    elseif Game and Game.safe then Music.play("town")
    elseif m == 5 then Music.play("oni")
    elseif m == 3 then Music.play("snow")
    else Music.play("field") end
  end

  local function startJingle(name)
    Sfx.jpl = { tr = JING[name], step = 0, t = 0, loop = false, tail = 40, name = name, sus = {} }
    silence(0, 2)
  end

  function Music.update()
    if not Audio.ready then return end
    Sfx.t = Sfx.t + 1
    if Sfx.busy > 0 then Sfx.busy = Sfx.busy - 1 end
    local j = Sfx.jpl
    if j then
      if not j.done then tickPlayer(j, Sfx.vol)
      else
        j.tail = j.tail - 1
        if j.tail <= 0 then
          Sfx.jpl = nil
          silence(0, 2)
          local q = table.remove(Sfx.queue, 1)
          if q then startJingle(q) end
        end
      end
    end
    if Music.fadeT > 0 then
      Music.fadeT = Music.fadeT - 1
      if Music.fadeT == 0 then startTrack(Music.cur) end
    end
    if Sfx.jpl or not Music.pl or Music.vol <= 0 then return end
    tickPlayer(Music.pl, Music.vol * (Music.fadeT > 0 and Music.fadeT / FADE or 1))
  end

  function Sfx.play(name)
    if not Audio.ready or Sfx.vol <= 0 then return end
    if JING[name] then
      if Sfx.jpl then
        if #Sfx.queue < 2 then Sfx.queue[#Sfx.queue + 1] = name end
      else
        startJingle(name)
      end
      return
    end
    local d = SFXD[name]
    if not d then return end
    if Sfx.busy > 0 and d.pri < Sfx.pri then return end
    if name == Sfx.last and Sfx.t - Sfx.lastT < 3 then return end
    local note = d.note
    if d.jit then note = note + rnd(-d.jit, d.jit) end
    sfx(d.id, note, d.len + 1, 3, max(1, flr(d.vol * Sfx.vol + 0.5)))
    Sfx.busy, Sfx.pri, Sfx.last, Sfx.lastT = d.len, d.pri, name, Sfx.t
  end
end)()

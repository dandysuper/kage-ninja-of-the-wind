-- ============================================================================
--  qa_tic_api - empirical checks for renderer-facing TIC-80 API contracts.
--
--  This driver deliberately uses pcall around optional/extended calls. A
--  successful Lua call is not proof of the drawing semantics, so each drawing
--  check also reads the destination pixels back.
-- ============================================================================

local QA = {
    oldTIC = TIC,
    done = false,
    checks = 0,
    fails = 0,
    saved = false,
}

local QA_SPR = 255       -- unused bank-0 atlas slot (the atlas ends at 210)
local QA_SRC_X = 17
local QA_SRC_Y = 23
local QA_DST_X = 41
local QA_DST_Y = 29
local QA_MIRROR_X = 73
local QA_MIRROR_Y = 31
local QA_PAL = 0x3FC0
local QA_PAL_BYTES = 48

function QA.ck(name, got, want)
    QA.checks = QA.checks + 1
    if got ~= want then
        QA.fails = QA.fails + 1
        trace("FAIL " .. name .. " got=" .. tostring(got) .. " want=" .. tostring(want))
    end
end

function QA.readPalette(bank)
    local values = {}
    vbank(bank)
    for i = 0, QA_PAL_BYTES - 1 do
        values[i + 1] = peek(QA_PAL + i)
    end
    return values
end

function QA.writePalette(bank, values)
    vbank(bank)
    for i = 0, QA_PAL_BYTES - 1 do
        poke(QA_PAL + i, values[i + 1])
    end
end

function QA.paletteDiff(a, b)
    local different = 0
    for i = 1, QA_PAL_BYTES do
        if a[i] ~= b[i] then different = different + 1 end
    end
    return different
end

function QA.snapshot()
    QA.vbank = vbank()
    QA.mapValue = mget(QA_SRC_X, QA_SRC_Y)
    QA.sprite = {}
    for y = 0, 7 do
        for x = 0, 7 do
            QA.sprite[y * 8 + x + 1] = peek4(0x8000 + QA_SPR * 64 + y * 8 + x)
        end
    end
    QA.palette0 = QA.readPalette(0)
    QA.palette1 = QA.readPalette(1)
    vbank(QA.vbank)
    QA.saved = true
end

function QA.testMap()
    local base = 0x8000 + QA_SPR * 64
    for y = 0, 7 do
        for x = 0, 7 do
            poke4(base + y * 8 + x, 6)
        end
    end
    poke4(base, 12)
    poke4(base + 7, 15)

    mset(QA_SRC_X, QA_SRC_Y, QA_SPR)
    cls(1)
    local ok, err = pcall(map, QA_SRC_X, QA_SRC_Y, 1, 1, QA_DST_X, QA_DST_Y, 0)
    QA.ck("map.call", ok, true)
    if not ok then
        trace("map error: " .. tostring(err))
        return
    end
    QA.ck("map.destination.marker", pix(QA_DST_X, QA_DST_Y), 12)
    QA.ck("map.destination.body", pix(QA_DST_X + 7, QA_DST_Y + 7), 6)
    QA.ck("map.nonzero-destination", pix(0, 0), 1)
    QA.ck("map.source-cell", mget(QA_SRC_X, QA_SRC_Y), QA_SPR)
end

function QA.testMirror()
    local base = 0x8000 + QA_SPR * 64
    for y = 0, 7 do
        for x = 0, 7 do
            poke4(base + y * 8 + x, 6)
        end
    end
    poke4(base, 12)
    poke4(base + 7, 15)

    vbank(0)
    cls(1)
    -- pcall is intentional: it catches an invalid installed-argument call
    -- without aborting the driver; the pixels below verify the flip itself.
    local ok, err = pcall(function()
        spr(QA_SPR, QA_MIRROR_X, QA_MIRROR_Y, 0, 1, 1)
    end)
    QA.ck("spr.mirror.call", ok, true)
    if not ok then
        trace("spr mirror error: " .. tostring(err))
        return
    end
    QA.ck("spr.mirror.left", pix(QA_MIRROR_X, QA_MIRROR_Y), 15)
    QA.ck("spr.mirror.right", pix(QA_MIRROR_X + 7, QA_MIRROR_Y), 12)
    QA.ck("spr.mirror.body", pix(QA_MIRROR_X + 3, QA_MIRROR_Y + 3), 6)
end

function QA.testPalette()
    -- Establish a known base before measuring the cold tint. The original
    -- palette is retained in QA.palette0/1 and restored by QA.restore().
    palSetTint("none")
    for _ = 1, 32 do palUpdateTint() end
    palApply()
    local base0 = QA.readPalette(0)
    local base1 = QA.readPalette(1)
    vbank(QA.vbank)

    palSetTint('cold')
    for _ = 1, 32 do palUpdateTint() end
    local cold0 = QA.readPalette(0)
    local cold1 = QA.readPalette(1)
    vbank(QA.vbank)
    QA.ck("palette.cold.bank0.changed", QA.paletteDiff(base0, cold0) > 0, true)
    QA.ck("palette.cold.bank1.changed", QA.paletteDiff(base1, cold1) > 0, true)

    -- Restore the active tint to none and drain any transition before applying
    -- the canonical base palette. QA.restore() then puts the exact pre-test
    -- bytes back, so this driver is safe even if a caller had custom colors.
    palSetTint("none")
    for _ = 1, 32 do palUpdateTint() end
    palApply()
    local final0 = QA.readPalette(0)
    local final1 = QA.readPalette(1)
    vbank(QA.vbank)
    QA.ck("palette.none.bank0.base", QA.paletteDiff(base0, final0), 0)
    QA.ck("palette.none.bank1.base", QA.paletteDiff(base1, final1), 0)
end

function QA.run()
    QA.snapshot()
    vbank(0)
    QA.testMap()
    QA.testMirror()
    QA.testPalette()
end

function QA.restore()
    if not QA.saved then return end

    -- Restore the controlled map cell and sprite even if an assertion or an
    -- optional API call failed part-way through the test body.
    pcall(mset, QA_SRC_X, QA_SRC_Y, QA.mapValue)
    local base = 0x8000 + QA_SPR * 64
    pcall(vbank, 0)
    for y = 0, 7 do
        for x = 0, 7 do
            pcall(poke4, base + y * 8 + x, QA.sprite[y * 8 + x + 1])
        end
    end

    -- Leave the tint state explicitly neutral, then restore the exact palette
    -- bytes captured before the test. Each bank is written independently.
    pcall(function()
        palSetTint("none")
        for _ = 1, 32 do palUpdateTint() end
        palApply()
    end)
    if QA.palette0 then pcall(QA.writePalette, 0, QA.palette0) end
    if QA.palette1 then pcall(QA.writePalette, 1, QA.palette1) end
    pcall(vbank, QA.vbank)
    QA.saved = false
end

function TIC()
    if QA.done then return end
    QA.done = true

    local oldOK, oldErr = pcall(QA.oldTIC)
    if not oldOK then
        QA.ck("original.TIC", false, true)
        trace("original TIC error: " .. tostring(oldErr))
    end

    local runOK, runErr = pcall(QA.run)
    if not runOK then
        QA.ck("qa.runner", false, true)
        trace("QA runner error: " .. tostring(runErr))
    end

    local restoreOK, restoreErr = pcall(QA.restore)
    if not restoreOK then
        QA.ck("qa.restore", false, true)
        trace("QA restore error: " .. tostring(restoreErr))
    end

    trace("CHECKS=" .. QA.checks .. " FAILS=" .. QA.fails)
    trace("QA-DONE")
    exit()
end

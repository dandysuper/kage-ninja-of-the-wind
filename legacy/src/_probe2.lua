-- title:  probe2
-- author: sixth
-- desc:   stdlib probe
-- script: lua

local names = {
    "math", "string", "table", "os", "io", "coroutine", "utf8", "debug", "package",
    "require", "load", "loadstring", "dofile", "collectgarbage",
    "type", "pairs", "ipairs", "next", "select", "tonumber", "tostring",
    "rawget", "rawset", "setmetatable", "getmetatable", "unpack", "table.unpack",
    "assert", "error", "pcall", "xpcall", "print",
    "flr", "ceil", "sin", "cos", "atan2", "sqrt", "pow", "abs", "min", "max", "mid",
    "rnd", "srand", "pi", "tostr", "tstamp", "time", "trace", "W", "H", "btn", "spr"
}

function BOOT()
    local out = {}
    for i = 1, #names do
        local v = rawget(_G, names[i])
        local ts = type(v)
        if ts ~= "nil" then out[#out + 1] = names[i] .. ":" .. ts end
    end
    trace("AVAIL " .. table.concat(out, " "))
    if math then
        trace("MATH floor=" .. type(math.floor) .. " sin=" .. type(math.sin) ..
            " cos=" .. type(math.cos) .. " random=" .. type(math.random) ..
            " pi=" .. type(math.pi) .. " sqrt=" .. type(math.sqrt) ..
            " huge=" .. type(math.huge) .. " fmod=" .. type(math.fmod))
    end
    if string then
        trace("STR format=" .. type(string.format) .. " sub=" .. type(string.sub) ..
            " byte=" .. type(string.byte) .. " rep=" .. type(string.rep) ..
            " char=" .. type(string.char))
    end
    if table then
        trace("TBL insert=" .. type(table.insert) .. " concat=" .. type(table.concat) ..
            " remove=" .. type(table.remove) .. " sort=" .. type(table.sort))
    end
    trace("ok")
end

function TIC()
    cls(0)
    print("probe2", 2, 2, 15)
end

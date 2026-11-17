-- TIC-80 CLI capability probe
function BOOT()
 trace("BOOT-OK")
end

function TIC()
 cls(5)
 print("hello 2.5d", 10, 10, 14)
 trace("TRACE-CHECK "..tostr(1+1))
end

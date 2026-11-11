P(string.format("clock %.2f frames %s ticks %d hooked %s gen %d lastFrame %s", os.clock(), tostring(S.frameCount), S.tickCount, tostring(S.frameHooked), S.gen, tostring(S.lastFrame)))
local warned = {}
for k in pairs(S.warned) do warned[#warned + 1] = k end
P("warnings so far:", #warned)
for _, k in ipairs(warned) do P("  " .. k) end

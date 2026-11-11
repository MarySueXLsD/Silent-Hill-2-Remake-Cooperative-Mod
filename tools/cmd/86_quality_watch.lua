-- Read-only watcher for one game session: writes a line to ipc\cvarlog.txt whenever the engine's
-- material-quality switch, the game's "high quality shaders" block or the loading film changes.
-- Made to find out whether the game swaps material quality around loads (the load-start crash of
-- 2026-11-11 was a material drawn with the data of its other quality version).
if SH2CoopMod.qualityWatch then P("watcher already running in this game session") return end
SH2CoopMod.qualityWatch = true
local path = "H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\cvarlog.txt"
local names = { "r.MaterialQualityLevel", "sg.EffectsQuality", "sg.ShadingQuality" }
local last, busy = {}, false
LoopAsync(250, function()
    if busy then return false end
    busy = true
    ExecuteInGameThread(function()
        local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local st = StaticFindObject("/Script/GameBase.Default__GameBaseStatics")
        local parts, changed = {}, false
        for _, n in ipairs(names) do
            local ok, v = pcall(function() return ksl:GetConsoleVariableIntValue(n) end)
            v = ok and tostring(v) or "?"
            if last[n] ~= v then changed = true last[n] = v end
            parts[#parts + 1] = n .. "=" .. v
        end
        local okB, b = pcall(function() return st:ShadersUseHighQualityBlock(UEHelpers.GetGameInstance()) end)
        b = okB and tostring(b) or "?"
        if last.block ~= b then changed = true last.block = b end
        local okM, m = pcall(function() return st:IsMoviePlayerActive() end)
        m = okM and tostring(m) or "?"
        if last.movie ~= m then changed = true last.movie = m end
        if changed then
            local f = io.open(path, "a")
            if f then
                f:write(os.date("%H:%M:%S"), "  ", table.concat(parts, "  "), "  highQualityBlock=", b, "  loadingFilm=", m, "\n")
                f:close()
            end
        end
        busy = false
    end)
    return false
end)
P("watcher started; changes go to ipc\\cvarlog.txt")

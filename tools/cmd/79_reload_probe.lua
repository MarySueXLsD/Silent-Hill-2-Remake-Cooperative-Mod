-- "Reload the last save" from the mod, as the shared-death restart will do. ipc\stage.txt:
-- "note" (remember where we are), "reload" (ask the game to reload), "report". Staged prints.
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "report"
if f then f:close() end
local pawn = getPawn()
if stage == "report" then
    P("in game:", tostring(pawn ~= nil), " seconds since the reload was asked:", S.probeReloadAt and string.format("%.1f", os.clock() - S.probeReloadAt) or "?")
    if pawn and S.probePos then
        local l = pawn:K2_GetActorLocation()
        P(string.format("now at %.0f %.0f %.0f; before the reload at %.0f %.0f %.0f; apart %.1f m", l.X, l.Y, l.Z, S.probePos.x, S.probePos.y, S.probePos.z,
            math.sqrt((l.X - S.probePos.x) ^ 2 + (l.Y - S.probePos.y) ^ 2 + (l.Z - S.probePos.z) ^ 2) / 100))
        pcall(function() P("health:", pawn.Health:GetHealthValue()) end)
    end
    return
end
if not pawn then P("not in game") return end
local l = pawn:K2_GetActorLocation()
if stage == "note" then
    S.probePos = { x = l.X, y = l.Y, z = l.Z }
    P(string.format("noted: at %.0f %.0f %.0f", l.X, l.Y, l.Z))
    return
end
if stage == "reload" then
    local UEHelpers = require("UEHelpers")
    local gi = UEHelpers.GetGameInstance()
    P("1 game instance:", tostring(gi ~= nil and gi:IsValid()))
    S.probeReloadAt = os.clock()
    P("2 ReloadGame(false, \"\", false, nil, 0)")
    local ok, err = pcall(function() gi:ReloadGame(false, "", false, nil, 0) end)
    P("   ", tostring(ok), tostring(err))
end

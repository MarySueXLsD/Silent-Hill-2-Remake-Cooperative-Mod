-- Can we see when the game last saved? Read-only. Staged.
local pawn = getPawn()
local world = pawn:GetWorld()
P("1 find the statics object")
local statics = StaticFindObject("/Script/GameBase.Default__GameBaseStatics")
P("  ", statics and statics:IsValid() and statics:GetFullName() or "not found")
if statics and statics:IsValid() then
    P("2 time since last save")
    local ok, v = pcall(function() return statics:GetTimeSinceLastSave(world) end)
    P("  ", tostring(ok), type(v), tostring(v))
    if ok and type(v) == "userdata" then
        pcall(function() P("    as seconds:", v:GetTotalSeconds()) end)
        pcall(function() P("    ticks:", v.Ticks) end)
    end
    P("3 does slot data exist (0..5)")
    for slot = 0, 5 do
        local ok2, e = pcall(function() return statics:SaveSlotDataExist(world, slot) end)
        P("   slot", slot, tostring(ok2), tostring(e))
    end
end
P("4 game instance")
local gi = UEHelpers.GetGameInstance()
P("  ", gi:GetFullName())
pcall(function() P("   playing from main menu:", tostring(gi:IsPlayingFromMainMenu()), " world travel finished:", tostring(gi:IsWorldTravelFinished())) end)
P("done")

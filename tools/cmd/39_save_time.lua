-- What does "time since last save" contain? Read-only.
local pawn = getPawn()
local statics = StaticFindObject("/Script/GameBase.Default__GameBaseStatics")
local t = statics:GetTimeSinceLastSave(pawn:GetWorld())
P("type", type(t))
if type(t) == "table" then
    for k, v in pairs(t) do P("  field", tostring(k), type(v), tostring(v)) end
end
local ok, last = pcall(function() return statics:GetLastSaveTime(pawn:GetWorld()) end)
P("last save time:", tostring(ok), type(last))
if ok and type(last) == "table" then
    for k, v in pairs(last) do P("  field", tostring(k), type(v), tostring(v)) end
end

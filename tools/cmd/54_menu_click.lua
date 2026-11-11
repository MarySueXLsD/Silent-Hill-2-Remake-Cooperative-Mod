-- Press the Join co-op entry the way the game would: fire its click event. Staged.
local btn = S.menuBtn
if not (btn and btn:IsValid()) then P("no entry") return end
P("label:", tostring(S.menuLabel), " enabled:", tostring(S.menuEnabled), " click hook:", tostring(S.menuClickHook), " wired:", tostring(S.menuClickWired))
pcall(function()
    local b = btn.OnClicked:GetBindings()
    for i = 1, #b do P("  bound to:", b[i].Object:GetFName():ToString(), b[i].FunctionName:ToString()) end
    if #b == 0 then P("  no click binding") end
end)
P("1 firing the click event")
local ok, err = pcall(function() btn.OnClicked:Broadcast() end)
P("   ", tostring(ok), tostring(err))
P("2 click seen by the mod:", tostring(S.menuClicked))
P("done")

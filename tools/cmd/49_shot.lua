-- Ask the game for a screenshot of itself, UI included (lands in Saved\Screenshots). Staged.
local ctx = FindFirstOf("SHMainMenuWidget")
if not (ctx and ctx:IsValid()) then ctx = getPawn() end
if not ctx then P("nothing to take a screenshot from") return end
local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
P("1 asking for a screenshot with the UI")
local ok, err = pcall(function() ksl:ExecuteConsoleCommand(ctx, "Shot showui", nil) end)
P("   ", tostring(ok), tostring(err))
P("done")

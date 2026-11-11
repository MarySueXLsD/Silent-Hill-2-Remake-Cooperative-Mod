-- Why did the simulated "use" not open the cupboard door? Try the delegate's Broadcast and, failing
-- that, calling each bound handler by hand. Staged prints.
local pawn = getPawn()
local a = S.simDrawer
if not (pawn and a and a:IsValid()) then P("no player or no drawer from the simulation") return end
local g = a.Generic_A
P("object:", a:GetClass():GetFName():ToString(), " opened:", tostring(a.WasOpened), " component:", tostring(g ~= nil and g:IsValid()))
local b = g.OnGrabbedByCharacterBP:GetBindings()
P("handlers:", #b)
for i = 1, #b do P("   ", b[i].Object:GetFName():ToString(), "::", b[i].FunctionName:ToString()) end

P("1 Broadcast(component, player)")
local ok, err = pcall(function() g.OnGrabbedByCharacterBP:Broadcast(g, pawn) end)
P("   ", tostring(ok), tostring(err))
P("    opened right after:", tostring(a.WasOpened))
if a.WasOpened ~= true then
    P("2 calling each handler by hand")
    for i = 1, #b do
        local obj, fn = b[i].Object, b[i].FunctionName:ToString()
        local ok2, err2 = pcall(function() obj[fn](obj, g, pawn) end)
        P("   ", fn:sub(1, 60), tostring(ok2), tostring(err2))
    end
    P("    opened right after:", tostring(a.WasOpened))
end

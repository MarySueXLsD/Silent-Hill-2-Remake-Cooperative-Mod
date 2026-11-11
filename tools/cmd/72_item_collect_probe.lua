-- Can the game be made to collect a pickup natively for our player from a distance (so the
-- pickup's own "collected" logic runs)? ipc\stage.txt: "info", "grab" (ammo pickup), "report".
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "info"
if f then f:close() end
local pawn = getPawn()
if not pawn then P("not in game") return end
if S.probeText and S.probeText:IsValid() then   -- tidy up the HUD test line from the previous probe
    pcall(function() FindFirstOf("SHGameplayHudWidget").MainContainer:RemoveChild(S.probeText) end)
    S.probeText = nil
end
local me = pawn:K2_GetActorLocation()
local function dist(a)
    local l = a:K2_GetActorLocation()
    return math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2) / 100
end
local function count(name)
    local n = 0
    pcall(function() n = pawn.Items:GetItemCount(FName(name)) end)
    return n
end

local item = S.probeItem
if stage ~= "report" or not (item and item:IsValid()) then
    item = nil
    local best
    for _, it in ipairs(FindAllOf("SHItem") or {}) do
        if it:IsValid() then
            local name, taken = "", true
            pcall(function() name = it.ItemData.RowName:ToString() end)
            pcall(function() taken = it.bWasCollected end)
            local d = dist(it)
            if name == "HandgunAmmo" and not taken and d > 6 and (not best or d < best) then item, best = it, d end
        end
    end
    S.probeItem = item
end
if not item then P("no uncollected handgun ammo pickup further than 6 m") return end
local name = item.ItemData.RowName:ToString()
local function describe()
    local t = string.format("%s x%s at %.0fm collected=%s", name, tostring(item.Quantity), dist(item), tostring(item.bWasCollected))
    pcall(function() t = t .. " disabled=" .. tostring(item:IsItemDisabled()) end)
    pcall(function() t = t .. " hidden=" .. tostring(item.bHidden) end)
    return t .. "  | we hold " .. count(name) .. string.format("  | we are at %.0f %.0f %.0f", me.X, me.Y, me.Z)
end
P("pickup:", describe())
local gen = item.InteractionGeneric
P("interaction component:", tostring(gen ~= nil and gen:IsValid()))
pcall(function()
    local b = gen.OnGrabbedByCharacterBP:GetBindings()
    P("handlers on 'grabbed':", #b)
    for i = 1, #b do P("   ", b[i].Object:GetFName():ToString(), "::", b[i].FunctionName:ToString()) end
end)
pcall(function() P("behaviour:", tostring(gen:GetBehaviour()), " clickable:", tostring(gen:IsClickable()), " holdable:", tostring(gen:IsHoldable()), " used:", tostring(gen:IsUsed())) end)

if stage == "grab" then
    P("1 firing 'grabbed by our character' on it")
    local ok, err = pcall(function() gen.OnGrabbedByCharacterBP:Broadcast(gen, pawn) end)
    P("   ", tostring(ok), tostring(err))
    P("right after:", describe())
end

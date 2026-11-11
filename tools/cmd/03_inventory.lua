local pawn = UEHelpers.GetPlayerController().Pawn
local items = pawn.Items
P("items comp:", items:GetFullName())
local arr = items.CollectedItems
P("count:", #arr)
arr:ForEach(function(i, e)
    local d = e:get()
    P(string.format("  %2d  %-40s x%d", i, d.ItemRowName:ToString(), d.Quantity))
end)
P("health:", pawn.Health.HealthValue)
local ok, v = pcall(function() return items:GetItemCount(FName("HandgunAmmo")) end)
P("GetItemCount test:", ok, v)

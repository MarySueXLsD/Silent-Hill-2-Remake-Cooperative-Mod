-- Simulate the local player gaining then losing one handgun round, to see the mod notice it.
local items = getPawn().Items
local before = items:GetItemCount(FName("HandgunAmmo"))
items:CollectItem(FName("HandgunAmmo"), 1, false)
P("ammo", before, "->", items:GetItemCount(FName("HandgunAmmo")))

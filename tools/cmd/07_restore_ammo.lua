local items = getPawn().Items
items:RemoveItem(FName("HandgunAmmo"), 1, false)
P("ammo now", items:GetItemCount(FName("HandgunAmmo")), " drinks now", items:GetItemCount(FName("HealthDrink")))
P("outbox size", #S.outbox, " peer.applied", S.peer.applied)

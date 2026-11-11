-- Read-only: the internal names and amounts of everything in the inventory.
local pawn = getPawn()
if not pawn then P("not in game") return end
local rows = {}
pawn.Items.CollectedItems:ForEach(function(_, e)
    local d = e:get()
    rows[#rows + 1] = d.ItemRowName:ToString() .. " x" .. tostring(d.Quantity)
end)
table.sort(rows)
P(#rows, "items:", table.concat(rows, ", "))

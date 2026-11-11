-- Which zoom-in puzzles are loaded, and are they solved? Read-only. Staged.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
P("1 focusable components")
local all = FindAllOf("SHFocusableComponent")
P("  loaded:", all and #all or 0)
local rows = {}
if all then
    for i = 1, #all do
        local c = all[i]
        if c:IsValid() then
            local owner = c:GetOwner()
            if owner and owner:IsValid() then
                local l = owner:K2_GetActorLocation()
                rows[#rows + 1] = { c = c, owner = owner, d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2) }
            end
        end
    end
end
table.sort(rows, function(a, b) return a.d < b.d end)
P("2 nearest")
for i = 1, math.min(12, #rows) do
    local r = rows[i]
    local solved, completed, shown = "?", "?", "?"
    pcall(function() solved = tostring(r.c:IsSolved()) end)
    pcall(function() completed = tostring(r.c.bIsCompleted) end)
    pcall(function() shown = tostring(r.c:IsShown()) end)
    P(string.format("  %5.0f away  solved %-5s completed %-5s shown %-5s  %s  (%s)", r.d, solved, completed, shown,
        r.owner:GetFullName():match("PersistentLevel%.(.+)$") or "?", r.owner:GetClass():GetFName():ToString()))
end
local nSolved = 0
for _, r in ipairs(rows) do
    local ok, s = pcall(function() return r.c:IsSolved() end)
    if ok and s then nSolved = nSolved + 1 end
end
P("3 solved in total:", nSolved, "of", #rows)
P("done")

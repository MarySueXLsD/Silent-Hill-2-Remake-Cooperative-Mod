-- Read-only: asset paths and kinds of the "press to use" objects loaded here, and which pickups
-- have story listeners on their "collected" event.
local function basePath(obj, wanted)
    local c = obj:GetClass()
    for _ = 1, 8 do
        if not (c and c:IsValid()) then return nil end
        if c:GetFName():ToString() == wanted then return c:GetFullName():match("^%S+%s+(%S+)$") end
        c = c:GetSuperStruct()
    end
    return nil
end
local all = FindAllOf("GenericBase_BP_C") or {}
local kinds = {}
local path
for _, a in ipairs(all) do
    if a:IsValid() then
        local n = a:GetClass():GetFName():ToString()
        kinds[n] = (kinds[n] or 0) + 1
        path = path or basePath(a, "GenericBase_BP_C")
    end
end
P("press-to-use objects loaded:", #all, " base class path:", tostring(path))
for n, c in pairs(kinds) do P("   ", n, c) end
local sample = all[1]
if sample and sample:IsValid() then
    pcall(function()
        local b = sample.Generic_A.OnGrabbedByCharacterBP:GetBindings()
        P("handlers on one of them:", #b)
        for i = 1, math.min(#b, 4) do P("   ", b[i].Object:GetClass():GetFName():ToString(), "::", b[i].FunctionName:ToString():sub(1, 70)) end
    end)
end
P("== pickups whose 'collected' event has listeners")
local n = 0
for _, it in ipairs(FindAllOf("ItemBase_BP_C") or {}) do
    if it:IsValid() then
        pcall(function()
            local b = it.OnCollected:GetBindings()
            if #b > 0 and n < 8 then
                n = n + 1
                local row = it.ItemData.RowName:ToString()
                local who = {}
                for i = 1, math.min(#b, 3) do who[#who + 1] = b[i].Object:GetClass():GetFName():ToString() .. "::" .. b[i].FunctionName:ToString() end
                P("   ", row, "collected=" .. tostring(it.bWasCollected), "->", table.concat(who, ", "))
            end
        end)
    end
end
if n == 0 then P("    none among the pickups loaded right now") end

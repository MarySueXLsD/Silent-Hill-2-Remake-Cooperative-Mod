-- Read-only details for the next probes: triggers near the player, pickups near the player,
-- text blocks in the HUD (for a font to borrow), and the functions a trigger really has.
local pawn = getPawn()
if not pawn then P("not in game") return end
local me = pawn:K2_GetActorLocation()
local function dist(a)
    local l = a:K2_GetActorLocation()
    return math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2) / 100
end

P("== nearest triggers (class, distance, DoOnce, enabled, entered)")
local rows = {}
for _, t in ipairs(FindAllOf("TriggerBase_BP_C") or {}) do
    if t:IsValid() then
        local c = t:GetClass():GetFName():ToString()
        if not c:find("MapObject") then
            local r = { d = dist(t), text = c .. " " .. t:GetFName():ToString() }
            pcall(function() r.text = r.text .. string.format("  once=%s enabled=%s entered=%s", tostring(t.DoOnce), tostring(t.TriggerCurrentState), tostring(t.CharacterEntered)) end)
            pcall(function() if c == "TriggerAI_BP_C" then r.text = r.text .. " solved=" .. tostring(t.bIsSolved) end end)
            rows[#rows + 1] = r
        end
    end
end
table.sort(rows, function(a, b) return a.d < b.d end)
for i = 1, math.min(#rows, 14) do P(string.format("  %4.0fm %s", rows[i].d, rows[i].text)) end

P("== does a trigger expose its overlap handler to Lua")
local any = (FindAllOf("TriggerBase_BP_C") or {})[1]
if any and any:IsValid() then
    for _, fn in ipairs({ "BndEvt__Box_K2Node_ComponentBoundEvent_0_ComponentBeginOverlapSignature__DelegateSignature", "ProcessEnter", "ProcessExit" }) do
        local ok, v = pcall(function() return any[fn] end)
        P("  ", fn:sub(1, 40), tostring(ok), type(v))
    end
    pcall(function() P("   Box valid:", tostring(any.Box:IsValid())) end)
end

P("== pickups within 30 m (name, amount, collected)")
local items = {}
for _, it in ipairs(FindAllOf("SHItem") or {}) do
    if it:IsValid() and dist(it) < 30 then
        local r = { d = dist(it), text = it:GetClass():GetFName():ToString() }
        pcall(function() r.text = r.text .. "  " .. it.ItemData.RowName:ToString() .. " x" .. tostring(it.Quantity) end)
        pcall(function() r.text = r.text .. " collected=" .. tostring(it.bWasCollected) .. " disabled=" .. tostring(it:IsItemDisabled()) end)
        items[#items + 1] = r
    end
end
table.sort(items, function(a, b) return a.d < b.d end)
for i = 1, math.min(#items, 8) do P(string.format("  %4.0fm %s", items[i].d, items[i].text)) end
if #items == 0 then P("  none") end

P("== HUD")
local hud = FindFirstOf("SHGameplayHudWidget")
if hud and hud:IsValid() then
    P("  ", hud:GetFullName():sub(1, 110))
    pcall(function() P("   MainContainer children:", hud.MainContainer:GetChildrenCount()) end)
    pcall(function() P("   WidgetTree:", tostring(hud.WidgetTree:IsValid())) end)
end
local n, shown = 0, 0
for _, tb in ipairs(FindAllOf("TextBlock") or {}) do
    if tb:IsValid() then
        n = n + 1
        if shown < 6 then
            local full = tb:GetFullName()
            if full:find("Hud") or full:find("Notification") or full:find("Tutorial") then
                shown = shown + 1
                local size = "?"
                pcall(function() size = tostring(tb.Font.Size) end)
                P("   text block:", full:match("([^%.:]+%.[^%.:]+)$") or full:sub(-60), " font size:", size)
            end
        end
    end
end
P("   text blocks in memory:", n)

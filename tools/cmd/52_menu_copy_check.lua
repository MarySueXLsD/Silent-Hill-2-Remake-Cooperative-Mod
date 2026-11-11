-- Look at the engine-made copy: size, list order, what its click handlers hold; then empty them. Staged.
local menu = FindFirstOf("SHMainMenuWidget")
local btn = S.testCopy
if not (menu and menu:IsValid() and btn and btn:IsValid()) then P("no menu or no copy") return end
local tpl = menu.Load_but
pcall(function() local d = tpl:GetDesiredSize() P("load desired:", string.format("%.0f x %.0f", d.X, d.Y)) end)
pcall(function() local d = btn:GetDesiredSize() P("copy desired:", string.format("%.0f x %.0f", d.X, d.Y)) end)
local list = btn:GetParent()
for i = 0, list:GetChildrenCount() - 1 do
    local c = list:GetChildAt(i)
    local t = ""
    pcall(function() t = c:GetText():ToString() end)
    P("  ", i, c:GetFName():ToString(), t)
end
local DELEGATES = { "OnClicked", "OnPressed", "OnReleased", "OnHovered", "OnUnhovered", "OnFocused", "OnUnfocused", "OnKeyDownEvent", "OnKeyUpEvent" }
local function dump(label, w)
    P("== " .. label)
    for _, name in ipairs(DELEGATES) do
        local line = "  " .. name .. ":"
        local ok, err = pcall(function()
            local b = w[name]:GetBindings()
            line = line .. " " .. tostring(#b)
            for i = 1, #b do
                local e = b[i]
                local obj, fn = "?", "?"
                pcall(function() obj = e.Object:GetFName():ToString() end)
                pcall(function() fn = e.FunctionName:ToString() end)
                line = line .. "  [" .. obj .. " :: " .. fn .. "]"
            end
        end)
        if not ok then line = line .. " (cannot read: " .. tostring(err):sub(1, 80) .. ")" end
        P(line)
    end
end
dump("game's Load entry", tpl)
dump("copy, as made", btn)
do
    P("clearing the copy's handlers")
    for _, name in ipairs(DELEGATES) do
        P("  " .. name)
        local ok, err = pcall(function() btn[name]:Clear() end)
        if not ok then P("    failed:", tostring(err):sub(1, 100)) end
    end
    dump("copy, after clearing", btn)
    dump("game's Load entry, after clearing the copy", tpl)
end
P("done")

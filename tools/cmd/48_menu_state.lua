-- What the Join co-op menu entry looks like to the mod right now.
local menu = FindFirstOf("SHMainMenuWidget")
P("menu:", tostring(menu ~= nil and menu:IsValid()), " in game:", tostring(getPawn() ~= nil), " role:", tostring(S.role))
P("entry:", tostring(S.menuBtn ~= nil and S.menuBtn:IsValid()), " label:", tostring(S.menuLabel), " enabled:", tostring(S.menuEnabled),
    " russian:", tostring(S.menuRussian))
P("host seq:", tostring(S.menuHostSeq), " last change:", S.menuHostTime and string.format("%.1fs ago", os.clock() - S.menuHostTime) or "never",
    " joining:", tostring(S.join ~= nil))
if S.menuBtn and S.menuBtn:IsValid() then
    pcall(function() P("text:", S.menuBtn:GetText():ToString()) end)
    pcall(function() P("widget enabled:", tostring(S.menuBtn:GetIsEnabled()), " visibility:", tostring(S.menuBtn:GetVisibility())) end)
    pcall(function()
        local list = S.menuBtn:GetParent()
        P("siblings:", list:GetChildrenCount())
        for i = 0, list:GetChildrenCount() - 1 do
            local c = list:GetChildAt(i)
            local t = ""
            pcall(function() t = c:GetText():ToString() end)
            P("  ", i, c:GetFName():ToString(), t)
        end
    end)
end
local warned = {}
for k in pairs(S.warned) do if k:find("menu") then warned[#warned + 1] = k end end
P("menu warnings:", #warned)
for _, k in ipairs(warned) do P("  " .. k:sub(1, 160)) end

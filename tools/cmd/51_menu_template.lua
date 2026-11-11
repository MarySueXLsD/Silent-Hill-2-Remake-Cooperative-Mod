-- Build the menu entry as an engine-made copy of the game's Load entry, and see what the copy
-- carries over (look, click handlers). Staged: every risky step is announced first.
local menu = FindFirstOf("SHMainMenuWidget")
if not (menu and menu:IsValid()) then P("no main menu") return end
local tpl = menu.Load_but
local list = tpl:GetParent()

P("1 what does the template's OnClicked look like from Lua")
local okD, d = pcall(function() return tpl.OnClicked end)
P("   ", tostring(okD), type(d), tostring(d))
if okD and d ~= nil then
    for _, m in ipairs({ "Clear", "Add", "Remove", "Broadcast", "GetBindings", "IsBound", "Num" }) do
        local okM, v = pcall(function() return d[m] end)
        P("    ." .. m, tostring(okM), type(v))
    end
    pcall(function() P("    mt:", tostring(getmetatable(d))) end)
end

P("2 remove the old entry")
if S.menuBtn and S.menuBtn:IsValid() then
    local ok, err = pcall(function() list:RemoveChild(S.menuBtn) end)
    P("   ", tostring(ok), tostring(err))
end
S.menuBtn = nil

P("3 construct a copy with the Load entry as template")
local ok, btn = pcall(function()
    return StaticConstructObject(tpl:GetClass(), tpl:GetOuter(), FName("JoinCoopCopy_but"), 0, 0, false, false, tpl)
end)
P("   ", tostring(ok), tostring(ok and btn and btn:IsValid()))
if not (ok and btn and btn:IsValid()) then P("   err:", tostring(btn)) return end
P("   name:", btn:GetFullName())
pcall(function() P("   text carried over:", btn:GetText():ToString()) end)
pcall(function() P("   slot carried over:", tostring(btn.Slot and btn.Slot:IsValid() and btn.Slot:GetFullName())) end)

P("4 add it to the list")
local okA, slot = pcall(function() return list:AddChild(btn) end)
P("   ", tostring(okA), tostring(okA and slot and slot:IsValid()))
pcall(function()
    local src = tpl.Slot
    slot:SetPadding(src.Padding)
    slot:SetHorizontalAlignment(src.HorizontalAlignment)
    slot:SetVerticalAlignment(src.VerticalAlignment)
end)
P("5 set its text")
local okT, errT = pcall(function() btn:SetText(FText("Совместная игра")) end)
P("   ", tostring(okT), tostring(errT))
S.testCopy = btn
P("done")

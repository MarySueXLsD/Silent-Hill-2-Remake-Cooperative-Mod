-- Create a "Join co-op" entry in the main menu, copying the look of the Load button. Staged.
local menu = FindFirstOf("SHMainMenuWidget")
if not (menu and menu:IsValid()) then P("no main menu") return end
local load = menu.Load_but
local parent = load:GetParent()

if S.menuBtn and S.menuBtn:IsValid() then
    P("already created; removing it first")
    pcall(function() parent:RemoveChild(S.menuBtn) end)
    S.menuBtn = nil
end

P("1 construct")
local outer = load:GetOuter()
P("   outer:", outer:GetFullName())
local btn = StaticConstructObject(load:GetClass(), outer, FName("JoinCoop_but"))
P("   ", btn and btn:IsValid() and btn:GetFullName() or "FAILED")
if not (btn and btn:IsValid()) then return end

P("2 copy look")
for _, prop in ipairs({ "Style", "TextStyle", "NormalStyle", "WidgetStyle", "AkEventsStyle", "ScrollStyle", "Margin", "Padding",
    "MinDesiredWidth", "Justification", "AutoWrapText", "WrapTextAt", "HorizontalAlignment", "VerticalAlignment",
    "ColorAndOpacity", "BackgroundColor", "ClickMethod", "TouchMethod", "PressMethod", "IsFocusable", "MobileFontSizeMultiplier" }) do
    local ok, err = pcall(function() btn[prop] = load[prop] end)
    P(string.format("   %-24s %s", prop, ok and "ok" or ("FAILED " .. tostring(err):sub(1, 70))))
end

P("3 text")
local russian = load:GetText():ToString():find("[\128-\255]") ~= nil
local label = russian and "\208\161\208\190\208\178\208\188\208\181\209\129\209\130\208\189\208\176\209\143 \208\184\208\179\209\128\208\176" or "Join co-op"
local ok3, err3 = pcall(function() btn:SetText(FText(label)) end)
P("   ", tostring(ok3), tostring(err3), " russian menu:", tostring(russian))

P("4 add to the list")
local slot = parent:AddChild(btn)
P("   slot:", slot and slot:IsValid() and slot:GetClass():GetFName():ToString() or "none")
pcall(function()
    local src = load.Slot
    slot:SetPadding(src.Padding)
    slot:SetHorizontalAlignment(src.HorizontalAlignment)
    slot:SetVerticalAlignment(src.VerticalAlignment)
end)

P("5 result")
P("   children now:", parent:GetChildrenCount(), " visible:", tostring(btn:IsVisible()), " enabled:", tostring(btn:GetIsEnabled()))
pcall(function() P("   text reads back:", (btn:GetText():ToString():gsub("[\128-\255]", "?"))) end)
S.menuBtn = btn
P("done")

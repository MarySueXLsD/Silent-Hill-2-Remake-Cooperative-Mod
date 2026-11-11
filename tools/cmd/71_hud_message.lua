-- Put a line of text on the game's own HUD (for "Other player died, restarting..."), in the
-- HUD's own font. ipc\stage.txt: "show" or "hide". Staged prints.
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "show"
if f then f:close() end
local hud = FindFirstOf("SHGameplayHudWidget")
if not (hud and hud:IsValid()) then P("no HUD") return end

if stage == "hide" then
    if S.probeText and S.probeText:IsValid() then
        P("removing:", tostring(hud.MainContainer:RemoveChild(S.probeText)))
    end
    S.probeText = nil
    return
end

P("1 look for a HUD text block to borrow the font from")
local src
for _, tb in ipairs(FindAllOf("TextBlock") or {}) do
    if tb:IsValid() and tb:GetFName():ToString() == "NotificationText_CurrentAmmo" then src = tb end
end
P("   found:", tostring(src ~= nil))

P("2 construct a text block in the HUD's widget tree")
local text = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), hud.WidgetTree, FName("CoopMessageProbe"))
P("   ", tostring(text ~= nil and text:IsValid()))
if src then
    P("3 font")
    local ok, err = pcall(function() text:SetFont(src.Font) end)
    P("   ", tostring(ok), tostring(err))
end
P("4 text, colour, shadow")
P("   text:", tostring(pcall(function() text:SetText(FText("Other player died, restarting...")) end)))
P("   colour:", tostring(pcall(function() text:SetColorAndOpacity({ SpecifiedColor = { R = 0.92, G = 0.9, B = 0.86, A = 1 }, ColorUseRule = 0 }) end)))
P("   shadow:", tostring(pcall(function()
    text:SetShadowOffset({ X = 2, Y = 2 })
    text:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.85 })
end)))
P("   justify:", tostring(pcall(function() text:SetJustification(1) end)))

P("5 add to the HUD's main canvas, centred near the top")
local slot = hud.MainContainer:AddChild(text)
P("   slot:", tostring(slot ~= nil and slot:IsValid()), slot and slot:GetClass():GetFName():ToString() or "")
P("   anchors:", tostring(pcall(function() slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.24 }, Maximum = { X = 0.5, Y = 0.24 } }) end)))
P("   alignment:", tostring(pcall(function() slot:SetAlignment({ X = 0.5, Y = 0.5 }) end)))
P("   autosize:", tostring(pcall(function() slot:SetAutoSize(true) end)))
P("   position:", tostring(pcall(function() slot:SetPosition({ X = 0, Y = 0 }) end)))
P("   z:", tostring(pcall(function() slot:SetZOrder(60) end)))
pcall(function() text:SetVisibility(3) end)   -- shown, but never in the way of the mouse
S.probeText = text
pcall(function() P("   HUD visible:", tostring(hud:IsVisible()), " canvas visible:", tostring(hud.MainContainer:IsVisible())) end)
P("done")

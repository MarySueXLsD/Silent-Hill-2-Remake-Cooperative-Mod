-- Why is the new menu entry not drawn? Compare it with the game's own Load entry. Staged.
local menu = FindFirstOf("SHMainMenuWidget")
if not (menu and menu:IsValid()) then P("no main menu") return end
local tpl, btn = menu.Load_but, S.menuBtn
if not (btn and btn:IsValid()) then P("no entry") return end
local sbl = StaticFindObject("/Script/UMG.Default__SlateBlueprintLibrary")

local function describe(name, w)
    P("== " .. name, w:GetFullName())
    pcall(function() local d = w:GetDesiredSize() P("  desired:", string.format("%.0f x %.0f", d.X, d.Y)) end)
    pcall(function()
        local g = w:GetCachedGeometry()
        local s = sbl:GetLocalSize(g)
        local a = sbl:GetAbsoluteSize(g)
        P("  local size:", string.format("%.0f x %.0f", s.X, s.Y), " absolute:", string.format("%.0f x %.0f", a.X, a.Y))
    end)
    pcall(function() P("  visible:", tostring(w:IsVisible()), " vis:", tostring(w:GetVisibility()), " enabled:", tostring(w:GetIsEnabled()),
        " opacity:", tostring(w:GetRenderOpacity())) end)
    pcall(function() P("  Style:", tostring(w.Style and w.Style:IsValid() and w.Style:GetFullName() or "none")) end)
    pcall(function() P("  ScrollStyle:", tostring(w.ScrollStyle and w.ScrollStyle:IsValid() and w.ScrollStyle:GetFullName() or "none")) end)
    pcall(function() P("  MinDesiredWidth:", tostring(w.MinDesiredWidth), " Justification:", tostring(w.Justification), " IsFocusable:", tostring(w.IsFocusable)) end)
    pcall(function() local c = w.ColorAndOpacity P("  ColorAndOpacity:", string.format("%.2f %.2f %.2f %.2f", c.R, c.G, c.B, c.A)) end)
    pcall(function() local m = w.Margin P("  Margin:", string.format("%.0f %.0f %.0f %.0f", m.Left, m.Top, m.Right, m.Bottom)) end)
    pcall(function() local m = w.Padding P("  Padding:", string.format("%.0f %.0f %.0f %.0f", m.Left, m.Top, m.Right, m.Bottom)) end)
    pcall(function() P("  outer:", w:GetOuter():GetFullName()) end)
    pcall(function()
        local slot = w.Slot
        P("  slot:", slot:GetFullName())
        local p = slot.Padding
        P("  slot padding:", string.format("%.0f %.0f %.0f %.0f", p.Left, p.Top, p.Right, p.Bottom), " halign:", tostring(slot.HorizontalAlignment),
            " valign:", tostring(slot.VerticalAlignment))
    end)
end
describe("game's Load entry", tpl)
describe("new entry", btn)
pcall(function()
    local list = btn:GetParent()
    P("== list", list:GetFullName())
    local g = list:GetCachedGeometry()
    local s = sbl:GetLocalSize(g)
    P("  local size:", string.format("%.0f x %.0f", s.X, s.Y))
    local parent = list:GetParent()
    P("  parent:", parent and parent:IsValid() and parent:GetFullName() or "none")
end)
P("done")

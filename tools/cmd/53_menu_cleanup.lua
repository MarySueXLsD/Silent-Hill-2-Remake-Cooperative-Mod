-- Remove test copies of the menu entry left by the probes (not the mod's own entry).
local menu = FindFirstOf("SHMainMenuWidget")
if not (menu and menu:IsValid()) then P("no main menu") return end
local list = menu.Load_but:GetParent()
local doomed = {}
for i = 0, list:GetChildrenCount() - 1 do
    local c = list:GetChildAt(i)
    if c:GetFName():ToString() == "JoinCoopCopy_but" then doomed[#doomed + 1] = c end
end
for _, c in ipairs(doomed) do P("removing", c:GetFName():ToString(), tostring(list:RemoveChild(c))) end
S.testCopy = nil
P("entries left:", list:GetChildrenCount())

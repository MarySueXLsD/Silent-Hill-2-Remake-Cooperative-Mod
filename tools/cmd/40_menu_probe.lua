-- How is the main menu built? Read-only. Staged: each step prints before it runs.
P("1 find the main menu widget")
local menus = FindAllOf("SHMainMenuWidget")
P("  found:", menus and #menus or 0)
local menu
if menus then
    for i = 1, #menus do
        local m = menus[i]
        if m:IsValid() then
            local vis = "?"
            pcall(function() vis = tostring(m:IsVisible()) end)
            P("   ", m:GetFullName(), " visible:", vis)
            if not menu or vis == "true" then menu = m end
        end
    end
end
if not menu then P("no menu") return end

P("2 buttons")
local function describe(name)
    local b = menu[name]
    if not (b and b:IsValid()) then P("   " .. name .. ": none") return nil end
    local line = "   " .. name .. ": " .. b:GetClass():GetFullName()
    pcall(function() line = line .. "  enabled " .. tostring(b:GetIsEnabled()) end)
    pcall(function() line = line .. "  visible " .. tostring(b:IsVisible()) end)
    P(line)
    return b
end
local cont = describe("Continue_but")
local newg = describe("NewGame_but")
local load = describe("Load_but")
describe("Settings_but")
local quit = describe("Quit_but")

P("3 parent panel of the Load button")
local parent = load:GetParent()
P("   ", parent and parent:IsValid() and parent:GetFullName() or "none")
if parent and parent:IsValid() then
    local n = parent:GetChildrenCount()
    P("   children:", n)
    for i = 0, n - 1 do
        local c = parent:GetChildAt(i)
        if c and c:IsValid() then P(string.format("     %d  %s  %s", i, c:GetClass():GetFName():ToString(), c:GetFName():ToString())) end
    end
end

P("4 inside the Load button")
local ok, n = pcall(function() return load:GetChildrenCount() end)
P("   child count:", tostring(ok), tostring(n))
if ok then
    for i = 0, n - 1 do
        local c = load:GetChildAt(i)
        if c and c:IsValid() then
            local line = string.format("     %d  %s  %s", i, c:GetClass():GetFName():ToString(), c:GetFName():ToString())
            pcall(function() line = line .. "  text='" .. c:GetText():ToString() .. "'" end)
            P(line)
        end
    end
end
P("5 class chain of the button")
local cls = load:GetClass()
local guard = 0
while cls and cls:IsValid() and guard < 8 do P("   ", cls:GetFullName()) cls = cls:GetSuperStruct() guard = guard + 1 end
P("done")

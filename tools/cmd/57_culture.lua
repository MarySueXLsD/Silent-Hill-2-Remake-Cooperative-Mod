-- Which language is the game running in? (The engine's culture can say "en" even when the menu
-- is in Russian, so the mod looks at the menu's own text instead; this prints both.)
local lib = StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary")
if lib and lib:IsValid() then
    pcall(function() P("culture:", lib:GetCurrentCulture():ToString()) end)
    pcall(function() P("language:", lib:GetCurrentLanguage():ToString()) end)
end
local menu = FindFirstOf("SHMainMenuWidget")
if menu and menu:IsValid() then
    pcall(function() P("load entry reads:", menu.Load_but:GetText():ToString()) end)
    P("mod thinks the menu is Russian:", tostring(S.menuRussian))
end

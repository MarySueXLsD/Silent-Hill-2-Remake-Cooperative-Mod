-- Load spare slot 9 from the main menu, the way the Join co-op entry will. Staged.
local menu = FindFirstOf("SHMainMenuWidget")
if not (menu and menu:IsValid()) then P("no main menu") return end
local statics = StaticFindObject("/Script/GameBase.Default__GameBaseStatics")
P("1 slot 9 has data:", tostring(statics:SaveSlotDataExist(menu, 9)))
P("2 calling LoadSavedGame(9)")
local ok, err = pcall(function() menu:LoadSavedGame(9, nil, 0) end)
P("   ", tostring(ok), tostring(err))
P("done")

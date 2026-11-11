-- Does the game accept a save file dropped into a spare slot? Copies slot 1 to slot 9 from inside
-- the game and asks the game whether slot 9 now has data. Does not load anything. Staged.
local menu = FindFirstOf("SHMainMenuWidget")
if not (menu and menu:IsValid()) then P("no main menu") return end
local statics = StaticFindObject("/Script/GameBase.Default__GameBaseStatics")
local dir = os.getenv("LOCALAPPDATA") .. "\\SilentHill2\\Saved\\SaveGames\\76561197960271872\\"

P("1 slot 9 has data before:", tostring(statics:SaveSlotDataExist(menu, 9)))
P("2 read slot 1")
local f = io.open(dir .. "SaveGameData_1.sav", "rb")
if not f then P("   cannot open slot 1") return end
local data = f:read("a")
f:close()
P("   bytes:", #data)
P("3 write slot 9")
local o = io.open(dir .. "SaveGameData_9.sav", "wb")
if not o then P("   cannot write slot 9") return end
o:write(data)
o:close()
local c = io.open(dir .. "SaveGameData_9.sav", "rb")
P("   written bytes:", c and c:seek("end") or "?")
if c then c:close() end
P("4 slot 9 has data after:", tostring(statics:SaveSlotDataExist(menu, 9)))
pcall(function() P("   menu slot count:", menu:GetSlotsCount()) end)
P("done")

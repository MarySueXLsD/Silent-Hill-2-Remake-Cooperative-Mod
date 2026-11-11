-- Menu API checks: text values, save slots. Read-only. Staged.
local menu = FindFirstOf("SHMainMenuWidget")
if not (menu and menu:IsValid()) then P("no main menu (are you in game?)") return end
local load = menu.Load_but

P("1 FText available:", type(FText))
local okT, txt = pcall(function() return FText("Join co-op") end)
P("   construct:", tostring(okT), type(txt))
if okT then pcall(function() P("   round trip:", txt:ToString()) end) end

P("2 existing button text")
pcall(function() P("   Load:", load:GetText():ToString(), " | Continue:", menu.Continue_but:GetText():ToString()) end)
pcall(function() P("   min width", load.MinDesiredWidth, " justification", tostring(load.Justification), " focusable", tostring(load.IsFocusable)) end)
pcall(function() local s = load.Style P("   style class:", s and s:IsValid() and s:GetFullName() or "none") end)

P("3 slot of the Load button in its list")
pcall(function()
    local slot = load.Slot
    P("   ", slot:GetClass():GetFName():ToString())
    local pad = slot.Padding
    P(string.format("   padding L%.0f T%.0f R%.0f B%.0f  halign %s valign %s", pad.Left, pad.Top, pad.Right, pad.Bottom, tostring(slot.HorizontalAlignment), tostring(slot.VerticalAlignment)))
end)

P("4 save slots")
pcall(function() P("   slots count:", menu:GetSlotsCount(), " has slots:", tostring(menu:HasSlots())) end)
local statics = StaticFindObject("/Script/GameBase.Default__GameBaseStatics")
local exist = {}
for slot = 0, 40 do
    local ok, e = pcall(function() return statics:SaveSlotDataExist(menu, slot) end)
    if ok and e then exist[#exist + 1] = slot end
end
P("   slots with data (0..40):", table.concat(exist, " "))
P("5 can the game read its save folder from Lua")
local dir = os.getenv("LOCALAPPDATA") .. "\\SilentHill2\\Saved\\SaveGames\\76561197960271872\\"
local f = io.open(dir .. "SaveGameData_1.sav", "rb")
P("   open slot 1 file:", tostring(f ~= nil))
if f then P("   size:", f:seek("end")) f:close() end
P("done")

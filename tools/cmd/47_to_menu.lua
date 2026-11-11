-- Send the game back to its main menu (to test the Join co-op entry). Staged.
local UEHelpers = require("UEHelpers")
P("1 in game:", tostring(getPawn() ~= nil))
local gi = UEHelpers.GetGameInstance()
P("2 game instance:", (gi and gi:IsValid()) and gi:GetFullName() or "none")
P("3 calling BackToMainMenu")
local ok, err = pcall(function() gi:BackToMainMenu() end)
P("   ", tostring(ok), tostring(err))
P("done")

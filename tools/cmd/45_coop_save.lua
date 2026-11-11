-- Host side: write a fresh save into the co-op slot (9) on request. Staged.
local pawn = getPawn()
if not pawn then P("not in game") return end
local statics = StaticFindObject("/Script/GameBase.Default__GameBaseStatics")
local dir = os.getenv("LOCALAPPDATA") .. "\\SilentHill2\\Saved\\SaveGames\\76561197960271872\\"
local function size()
    local f = io.open(dir .. "SaveGameData_9.sav", "rb")
    if not f then return -1 end
    local n = f:seek("end")
    f:close()
    return n
end
P("1 slot 9 size before:", size())
P("2 MakeFullSave into slot 9 (not async)")
S.savingForPeer = true
local ok, err = pcall(function() statics:MakeFullSave(pawn:GetWorld(), 9, "Co-op", false, false) end)
S.savingForPeer = nil
P("   ", tostring(ok), tostring(err))
P("3 slot 9 size right after:", size())
local l = pawn:K2_GetActorLocation()
P(string.format("   player at %.0f %.0f %.0f", l.X, l.Y, l.Z))
P("done")

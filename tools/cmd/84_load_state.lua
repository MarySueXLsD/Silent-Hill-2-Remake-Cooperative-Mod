-- Read-only: how the mod's idea of "the current load" compares with the game's own clock.
-- A world clock much younger than the mod's "loaded" age means a reload went by unnoticed.
local pawn = getPawn()
if not pawn then P("no player (menu or loading)") return end
local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
local ok, t = pcall(function() return ksl:GetGameTimeInSeconds(pawn) end)
P("world clock:", ok and string.format("%.1f s", t) or ("failed: " .. tostring(t)))
pcall(function() P("player age:", string.format("%.1f s", pawn:GetGameTimeSinceCreation())) end)
P("mod thinks the load is", S.loadedAt and string.format("%.1f s", os.clock() - S.loadedAt) or "?", "old;  load counter:", tostring(S.loadGen))
pcall(function() local w = pawn:GetWorld() P("world:", w:GetFullName(), string.format("%x", w:GetAddress())) end)
P("player:", pawn:GetFullName(), string.format("%x", pawn:GetAddress()))
pcall(function() local pc = UEHelpers.GetPlayerController() P("controller:", pc:GetFullName(), string.format("%x", pc:GetAddress())) end)
P("role:", tostring(S.role), " death seen:", tostring(S.deathSeen), " restart pending:", tostring(S.restart ~= nil))
local dead = 0
for _ in pairs(S.enemyDead or {}) do dead = dead + 1 end
P("enemies remembered as dead:", dead, " peer connected:", tostring(S.peer and S.peer.connected), " peer gen:", tostring(S.peer and S.peer.gen))

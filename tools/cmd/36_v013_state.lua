-- State for v0.13: pushables, regroup key, and everything else at a glance.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
P(string.format("player at %.0f %.0f %.0f  mirror %s  avatar shown %s", me.X, me.Y, me.Z, tostring(S.mirror), tostring(S.avatarVisible)))
P("pushables tracked", #S.pushables, " pushing now:", tostring(S.myPushing))
P("F10 bound", tostring(S.regroupKey), " failed", tostring(S.regroupKeyFailed))
P("doors", #S.doors, " enemies", #S.enemies, " cutscenes", #S.cutPlayers)
local puzzles = 0
for _ in pairs(S.puzzleState) do puzzles = puzzles + 1 end
P("puzzles", puzzles, " outbox", #S.outbox)
local warned = {}
for k in pairs(S.warned) do warned[#warned + 1] = k end
table.sort(warned)
P("warnings this session:", #warned)
for _, k in ipairs(warned) do P("  " .. k:sub(1, 110)) end

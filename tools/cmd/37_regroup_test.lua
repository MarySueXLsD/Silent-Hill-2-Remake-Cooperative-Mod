-- Run twice. First run asks for a regroup and reports where we are; second run reports where we ended up.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
local n = S.snaps[#S.snaps]
if not S.regroupTest then
    S.regroupTest = { x = me.X, y = me.Y, z = me.Z }
    P(string.format("before: player at %.0f %.0f %.0f", me.X, me.Y, me.Z))
    if n then P(string.format("other player's body at %.0f %.0f %.0f (%.0f away)", n.x, n.y, n.z, math.sqrt((n.x - me.X) ^ 2 + (n.y - me.Y) ^ 2))) else P("no other player known") end
    P("F7 bound:", tostring(S.regroupKeyF7))
    S.regroupRequested = true
    P("regroup requested")
else
    local b = S.regroupTest
    P(string.format("after: player at %.0f %.0f %.0f, moved %.0f", me.X, me.Y, me.Z, math.sqrt((b.x - me.X) ^ 2 + (b.y - me.Y) ^ 2 + (b.z - me.Z) ^ 2)))
    if n then P(string.format("now %.0f from the other player's body", math.sqrt((n.x - me.X) ^ 2 + (n.y - me.Y) ^ 2))) end
    S.regroupTest = nil
end

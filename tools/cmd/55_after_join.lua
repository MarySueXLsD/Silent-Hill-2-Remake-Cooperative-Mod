-- After joining from the main menu: are we in the game, and is the mod waiting to stand beside the host?
local pawn = getPawn()
P("in game:", tostring(pawn ~= nil), " role:", tostring(S.role))
if pawn then
    local l = pawn:K2_GetActorLocation()
    P(string.format("player at %.0f %.0f %.0f", l.X, l.Y, l.Z))
    pcall(function() P("level:", pawn:GetWorld():GetFullName()) end)
end
P("waiting to regroup with the host:", tostring(S.regroupAfterLoad ~= nil), " joined via menu flag left:", tostring(S.joinedViaMenu))
P("menu refs cleared:", tostring(S.menu == nil and S.menuBtn == nil))
local warned = {}
for k in pairs(S.warned) do warned[#warned + 1] = k end
P("warnings:", #warned)
for _, k in ipairs(warned) do P("  " .. k:sub(1, 140)) end

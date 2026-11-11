local function chain(obj)
    local parts, cls, n = {}, obj:GetClass(), 0
    while cls and cls:IsValid() and n < 20 do
        parts[#parts + 1] = cls:GetFullName()
        cls = cls:GetSuperStruct()
        n = n + 1
    end
    return table.concat(parts, "\n     <- ")
end

local pc = UEHelpers.GetPlayerController()
P("controller:", pc:GetFullName())
P("  classes:", chain(pc))
local pawn = pc.Pawn
P("pawn:", pawn:GetFullName())
P("  classes:", chain(pawn))
local l = pawn:K2_GetActorLocation()
P(string.format("  loc %.0f %.0f %.0f", l.X, l.Y, l.Z))
P("world:", UEHelpers.GetWorld():GetFullName())
local gm = UEHelpers.GetGameModeBase()
P("gamemode:", gm:GetFullName())
P("  classes:", chain(gm))
local gs = gm.GameState
if gs and gs:IsValid() then P("gamestate:", gs:GetFullName()) end
local gi = UEHelpers.GetGameInstance()
P("gameinstance:", gi:GetFullName())
P("  classes:", chain(gi))

P("--- pawn components ---")
local acClass = StaticFindObject("/Script/Engine.ActorComponent")
local comps = pawn:K2_GetComponentsByClass(acClass)
for i = 1, #comps do
    local c = comps[i]
    if c and c:IsValid() then P("  " .. c:GetClass():GetFName():ToString() .. "   " .. c:GetFName():ToString()) end
end

P("--- controller components ---")
comps = pc:K2_GetComponentsByClass(acClass)
for i = 1, #comps do
    local c = comps[i]
    if c and c:IsValid() then P("  " .. c:GetClass():GetFName():ToString() .. "   " .. c:GetFName():ToString()) end
end

-- Survey of other stateful world objects near the player. Read-only. Staged.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
local function dist(a) local l = a:K2_GetActorLocation() return math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2), l end
local function short(a) return a:GetFullName():match("PersistentLevel%.(.+)$") or a:GetFullName() end

P("1 pushables")
local push = FindAllOf("SHPushableComponent")
P("  loaded:", push and #push or 0)
if push then
    for i = 1, math.min(#push, 6) do
        local c = push[i]
        if c:IsValid() then
            local o = c:GetOwner()
            local d, l = dist(o)
            local who = c.InteractingCharacter
            P(string.format("  %5.0f away  at %.0f %.0f %.0f  in use %s  %s (%s)", d, l.X, l.Y, l.Z,
                tostring(who ~= nil and who:IsValid()), short(o), c:GetClass():GetFName():ToString()))
        end
    end
end

P("2 sliding doors")
local sl = FindAllOf("SHSlidingDoorMovementComponent")
P("  loaded:", sl and #sl or 0)
if sl then
    for i = 1, math.min(#sl, 4) do
        local c = sl[i]
        if c:IsValid() then
            local o = c:GetOwner()
            local d = dist(o)
            local line = string.format("  %5.0f away  %s  state %s  saved alpha %s  range %s", d, short(o), tostring(c:GetCurrentDoorState()), tostring(c.DoorMovementAlphaSave), tostring(c.MovementRange))
            pcall(function()
                local m = c.ManagedDoorMesh
                local r = m.RelativeLocation
                line = line .. string.format("  mesh rel %.1f %.1f %.1f", r.X, r.Y, r.Z)
            end)
            P(line)
        end
    end
end

P("3 switches")
local sw = FindAllOf("InteractionSwitch_Base_BP_C")
P("  loaded:", sw and #sw or 0)
if sw then
    for i = 1, math.min(#sw, 4) do
        local a = sw[i]
        if a:IsValid() then P(string.format("  %5.0f away  used %s  %s", dist(a), tostring(a.bUsed), short(a))) end
    end
end

P("4 item containers")
local ct = FindAllOf("SHItemsContainer")
P("  loaded:", ct and #ct or 0)
if ct then
    for i = 1, math.min(#ct, 4) do
        local a = ct[i]
        if a:IsValid() then P(string.format("  %5.0f away  open %s  %s", dist(a), tostring(a.bIsOpen), short(a))) end
    end
end

P("5 valves, holes, elevators, save points")
for _, cls in ipairs({ "SHValve", "SHJumpIntoHole", "SHElevatorEngine", "SHSavePoint", "SHTraversalLadder" }) do
    local all = FindAllOf(cls)
    P("  " .. cls .. ":", all and #all or 0)
end
P("done")

-- Move the nearest closed door the way a remote player's game would, or put it back.
-- First run opens it to 40 degrees; run again to close it.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
if S.doorTest and S.doorTest.comp:IsValid() then
    local c = S.doorTest.comp
    P(string.format("door is now at %.1f (asked for %.1f); closing it again", c:GetCurrentDoorAngle(), S.doorTest.target))
    c:RequestCustomFakeMovement(S.doorTest.from, math.max(c.FakeMovementSpeed * 2, 10), c.FakeMovementBlendExp, true)
    S.doorTest = nil
    return
end
local best, bestD
for _, d in ipairs(S.doors) do
    if d.comp:IsValid() and math.abs(d.comp:GetCurrentDoorAngle()) < 1 and not d.comp.bIsDoorFrozen then
        local dist = math.sqrt((d.x - me.X) ^ 2 + (d.y - me.Y) ^ 2 + (d.z - me.Z) ^ 2)
        if not bestD or dist < bestD then best, bestD = d, dist end
    end
end
if not best then P("no closed door loaded") return end
P(string.format("1 chosen door %s, %.0f away, locked %s", best.id, bestD, tostring(best.lock and best.lock:IsValid() and best.lock.bIsDoorLocked)))
P("2 requesting 40 degrees")
best.comp:RequestCustomFakeMovement(40, math.max(best.comp:GetCurrentDoorAngle() * 0 + best.comp.FakeMovementSpeed * 2, 10), best.comp.FakeMovementBlendExp, true)
S.doorTest = { comp = best.comp, from = 0, target = 40 }
P("3 requested; angle right now", best.comp:GetCurrentDoorAngle())

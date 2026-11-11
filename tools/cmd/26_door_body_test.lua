-- Pretend the other player's body walks up to the nearest unlocked, closed door and watch it react.
-- Run 1: place the body at the door.  Run 2 (2 s later): report, take the body away.  Run 3: report.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
local T = S.bodyTest
if not T then
    local best, bestD
    for _, d in ipairs(S.doors) do
        if d.comp:IsValid() and d.leaf and math.abs(d.comp:GetCurrentDoorAngle()) < 1 and not d.comp.bIsDoorFrozen
            and not (d.lock and d.lock:IsValid() and d.lock.bIsDoorLocked) then
            local dist = math.sqrt((d.x - me.X) ^ 2 + (d.y - me.Y) ^ 2 + (d.z - me.Z) ^ 2)
            if dist > 300 and (not bestD or dist < bestD) then best, bestD = d, dist end
        end
    end
    if not best then
        P("no unlocked closed door loaded (doors tracked: " .. #S.doors .. ")")
        local locked = 0
        for _, d in ipairs(S.doors) do if d.lock and d.lock:IsValid() and d.lock.bIsDoorLocked then locked = locked + 1 end end
        P("locked doors:", locked)
        return
    end
    local L = best.leaf
    -- stand 40 units toward the +30 side of the leaf, at floor height
    local dx, dy = L[4] - L[1], L[5] - L[2]
    local len = math.sqrt(dx * dx + dy * dy)
    S.testBody = { X = L[1] + dx / len * 40, Y = L[2] + dy / len * 40, Z = L[3] - 90 }
    S.bodyTest = { door = best, step = 1 }
    P(string.format("body placed at door %s (%.0f from you), on its + side; angle now %.1f", best.id, bestD, best.comp:GetCurrentDoorAngle()))
elseif T.step == 1 then
    local c = T.door.comp
    P(string.format("with the body there: angle %.1f (opened %.1f, other side %.1f), fake target %.1f", c:GetCurrentDoorAngle(), c.OpenedAngle, c.OtherSideOpenedAngle, c:GetFakeMovementTargetAngle()))
    S.testBody = nil
    T.step = 2
    P("body taken away")
else
    local c = T.door.comp
    P(string.format("after leaving: angle %.1f, autoclose blocked %s, uses autoclose %s", c:GetCurrentDoorAngle(), tostring(c:IsAutocloseBlocked()), tostring(c.bUseAutoclose)))
    if math.abs(c:GetCurrentDoorAngle()) > 1 then c:RequestFakeClose() P("closing it again") end
    S.bodyTest = nil
end

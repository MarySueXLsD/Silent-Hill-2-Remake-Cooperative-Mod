-- Find which call actually moves a door. Run repeatedly; each run reports, then tries the next method.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
local T = S.doorProbe
if not T then
    local best, bestD
    for _, d in ipairs(S.doors) do
        if d.comp:IsValid() and math.abs(d.comp:GetCurrentDoorAngle()) < 1 and not d.comp.bIsDoorFrozen
            and not (d.lock and d.lock:IsValid() and d.lock.bIsDoorLocked) then
            local dist = math.sqrt((d.x - me.X) ^ 2 + (d.y - me.Y) ^ 2 + (d.z - me.Z) ^ 2)
            if dist > 250 and (not bestD or dist < bestD) then best, bestD = d, dist end   -- not right next to us
        end
    end
    if not best then P("no suitable closed, unlocked door") return end
    T = { comp = best.comp, step = 0, dist = bestD }
    S.doorProbe = T
    P(string.format("door %s chosen, %.0f away", best.id, bestD))
end
local c = T.comp
local function report(label)
    P(string.format("%s: angle %.1f  state %s  fake target %.1f  playing curve %s  physic force %s  cutscene %s  autoclose blocked %s",
        label, c:GetCurrentDoorAngle(), tostring(c:GetCurrentDoorState()), c:GetFakeMovementTargetAngle(),
        tostring(c:IsPlayingCurveAnim()), tostring(c:HasPhysicForce()), tostring(c:IsManagedByCutscene()), tostring(c:IsAutocloseBlocked())))
end
report("before step " .. T.step)
local steps = {
    function() P("-> RequestFakeOpen(false)") c:RequestFakeOpen(false) end,
    function() P("-> RequestFakeClose()") c:RequestFakeClose() end,
    function() P("-> SetAutocloseBlocked(true) + RequestCustomFakeMovement(45, 6, 2, true)") c:SetAutocloseBlocked(true, pawn) c:RequestCustomFakeMovement(45, 6, 2, true) end,
    function() P("-> RequestCustomFakeMovement(0, 6, 2, true) + autoclose unblocked") c:RequestCustomFakeMovement(0, 6, 2, true) c:SetAutocloseBlocked(false, pawn) end,
    function() P("-> AddPhysicForce(200)") c:AddPhysicForce(200) end,
    function() P("-> RequestFakeClose() (final)") c:RequestFakeClose() end,
}
T.step = T.step + 1
if steps[T.step] then steps[T.step]() report("right after") else P("probe finished") S.doorProbe = nil end

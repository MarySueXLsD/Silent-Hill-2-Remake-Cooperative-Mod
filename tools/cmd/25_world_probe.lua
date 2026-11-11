-- What cutscenes, pickups and door geometry are loaded around the player? Staged.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
P(string.format("player at %.0f %.0f %.0f", me.X, me.Y, me.Z))

P("1 cutscene players")
local cps = FindAllOf("SHCutscenePlayer")
P("  loaded:", cps and #cps or 0)
if cps then
    local shown = 0
    for i = 1, #cps do
        local c = cps[i]
        if c:IsValid() then
            local l = c:K2_GetActorLocation()
            local d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2)
            if shown < 6 then
                shown = shown + 1
                P(string.format("  %.0f away  playing %s  played once %s  only once %s  %s", d, tostring(c:IsPlaying()), tostring(c:IsAlreadyPlayedOnce()),
                    tostring(c.bPlayOnlyOnce), c:GetFullName():match("PersistentLevel%.(.+)$") or c:GetFullName()))
            end
        end
    end
end

P("2 cutscene triggers")
local trs = FindAllOf("TriggerCutscene_BP_C")
P("  loaded:", trs and #trs or 0)

P("3 world items")
local items = FindAllOf("SHItem")
P("  loaded:", items and #items or 0)
if items then
    local shown = 0
    for i = 1, #items do
        local it = items[i]
        if it:IsValid() and shown < 6 then
            shown = shown + 1
            local row = "?"
            pcall(function() row = it.ItemData.RowName:ToString() end)
            P(string.format("  %-28s x%d collected %s disabled %s  %s", row, it.Quantity, tostring(it.bWasCollected), tostring(it:IsItemDisabled()),
                it:GetFullName():match("PersistentLevel%.(.+)$") or "?"))
        end
    end
end

P("4 door geometry")
if S.doors and S.doors[1] then
    local best, bestD
    for _, d in ipairs(S.doors) do
        local dist = math.sqrt((d.x - me.X) ^ 2 + (d.y - me.Y) ^ 2 + (d.z - me.Z) ^ 2)
        if d.comp:IsValid() and (not bestD or dist < bestD) then best, bestD = d, dist end
    end
    local c = best.comp
    local p0, pp, pn = c:GetDoorTraceLoc(c.ClosedAngle), c:GetDoorTraceLoc(c.ClosedAngle + 30), c:GetDoorTraceLoc(c.ClosedAngle - 30)
    P(string.format("  nearest door %.0f away; actor at %.0f %.0f %.0f", bestD, best.x, best.y, best.z))
    P(string.format("  leaf closed %.0f %.0f %.0f | +30 %.0f %.0f %.0f | -30 %.0f %.0f %.0f", p0.X, p0.Y, p0.Z, pp.X, pp.Y, pp.Z, pn.X, pn.Y, pn.Z))
    P(string.format("  angle %.1f locked %s", c:GetCurrentDoorAngle(), tostring(best.lock and best.lock:IsValid() and best.lock.bIsDoorLocked)))
else
    P("  no doors tracked")
end
P("done")

-- Overall state for v0.10: doors held, cutscenes, pickups, health.
local pawn = getPawn()
local held, pushed = 0, 0
for id, st in pairs(S.doorState) do
    if st.held then held = held + 1 end
    if st.pushed then pushed = pushed + 1 end
end
P("doors tracked", #S.doors, " still held", held, " being pushed", pushed)
for _, d in ipairs(S.doors) do
    if d.comp:IsValid() and math.abs(d.comp:GetCurrentDoorAngle()) > 1 then
        P(string.format("  open door %s at %.1f, autoclose blocked %s", d.id, d.comp:GetCurrentDoorAngle(), tostring(d.comp:IsAutocloseBlocked())))
    end
end
P("cutscenes loaded", #S.cutPlayers, " playing", tostring(S.cutPlaying), " request", tostring(S.cutRequest ~= nil), " regroup pending", tostring(S.regroupAt ~= nil))
local items, collected = 0, 0
for _, v in pairs(S.itemState) do items = items + 1 if v then collected = collected + 1 end end
P("pickups seen", items, " collected", collected, " outbox", #S.outbox)
P("health", pawn.Health.HealthValue, " mirror", tostring(S.mirror), " role", S.role)
local warned = {}
for k in pairs(S.warned) do warned[#warned + 1] = k end
P("warnings:", #warned)
for _, k in ipairs(warned) do P("  " .. k) end

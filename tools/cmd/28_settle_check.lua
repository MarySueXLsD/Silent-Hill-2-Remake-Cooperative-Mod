-- Is the settle logic live, and which doors have changed lock state recently?
local now = os.clock()
P("doorSeen table:", tostring(S.doorSeen ~= nil), " itemSeen table:", tostring(S.itemSeen ~= nil))
local withSince, unsettled, locked = 0, 0, 0
for id, st in pairs(S.doorState) do
    if st.since then
        withSince = withSince + 1
        if now - st.since < 6 then unsettled = unsettled + 1 end
    end
    if st.lock then locked = locked + 1 end
end
P("door states with a first-seen time:", withSince, " still settling:", unsettled, " locked:", locked)
local pending = 0
for _ in pairs(S.pendingLocks) do pending = pending + 1 end
P("pending remote locks:", pending, " outbox:", #S.outbox)
for i = math.max(1, #S.outbox - 5), #S.outbox do P("  queued:", S.outbox[i].text) end

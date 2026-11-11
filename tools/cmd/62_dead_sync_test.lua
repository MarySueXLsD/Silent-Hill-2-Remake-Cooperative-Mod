-- Exercise the "dead there means dead here" path on the far-away test enemy from
-- 59_spawn_die_probe.lua: mark its id as dead in the other game and let the mod's own enemy pass
-- deal with it. ipc\stage.txt: "mark" or "report".
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "report"
if f then f:close() end
local sp = S.probeSpawner
if not (sp and sp:IsValid()) then P("no probe spawner; run 59 with stage spawn first") return end
local id
for k, v in pairs(S.spawnerById or {}) do
    if v:IsValid() and v:GetAddress() == sp:GetAddress() then id = k end
end
P("mod version:", SH2CoopMod.impl and SH2CoopMod.impl.version, " spawner id known to the mod:", tostring(id))
if not id then return end
if stage == "mark" then
    S.enemyDead[id] = true
    S.enemiesDue = true
    P("marked dead in the other game")
end
local actor
pcall(function() actor = sp:GetSpawnedActor() end)
if actor and actor:IsValid() then
    local t = actor:GetFName():ToString()
    pcall(function() t = t .. string.format(" hp=%d dead=%s", math.floor(actor.healthComponent:GetHealth()), tostring(actor.healthComponent:IsDead())) end)
    pcall(function() t = t .. " hidden=" .. tostring(actor.bHidden) .. " collision=" .. tostring(actor:GetActorEnableCollision()) end)
    P("enemy:", t)
else
    P("no enemy on the spawner")
end
local st = S.enemyState[id]
P("mod state:", st and ("hp=" .. tostring(st.hp) .. " tidyAt=" .. tostring(st.tidyAt) .. " killTried=" .. tostring(st.killTried ~= nil)) or "none")
local warned = {}
for k in pairs(S.warned) do if k:find("enem") then warned[#warned + 1] = k end end
P("enemy warnings:", #warned)
for _, k in ipairs(warned) do P("  " .. k:sub(1, 200)) end

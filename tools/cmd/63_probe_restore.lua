-- Put the probe's test enemy back to full health (Revive leaves it at 1) and forget it.
local sp = S.probeSpawner
if not (sp and sp:IsValid()) then P("no probe spawner") return end
local actor
pcall(function() actor = sp:GetSpawnedActor() end)
if not (actor and actor:IsValid()) then
    pcall(function() sp:Spawn() end)
    pcall(function() actor = sp:GetSpawnedActor() end)
end
if actor and actor:IsValid() then
    local h = actor.healthComponent
    pcall(function() h:SetHealth(h:GetMaxHealth()) end)
    P("health now:", math.floor(h:GetHealth()), "of", math.floor(h:GetMaxHealth()), " dead:", tostring(h:IsDead()))
end
for k, v in pairs(S.spawnerById or {}) do
    if v:IsValid() and v:GetAddress() == sp:GetAddress() then S.enemyDead[k] = nil S.enemyState[k] = nil S.spawnTried[k] = nil end
end
pcall(function() sp:Despawn() end)
P("spawner back to: spawned=" .. tostring(sp._Spawned))
S.probeSpawner, S.probeEnemy = nil, nil

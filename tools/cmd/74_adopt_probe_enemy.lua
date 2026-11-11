-- The probe spawner may spawn a moment later (the enemy class loads first). If its enemy is there
-- now, take it as the probe enemy and put it 5.5 m in front of the player.
local pawn = getPawn()
local sp = S.probeSpawner
if not (pawn and sp and sp:IsValid()) then P("no player or no probe spawner") return end
P("spawner:", sp:GetFName():ToString(), " spawned flag:", tostring(sp._Spawned), " enabled:", tostring(sp._Enabled), " active:", tostring(sp:IsActive()))
local a
pcall(function() a = sp:GetSpawnedActor() end)
if not (a and a:IsValid()) then P("still no enemy on it") return end
S.probeEnemy = a
local me, fwd = pawn:K2_GetActorLocation(), pawn:GetActorForwardVector()
P("moving it in front of the player:", tostring(pcall(function()
    a:K2_SetActorLocation({ X = me.X + fwd.X * 550, Y = me.Y + fwd.Y * 550, Z = me.Z + 20 }, false, {}, true)
end)))
pcall(function() P("enemy:", a:GetClass():GetFName():ToString(), " hp:", math.floor(a.healthComponent:GetHealth()), " active:", tostring(a:IsActive())) end)

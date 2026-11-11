-- No living enemy is near, so bring the nearest corpse back for the damage probe (73). It was dead
-- before and the probe ends with it dead again. ipc\stage.txt: "revive", or "finish" (make sure it
-- is dead again and forget it). Staged prints.
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "revive"
if f then f:close() end
local pawn = getPawn()
if not pawn then P("not in game") return end
local me = pawn:K2_GetActorLocation()

if stage == "revive" then
    local best, bestD
    for _, s in ipairs(FindAllOf("SHAISpawner") or {}) do
        if s:IsValid() then
            local a
            pcall(function() a = s:GetSpawnedActor() end)
            if a and a:IsValid() then
                local dead = false
                pcall(function() dead = a.healthComponent:IsDead() end)
                local l = a:K2_GetActorLocation()
                local d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2)
                if dead and d > 700 and (not bestD or d < bestD) then best, bestD = a, d end
            end
        end
    end
    if not best then P("no corpse further than 7 m loaded") return end
    S.probeEnemy = best
    S.probeMyHp = pawn.Health:GetHealthValue()
    P("corpse:", best:GetClass():GetFName():ToString(), string.format("%.0fm away; our health %.0f", bestD / 100, S.probeMyHp))
    P("1 Revive() on the character")
    P("   ", tostring(pcall(function() best:Revive() end)))
    local dead = true
    pcall(function() dead = best.healthComponent:IsDead() end)
    if dead then
        P("2 still dead; Revive() on its health")
        P("   ", tostring(pcall(function() best.healthComponent:Revive() end)))
    end
    P("3 full health")
    P("   ", tostring(pcall(function() best.healthComponent:SetHealth(best.healthComponent:GetMaxHealth()) end)))
    -- The mod itself knows this enemy as dead and would kill it again at once ("dead in one game
    -- means dead in both"). Make it forget, and undo the hiding it may have done.
    for _, e in ipairs(S.enemies or {}) do
        if e.actor:IsValid() and e.actor:GetAddress() == best:GetAddress() then
            S.enemyDead[e.id] = nil
            S.enemyState[e.id] = nil
            S.probeEnemyId = e.id
        end
    end
    pcall(function() best:SetActorHiddenInGame(false) best:SetActorEnableCollision(true) end)
    pcall(function() P("now: hp", math.floor(best.healthComponent:GetHealth()), "dead", tostring(best.healthComponent:IsDead()), "active", tostring(best:IsActive()),
        "deathAnim", tostring(best.AnimComponent:IsInDeathState(true))) end)
    return
end

local a = S.probeEnemy
if not (a and a:IsValid()) then P("no probe enemy") return end
local dead = false
pcall(function() dead = a.healthComponent:IsDead() end)
if not dead then
    P("still alive; killing it the plain way so it ends as it began")
    pcall(function() a.healthComponent:Kill() end)
    pcall(function() dead = a.healthComponent:IsDead() end)
end
local dying = false
pcall(function() dying = a.AnimComponent:IsInDeathState(true) end)
P("dead:", tostring(dead), " playing/played its death:", tostring(dying))
if dead and not dying then
    pcall(function() a:SetActorEnableCollision(false) a:SetActorHiddenInGame(true) end)
    P("it was standing dead, so it is hidden")
end
local now = pawn.Health:GetHealthValue()
if S.probeMyHp and now < S.probeMyHp then
    pcall(function() pawn.Health:ReceiveHeal(S.probeMyHp - now, pawn) end)
    P(string.format("our health dropped to %.0f during the test; healed back to %.0f", now, pawn.Health:GetHealthValue()))
end
S.probeEnemy, S.probeMyHp = nil, nil

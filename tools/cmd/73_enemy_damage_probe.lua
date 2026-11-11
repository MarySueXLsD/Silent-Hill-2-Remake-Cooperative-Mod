-- Does the engine's standard damage call hurt and kill an enemy the way the player's own attacks
-- do (hit reactions, death animation)? Uses a throwaway enemy from a script-only spawner, placed
-- in front of the player, and puts everything back afterwards.
-- ipc\stage.txt: "place", "tap", "lethal", "killcall", "report", "restore". Staged prints.
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "report"
if f then f:close() end
local pawn = getPawn()
if not pawn then P("not in game") return end
local me = pawn:K2_GetActorLocation()

local function describe(a)
    local t = a:GetClass():GetFName():ToString()
    pcall(function()
        local l = a:K2_GetActorLocation()
        t = t .. string.format(" %.1fm", math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2) / 100)
    end)
    pcall(function() t = t .. string.format(" hp=%d/%d dead=%s", math.floor(a.healthComponent:GetHealth()), math.floor(a.healthComponent:GetMaxHealth()), tostring(a.healthComponent:IsDead())) end)
    pcall(function() t = t .. " active=" .. tostring(a:IsActive()) .. " knocked=" .. tostring(a:IsKnockedDown()) .. " hidden=" .. tostring(a.bHidden) .. " coll=" .. tostring(a:GetActorEnableCollision()) end)
    pcall(function()
        local an = a.AnimComponent
        t = t .. " anim[death=" .. tostring(an:IsInDeathState(true)) .. " knockdown=" .. tostring(an:IsInKnockdownState(true)) .. " falter=" .. tostring(an:IsInFalterState(true)) ..
            " stagger=" .. tostring(an:IsInStaggerState(true)) .. " hit=" .. tostring(an:IsInNormalHitState(true)) .. " twitch=" .. tostring(an:IsInTwitchState(true)) .. "]"
    end)
    return t
end

if stage == "place" then
    local best, bestD
    for _, s in ipairs(FindAllOf("SHAISpawner") or {}) do
        if s:IsValid() then
            local okState = false
            pcall(function() okState = s._AutoSpawn == false and s._Spawned == 0 and s._Enabled == true end)
            if okState then
                local l = s:K2_GetActorLocation()
                local d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2)
                if d > 2500 and (not bestD or d < bestD) then best, bestD = s, d end
            end
        end
    end
    if not best then P("no unspawned script-only spawner further than 25 m") return end
    S.probeSpawner = best
    P("spawner:", best:GetFName():ToString(), string.format("%.0fm away", bestD / 100))
    P("1 Spawn()")
    P("   ", tostring(pcall(function() best:Spawn() end)))
    local a
    pcall(function() a = best:GetSpawnedActor() end)
    if not (a and a:IsValid()) then P("   no enemy came out") return end
    S.probeEnemy = a
    local fwd = pawn:GetActorForwardVector()
    local spot = { X = me.X + fwd.X * 550, Y = me.Y + fwd.Y * 550, Z = me.Z + 20 }
    P("2 moving it 5.5 m in front of the player")
    P("   ", tostring(pcall(function() a:K2_SetActorLocation(spot, false, {}, true) end)))
    P("now:", describe(a))
    return
end

local a = S.probeEnemy
if not (a and a:IsValid()) then P("no probe enemy; run stage place first") return end
P("before:", describe(a))
local statics = UEHelpers and UEHelpers.GetGameplayStatics and UEHelpers.GetGameplayStatics() or StaticFindObject("/Script/Engine.Default__GameplayStatics")
local melee = StaticFindObject("/Script/SHProto.SHMeleeBaseDamage")

if stage == "tap" or stage == "lethal" then
    local amount = stage == "tap" and 30 or 5000
    P("1 GameplayStatics:ApplyDamage(" .. amount .. ") from our own player")
    local ok, err = pcall(function() return statics:ApplyDamage(a, amount, pawn.Controller, pawn, melee) end)
    P("   ", tostring(ok), tostring(err))
    P("right after:", describe(a))
elseif stage == "ptap" then
    -- the same, as point damage (what a bullet or a swing is), with an empty hit description
    local l = a:K2_GetActorLocation()
    local dir = { X = l.X - me.X, Y = l.Y - me.Y, Z = 0 }
    P("1 GameplayStatics:ApplyPointDamage(30) from our own player")
    local ok, err = pcall(function() return statics:ApplyPointDamage(a, 30, dir, {}, pawn.Controller, pawn, melee) end)
    P("   ", tostring(ok), tostring(err))
    P("right after:", describe(a))
elseif stage == "mtap" then
    -- the AI framework's own helper on the character
    P("1 character:TakePointDamage(30) from our own player")
    local ok, err = pcall(function() return a:TakePointDamage(30, melee, pawn.Controller, pawn) end)
    P("   ", tostring(ok), tostring(err))
    P("right after:", describe(a))
elseif stage == "hdmg" then
    P("1 healthComponent:ReceiveDamage(30) credited to our own player")
    P("   ", tostring(pcall(function() a.healthComponent:ReceiveDamage(30, pawn) end)))
    P("right after:", describe(a))
elseif stage == "killcall" then
    P("1 healthComponent:Kill()")
    P("   ", tostring(pcall(function() a.healthComponent:Kill() end)))
    P("right after:", describe(a))
elseif stage == "restore" then
    local sp = S.probeSpawner
    pcall(function() a:Revive() end)
    pcall(function() if a.healthComponent:IsDead() then a.healthComponent:Revive() end end)
    pcall(function() a.healthComponent:SetHealth(a.healthComponent:GetMaxHealth()) end)
    P("revived:", describe(a))
    if sp and sp:IsValid() then
        for k, v in pairs(S.spawnerById or {}) do
            if v:IsValid() and v:GetAddress() == sp:GetAddress() then S.enemyDead[k] = nil S.enemyState[k] = nil S.spawnTried[k] = nil end
        end
        P("despawn:", tostring(pcall(function() sp:Despawn() end)), " spawned flag now:", tostring(sp._Spawned))
    end
    S.probeEnemy, S.probeSpawner = nil, nil
end

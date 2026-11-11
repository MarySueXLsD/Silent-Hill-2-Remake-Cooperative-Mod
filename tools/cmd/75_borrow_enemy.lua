-- Borrow the nearest living enemy for the damage probe (73): remember where and how it was, put it
-- 6.5 m in front of the player; "return" revives it, restores its health and place, undoes the
-- earlier test spawner, and heals the player back to what they had. ipc\stage.txt: "borrow"/"return".
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "borrow"
if f then f:close() end
local pawn = getPawn()
if not pawn then P("not in game") return end
local me = pawn:K2_GetActorLocation()

if stage == "borrow" then
    -- undo the script-only spawner the first attempt touched
    local sp = S.probeSpawner
    if sp and sp:IsValid() then
        P("undoing test spawner:", tostring(pcall(function() sp:Despawn() end)), " spawned flag:", tostring(sp._Spawned))
    end
    S.probeSpawner = nil
    local best, bestD
    for _, s in ipairs(FindAllOf("SHAISpawner") or {}) do
        if s:IsValid() then
            local a
            pcall(function() a = s:GetSpawnedActor() end)
            if a and a:IsValid() then
                local alive = false
                pcall(function() alive = not a.healthComponent:IsDead() and a.healthComponent:GetHealth() > 0 end)
                local l = a:K2_GetActorLocation()
                local d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2)
                if alive and (not bestD or d < bestD) then best, bestD = a, d end
            end
        end
    end
    if not best then P("no living enemy loaded") return end
    local l, r = best:K2_GetActorLocation(), best:K2_GetActorRotation()
    S.probeHome = { x = l.X, y = l.Y, z = l.Z, pitch = r.Pitch, yaw = r.Yaw, roll = r.Roll, hp = best.healthComponent:GetHealth(), myHp = pawn.Health:GetHealthValue() }
    S.probeEnemy = best
    P("borrowing", best:GetClass():GetFName():ToString(), string.format("from %.0fm, hp %d; our health %.0f", bestD / 100, math.floor(S.probeHome.hp), S.probeHome.myHp))
    local fwd = pawn:GetActorForwardVector()
    P("moved:", tostring(pcall(function()
        best:K2_SetActorLocation({ X = me.X + fwd.X * 650, Y = me.Y + fwd.Y * 650, Z = me.Z + 20 }, false, {}, true)
    end)))
    return
end

local a, home = S.probeEnemy, S.probeHome
if not (a and a:IsValid() and home) then P("nothing borrowed") return end
pcall(function() a:Revive() end)
pcall(function() if a.healthComponent:IsDead() then a.healthComponent:Revive() end end)
pcall(function() a.healthComponent:SetHealth(math.floor(home.hp)) end)
pcall(function() a.Controller:SetForcedEnemy(nil) end)
P("put back:", tostring(pcall(function()
    a:K2_SetActorLocationAndRotation({ X = home.x, Y = home.y, Z = home.z }, { Pitch = home.pitch, Yaw = home.yaw, Roll = home.roll }, false, {}, true)
end)))
pcall(function() P("enemy now: hp", math.floor(a.healthComponent:GetHealth()), "dead", tostring(a.healthComponent:IsDead()), "active", tostring(a:IsActive())) end)
for k, v in pairs(S.enemyState or {}) do v.tidyAt = nil end
local now = pawn.Health:GetHealthValue()
if now < home.myHp then
    pcall(function() pawn.Health:ReceiveHeal(home.myHp - now, pawn) end)
    P(string.format("our health was %.0f, dropped to %.0f, healed back to %.0f", home.myHp, now, pawn.Health:GetHealthValue()))
else
    P(string.format("our health unchanged at %.0f", now))
end
-- the mod must not treat the test kill as a real death of this enemy
for id, _ in pairs(S.enemyDead or {}) do
    for _, e in ipairs(S.enemies or {}) do
        if e.id == id and e.actor:IsValid() and e.actor:GetAddress() == a:GetAddress() then S.enemyDead[id] = nil S.enemyState[id] = nil end
    end
end
S.probeEnemy, S.probeHome = nil, nil

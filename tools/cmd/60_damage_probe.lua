-- Does the game's own point-damage call kill an enemy properly? Works on the test enemy spawned by
-- 59_spawn_die_probe.lua (stage "spawn"). Stage from ipc\stage.txt: "hit" (lethal point damage),
-- "kill" (health component's Kill), "report". Staged prints.
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "report"
if f then f:close() end
local pawn = getPawn()
local sp = S.probeSpawner
if not (pawn and sp and sp:IsValid()) then P("no player or no probe spawner") return end
local actor
pcall(function() actor = sp:GetSpawnedActor() end)
if not (actor and actor:IsValid()) then P("spawner has no enemy; spawned=" .. tostring(sp._Spawned)) return end

local function describe()
    local t = actor:GetFName():ToString()
    pcall(function()
        local h = actor.healthComponent
        t = t .. string.format(" hp=%d healthDead=%s", math.floor(h:GetHealth()), tostring(h:IsDead()))
    end)
    pcall(function() t = t .. " charDead=" .. tostring(actor:IsDead()) end)
    pcall(function() t = t .. " active=" .. tostring(actor:IsActive()) end)
    pcall(function() t = t .. " knocked=" .. tostring(actor:IsKnockedDown()) end)
    pcall(function() t = t .. " deathAnim=" .. tostring(actor.AnimComponent:IsInDeathState(true)) end)
    pcall(function() t = t .. " hidden=" .. tostring(actor.bHidden) .. " collision=" .. tostring(actor:GetActorEnableCollision()) end)
    pcall(function() t = t .. " controller=" .. tostring(actor.Controller ~= nil and actor.Controller:IsValid()) end)
    return t
end

P("before:", describe())
if stage == "hit" then
    local cls = StaticFindObject("/Script/SHProto.SHMeleeBaseDamage")
    P("1 damage class:", tostring(cls ~= nil and cls:IsValid()))
    P("2 calling TakePointDamage(500)")
    local ok, err = pcall(function() actor:TakePointDamage(500, cls, pawn.Controller, pawn) end)
    P("   ", tostring(ok), tostring(err))
    P("right after:", describe())
elseif stage == "revive" then
    -- undo a test kill: bring the enemy back and forget that the mod saw it dead
    P("1 calling Revive() on the enemy")
    local ok, err = pcall(function() actor:Revive() end)
    P("   ", tostring(ok), tostring(err))
    local dead = true
    pcall(function() dead = actor.healthComponent:IsDead() end)
    if dead then
        P("2 still dead; calling healthComponent:Revive()")
        local ok2, err2 = pcall(function() actor.healthComponent:Revive() end)
        P("   ", tostring(ok2), tostring(err2))
    end
    for k, v in pairs(S.spawnerById or {}) do
        if v:IsValid() and v:GetAddress() == sp:GetAddress() then S.enemyDead[k] = nil S.enemyState[k] = nil end
    end
    P("right after:", describe())
elseif stage == "kill" then
    P("1 calling healthComponent:Kill()")
    local ok, err = pcall(function() actor.healthComponent:Kill() end)
    P("   ", tostring(ok), tostring(err))
    P("right after:", describe())
end

-- Can the mod make a scripted spawner spawn, kill its enemy properly, and put the spawner back?
-- Three stages, picked by ipc\stage.txt: "spawn", "die", "report", "despawn". Staged prints.
local f = io.open(os.getenv("SH2_STAGE_FILE") or "H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "report"
if f then f:close() end
local pawn = getPawn()
if not pawn then P("not in game") return end
local me = pawn:K2_GetActorLocation()

local function describe(sp)
    local t = "spawned=" .. tostring(sp._Spawned)
    local actor
    pcall(function() actor = sp:GetSpawnedActor() end)
    if actor and actor:IsValid() then
        t = t .. " actor=" .. actor:GetFName():ToString()
        pcall(function()
            local h = actor.healthComponent
            t = t .. string.format(" hp=%d dead=%s", math.floor(h:GetHealth()), tostring(h:IsDead()))
        end)
        pcall(function() t = t .. " knocked=" .. tostring(actor:IsKnockedDown()) end)
        pcall(function() t = t .. " hidden=" .. tostring(actor.bHidden) .. " collision=" .. tostring(actor:GetActorEnableCollision()) end)
        pcall(function()
            local l = actor:K2_GetActorLocation()
            t = t .. string.format(" dist=%.0fm", math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2) / 100)
        end)
    else
        t = t .. " no actor"
    end
    return t, actor
end

local sp = S.probeSpawner
if stage == "spawn" then
    local best, bestD
    for _, s in ipairs(FindAllOf("SHAISpawner") or {}) do
        if s:IsValid() and s._AutoSpawn == false and s._Spawned == 0 and s._Enabled == true then
            local l = s:K2_GetActorLocation()
            local d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2)
            if d > 2500 and (not bestD or d < bestD) then best, bestD = s, d end
        end
    end
    if not best then P("no unspawned scripted spawner further than 25 m") return end
    sp = best
    S.probeSpawner = sp
    P("spawner:", sp:GetFullName():match("^%S+%s+(.+)$"), string.format("%.0fm away", bestD / 100))
    P("before:", (describe(sp)))
    P("1 calling Spawn()")
    local ok, err = pcall(function() sp:Spawn() end)
    P("   ", tostring(ok), tostring(err))
    P("after:", (describe(sp)))
    return
end
if not (sp and sp:IsValid()) then P("no probe spawner remembered; run the spawn stage first") return end
if stage == "die" then
    local text, actor = describe(sp)
    P("before:", text)
    if not actor then return end
    P("1 calling Die() on the enemy")
    local ok, err = pcall(function() actor:Die() end)
    P("   ", tostring(ok), tostring(err))
    P("right after:", (describe(sp)))
elseif stage == "despawn" then
    P("before:", (describe(sp)))
    P("1 calling Despawn()")
    local ok, err = pcall(function() sp:Despawn() end)
    P("   ", tostring(ok), tostring(err))
    P("after:", (describe(sp)))
else
    P("now:", (describe(sp)))
end

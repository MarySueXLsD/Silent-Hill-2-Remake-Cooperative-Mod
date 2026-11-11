-- The game's point-damage call on the nearest live, active enemy. ipc\stage.txt: "pick" (choose and
-- remember it), "tap" (30 damage), "lethal" (enough to kill), "report". Staged prints.
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "report"
if f then f:close() end
local pawn = getPawn()
if not pawn then P("not in game") return end
local me = pawn:K2_GetActorLocation()

if stage == "pick" then
    local best, bestD
    for _, sp in ipairs(FindAllOf("SHAISpawner") or {}) do
        if sp:IsValid() then
            local a
            pcall(function() a = sp:GetSpawnedActor() end)
            if a and a:IsValid() then
                local alive, active = false, false
                pcall(function() alive = not a.healthComponent:IsDead() end)
                pcall(function() active = a:IsActive() end)
                local l = a:K2_GetActorLocation()
                local d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2)
                if alive and active and (not bestD or d < bestD) then best, bestD = a, d end
            end
        end
    end
    S.probeEnemy = best
    if not best then P("no live, active enemy loaded") return end
    P("picked", best:GetFName():ToString(), string.format("%.0fm away", bestD / 100))
end

local actor = S.probeEnemy
if not (actor and actor:IsValid()) then P("no enemy picked") return end
local function describe()
    local t = actor:GetFName():ToString()
    pcall(function()
        local h = actor.healthComponent
        t = t .. string.format(" hp=%d dead=%s", math.floor(h:GetHealth()), tostring(h:IsDead()))
    end)
    pcall(function() t = t .. " active=" .. tostring(actor:IsActive()) .. " knocked=" .. tostring(actor:IsKnockedDown()) .. " lying=" .. tostring(actor:IsLying()) end)
    pcall(function()
        local an = actor.AnimComponent
        t = t .. " anim[death=" .. tostring(an:IsInDeathState(true)) .. " knockdown=" .. tostring(an:IsInKnockdownState(true)) ..
            " stagger=" .. tostring(an:IsInStaggerState(true)) .. " falter=" .. tostring(an:IsInFalterState(true)) ..
            " hit=" .. tostring(an:IsInNormalHitState(true)) .. " twitch=" .. tostring(an:IsInTwitchState(true)) .. "]"
    end)
    pcall(function() t = t .. " hidden=" .. tostring(actor.bHidden) .. " collision=" .. tostring(actor:GetActorEnableCollision()) end)
    return t
end
P("before:", describe())
if stage == "htap" or stage == "hlethal" then
    -- the health component's own damage call, with the player as the one who did it
    local amount = stage == "htap" and 30 or 2000
    P("1 calling healthComponent:ReceiveDamage(" .. amount .. ")")
    local ok, err = pcall(function() actor.healthComponent:ReceiveDamage(amount, pawn) end)
    P("   ", tostring(ok), tostring(err))
    P("right after:", describe())
elseif stage == "tap" or stage == "lethal" then
    local cls = StaticFindObject("/Script/SHProto.SHMeleeBaseDamage")
    local amount = stage == "tap" and 30 or 2000
    P("1 calling TakePointDamage(" .. amount .. ")")
    local ok, err = pcall(function() actor:TakePointDamage(amount, cls, pawn.Controller, pawn) end)
    P("   ", tostring(ok), tostring(err))
    P("right after:", describe())
end

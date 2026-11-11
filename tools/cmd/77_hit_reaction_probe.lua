-- Can the mod make an enemy play a given hit reaction (stagger, knockdown, death) through the
-- game's own hit-reaction system? Works on the probe enemy from 76. ipc\stage.txt:
-- "find" (locate the subcomponent only), "stagger", "knockdown", "death", "report". Staged prints.
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "report"
if f then f:close() end
local pawn = getPawn()
local a = S.probeEnemy
if not (pawn and a and a:IsValid()) then P("no player or no probe enemy") return end
local me = pawn:K2_GetActorLocation()
local function describe()
    local t = ""
    pcall(function() t = t .. string.format("hp=%d dead=%s", math.floor(a.healthComponent:GetHealth()), tostring(a.healthComponent:IsDead())) end)
    pcall(function() t = t .. " knocked=" .. tostring(a:IsKnockedDown()) .. " hidden=" .. tostring(a.bHidden) .. " coll=" .. tostring(a:GetActorEnableCollision()) end)
    pcall(function()
        local an = a.AnimComponent
        t = t .. " anim[death=" .. tostring(an:IsInDeathState(true)) .. " knockdown=" .. tostring(an:IsInKnockdownState(true)) .. " falter=" .. tostring(an:IsInFalterState(true)) ..
            " stagger=" .. tostring(an:IsInStaggerState(true)) .. " hit=" .. tostring(an:IsInNormalHitState(true)) .. " twitch=" .. tostring(an:IsInTwitchState(true)) .. "]"
    end)
    return t
end
P("before:", describe())
if stage == "report" then return end

P("1 find the hit-reaction subcomponent")
local cls = StaticFindObject("/Script/SHProto.SHHitReactionSubcomponent")
P("    class:", tostring(cls ~= nil and cls:IsValid()))
local sub
local ok, err = pcall(function() sub = a.AnimComponent:FindSubcomponentByClass(cls) end)
P("    found:", tostring(ok), tostring(sub ~= nil and sub:IsValid()), ok and "" or tostring(err))
if not (sub and sub:IsValid()) then return end
P("    it is:", sub:GetClass():GetFName():ToString())
if stage == "find" then return end

local kinds = { stagger = 3, falter = 4, knockdown = 5, death = 6, normal = 2, twitch = 1 }
local kind = kinds[stage]
if not kind then P("unknown stage") return end
local dmg = StaticFindObject("/Script/SHProto.Default__SHMeleeBaseDamage")
P("2 damage type object:", tostring(dmg ~= nil and dmg:IsValid()))
P("4 ChooseAndApplyHitReaction, type " .. kind)
local out = {}
local ok2, err2 = pcall(function()
    sub:ChooseAndApplyHitReaction(out, dmg, kind, FName("None"), 0.0, 100.0, 0, { X = me.X, Y = me.Y, Z = me.Z }, pawn, {})
end)
P("   ", tostring(ok2), tostring(err2))
P("right after the reaction:", describe())
if stage == "death" then
    P("5 now mark it dead (health Kill)")
    P("   ", tostring(pcall(function() a.healthComponent:Kill() end)))
    P("right after the kill:", describe())
end

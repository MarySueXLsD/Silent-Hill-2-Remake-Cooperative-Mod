-- Feed the mod enemy lines as if the other player had sent them, on the revived probe enemy from
-- 76: "stagger" (their hit made it stagger), "dead" (they killed it), "report".
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "report"
if f then f:close() end
local pawn = getPawn()
local impl = SH2CoopMod.impl
local a, id = S.probeEnemy, S.probeEnemyId
if not (pawn and impl and impl.debugEvent and a and a:IsValid() and id) then P("need a player, the 0.20 mod and a revived probe enemy (run 76 with stage revive)") return end
local function describe()
    local t = a:GetClass():GetFName():ToString()
    pcall(function() t = t .. string.format(" hp=%d dead=%s", math.floor(a.healthComponent:GetHealth()), tostring(a.healthComponent:IsDead())) end)
    pcall(function() t = t .. " hidden=" .. tostring(a.bHidden) .. " coll=" .. tostring(a:GetActorEnableCollision()) end)
    pcall(function()
        local an = a.AnimComponent
        t = t .. " anim[death=" .. tostring(an:IsInDeathState(true)) .. " knockdown=" .. tostring(an:IsInKnockdownState(true)) .. " stagger=" .. tostring(an:IsInStaggerState(true)) .. "]"
    end)
    return t
end
P("before:", describe())
if stage == "stagger" then
    impl.debugEvent("ereact " .. id .. " 3")
    P("sent 'it staggered' as the other player")
    P("right after:", describe())
elseif stage == "dead" then
    impl.debugEvent("edead " .. id)
    P("sent 'it died' as the other player; the mod kills it on its next enemy pass")
end

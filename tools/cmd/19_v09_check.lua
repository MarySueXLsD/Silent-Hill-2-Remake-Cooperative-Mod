-- Checks for v0.9: flashlight falloff, doors, collision capsule, melee hook.
local pawn = getPawn()
P("mirror", tostring(S.mirror), " avatar", tostring(S.avatar and S.avatar:IsValid()), " visible", tostring(S.avatarVisible))

local l = S.lightComp
if l and l:IsValid() then
    P(string.format("light: inverse-squared %s  exponent %.2f  intensity %.1f  source radius %.1f  visible %s",
        tostring(l.bUseInverseSquaredFalloff), l.LightFalloffExponent, l.Intensity, l.SourceRadius, tostring(l:IsVisible())))
else
    P("light: none (is your flashlight on, and the mirror on?)")
end

P("doors loaded", #S.doors, " mine now:", tostring(S.myDoors))
P("capsule", tostring(S.capsule and S.capsule:IsValid()), " collision on", tostring(S.collisionOn),
    S.capsule and S.capsule:IsValid() and (" enabled " .. tostring(S.capsule:GetCollisionEnabled())) or "")
P("melee hooked", tostring(S.meleeHooked), " failed", tostring(S.meleeHookFailed), " ranged comp", tostring(S.rangedComp and S.rangedComp:IsValid()), " ammo total", tostring(S.ammoTotal))
P("health", pawn.Health.HealthValue)
local warned = {}
for k in pairs(S.warned) do warned[#warned + 1] = k end
P("warnings:", #warned)
for _, k in ipairs(warned) do P("  " .. k) end

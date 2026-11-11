-- Compare the game's own flashlight light with the one we put on the other player. Staged.
local pawn = getPawn()
local fl
pawn.Items.EquipmentActors:ForEach(function(_, e)
    local a = e:get()
    if a and a:IsValid() and a:GetClass():GetFName():ToString():find("Flashlight") then fl = a end
end)
if not fl then P("no flashlight") return end
local real = fl.LightMain
local mine = S.lightComp
P("flashlight on:", tostring(fl:IsTurnOn()), " mirror:", tostring(S.mirror), " our light:", tostring(mine and mine:IsValid()))

local props = { "Intensity", "IntensityUnits", "bUseInverseSquaredFalloff", "LightFalloffExponent", "AttenuationRadius",
    "InnerConeAngle", "OuterConeAngle", "SourceRadius", "SoftSourceRadius", "SourceLength", "IndirectLightingIntensity",
    "VolumetricScatteringIntensity", "SpecularScale", "bAffectsWorld", "CastShadows", "bUseTemperature", "Temperature",
    "bUseIESBrightness", "IESBrightnessScale", "LightFunctionFadeDistance", "DisabledBrightness", "MaxDrawDistance",
    "MaxDistanceFadeRange", "Mobility", "bVisible", "bHiddenInGame", "InverseExposureBlend" }
for _, name in ipairs(props) do
    local a, b = "?", "-"
    pcall(function() a = tostring(real[name]) end)
    if mine and mine:IsValid() then pcall(function() b = tostring(mine[name]) end) end
    P(string.format("  %-30s game %-12s ours %s%s", name, a, b, (a ~= b and mine) and "   <-- differs" or ""))
end
P("light function scale (game):", pcall(function() local s = real.LightFunctionScale return s.X .. " " .. s.Y .. " " .. s.Z end))
if mine and mine:IsValid() then
    local w = mine:K2_GetComponentLocation()
    local rw = real:K2_GetComponentLocation()
    P(string.format("positions: game %.0f %.0f %.0f   ours %.0f %.0f %.0f", rw.X, rw.Y, rw.Z, w.X, w.Y, w.Z))
    P("ours registered/visible:", tostring(mine:IsVisible()))
end

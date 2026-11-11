-- How is the flashlight's light set up? Staged.
local pawn = getPawn()
local fl
pawn.Items.EquipmentActors:ForEach(function(_, e)
    local a = e:get()
    if a and a:IsValid() and a:GetClass():GetFName():ToString():find("Flashlight") then fl = a end
end)
if not fl then P("no flashlight actor") return end
P("1 actor", fl:GetFullName())
P("2 IsTurnOn", tostring(fl:IsTurnOn()))
local lm = fl.LightMain
P("3 LightMain", lm:GetFullName())
P("  visible", tostring(lm:IsVisible()))
P("  Intensity", lm.Intensity, " units", tostring(lm.IntensityUnits))
P("  Inner", lm.InnerConeAngle, " Outer", lm.OuterConeAngle, " Radius", lm.AttenuationRadius)
local c = lm.LightColor
P("  Color", c.R, c.G, c.B, c.A)
P("  CastShadows", tostring(lm.CastShadows), " Temperature", lm.Temperature, " useTemp", tostring(lm.bUseTemperature))
P("  SourceRadius", lm.SourceRadius, " VolumetricScattering", lm.VolumetricScatteringIntensity)
local wr = lm:K2_GetComponentRotation()
local wl = lm:K2_GetComponentLocation()
local ar = pawn:K2_GetActorRotation()
P(string.format("4 light world rot P%.1f Y%.1f R%.1f  actor yaw %.1f", wr.Pitch, wr.Yaw, wr.Roll, ar.Yaw))
local sl = pawn.Mesh:GetSocketLocation(FName("FlashlightSocket"))
P(string.format("  light pos %.0f %.0f %.0f  socket pos %.0f %.0f %.0f", wl.X, wl.Y, wl.Z, sl.X, sl.Y, sl.Z))
P("5 defaults: DefaultGlobalIntensity", fl.DefaultGlobalIntensity, " MainMult", fl.MainLightIntensityMultiplier)
local lf = lm.LightFunctionMaterial
P("  light function", lf and lf:IsValid() and lf:GetFullName() or "none")
local ies = lm.IESTexture
P("  IES", ies and ies:IsValid() and ies:GetFullName() or "none")
P("done")

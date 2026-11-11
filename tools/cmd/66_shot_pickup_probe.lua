-- Try the two calls behind "see the other player's pickups and shots": the game's item popup,
-- and a firearm's gunshot sound played at a spot in the world. Staged prints.
local pawn = getPawn()
if not pawn then P("not in game") return end
P("mod:", SH2CoopMod.impl and SH2CoopMod.impl.version, " shot hook:", tostring(S.shotHook), " avatar:", tostring(S.avatar ~= nil and S.avatar:IsValid()))

P("1 firearms loaded here")
local guns = FindAllOf("SHItemWeaponRanged") or {}
local event
for i = 1, #guns do
    local g = guns[i]
    if g:IsValid() then
        local ev
        pcall(function() ev = g.WeaponItemAudioComponent.ShootAudioEvent end)
        P("   ", g:GetClass():GetFName():ToString(), " shot sound:", tostring(ev ~= nil and ev:IsValid() and ev:GetFName():ToString()))
        if ev and ev:IsValid() then event = event or ev end
    end
end

P("2 item popup for one health drink (nothing is added to the inventory)")
local ui = StaticFindObject("/Script/SHProto.Default__SHGameplayUIStatics")
P("    statics found:", tostring(ui ~= nil and ui:IsValid()))
local ok, err = pcall(function() ui:RequestItemNotification(pawn, FName("HealthDrink"), 1, 1) end)
P("   ", tostring(ok), tostring(err))

if event then
    P("3 gunshot sound two metres in front of the player")
    local l = pawn:K2_GetActorLocation()
    local f = pawn:GetActorForwardVector()
    local ak = StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics")
    P("    audio statics found:", tostring(ak ~= nil and ak:IsValid()))
    local ok2, err2 = pcall(function()
        ak:PostEventAtLocation(event, { X = l.X + f.X * 200, Y = l.Y + f.Y * 200, Z = l.Z + 60 }, { Pitch = 0, Yaw = 0, Roll = 0 }, "", pawn)
    end)
    P("   ", tostring(ok2), tostring(err2))
else
    P("3 no firearm with a shot sound loaded; sound not tried")
end
P("done")

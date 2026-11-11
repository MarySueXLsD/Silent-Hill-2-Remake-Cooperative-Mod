-- Play the gun's own shot sound and a flash at the other player's body (or 2 m ahead of us when
-- alone), the way a remote shot will. Staged prints.
local pawn = getPawn()
if not pawn then P("not in game") return end
local gun = (FindAllOf("SHItemWeaponRanged") or {})[1]
if not (gun and gun:IsValid()) then P("no firearm out; draw the pistol and run again") return end
local ev = gun.WeaponItemAudioComponent.ShootAudioEvent
local path = ev:GetFullName():match("^%S+%s+(%S+)$")
P("1 this gun's shot sound:", tostring(path))
local found = StaticFindObject(path)
P("2 found again by that path:", tostring(found ~= nil and found:IsValid()))
local loc
if S.avatar and S.avatar:IsValid() and S.avatarComp and S.avatarComp:IsValid() then
    local l = S.avatarComp:GetSocketLocation(FName("hand_r"))
    loc = { X = l.X, Y = l.Y, Z = l.Z }
    P("3 at the other player's gun hand:", string.format("%.0f %.0f %.0f", l.X, l.Y, l.Z))
else
    local l, f = pawn:K2_GetActorLocation(), pawn:GetActorForwardVector()
    loc = { X = l.X + f.X * 200, Y = l.Y + f.Y * 200, Z = l.Z + 60 }
    P("3 no other player here; two metres ahead of us")
end
local ak = StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics")
local ok, err = pcall(function() ak:PostEventAtLocation(found, loc, { Pitch = 0, Yaw = 0, Roll = 0 }, "", pawn) end)
P("4 sound posted:", tostring(ok), tostring(err))
P("done")

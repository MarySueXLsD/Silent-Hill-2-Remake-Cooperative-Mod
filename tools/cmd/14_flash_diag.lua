local pawn = getPawn()
P("cfg my_model", S.cfg.my_model, " other_model", S.cfg.other_model, " sync_flashlight", S.cfg.sync_flashlight, " mirror", tostring(S.mirror))
P("avatar model", tostring(S.avatarModel), " my flash", S.myFlash and table.concat(S.myFlash, " ") or "none")
local newest = S.snaps[#S.snaps]
P("newest snap fl", newest and tostring(newest.fl) or "no snaps", " snaps", #S.snaps)
local l = S.lightComp
if l and l:IsValid() then
    local w, r = l:K2_GetComponentLocation(), l:K2_GetComponentRotation()
    local a = S.avatar:K2_GetActorLocation()
    P(string.format("light visible flag %s, IsVisible %s, intensity %.1f, pos %.0f %.0f %.0f (avatar %.0f %.0f %.0f), rot P%.1f Y%.1f",
        tostring(S.lightVisible), tostring(l:IsVisible()), l.Intensity, w.X, w.Y, w.Z, a.X, a.Y, a.Z, r.Pitch, r.Yaw))
    P("light attach socket:", l:GetAttachSocketName():ToString())
else
    P("light: none")
end
P("--- where James's flashlight pocket is ---")
local m = pawn.Mesh
P("socket bone:", m:GetSocketBoneName(FName("FlashlightSocket")):ToString(), " radio bone:", m:GetSocketBoneName(FName("RadioSocket")):ToString())
for _, s in ipairs({ "FlashlightSocket", "RadioSocket" }) do
    local t = m:GetSocketTransform(FName(s), 3)   -- relative to its parent bone
    P(string.format("  %s rel pos %.2f %.2f %.2f  quat %.4f %.4f %.4f %.4f", s, t.Translation.X, t.Translation.Y, t.Translation.Z, t.Rotation.X, t.Rotation.Y, t.Rotation.Z, t.Rotation.W))
end
P("avatar has bone for it:", tostring(S.avatarComp and S.avatarComp:IsValid() and S.avatarComp:GetBoneIndex(m:GetSocketBoneName(FName("FlashlightSocket")))))

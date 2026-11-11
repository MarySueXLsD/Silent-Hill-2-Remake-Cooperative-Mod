P(string.format("frames %d  ticks %d  gen %d  mirror %s", S.frameCount or 0, S.tickCount, S.gen, tostring(S.mirror)))
P("cfg my_model", S.cfg.my_model, " other_model", S.cfg.other_model, " share_inventory", S.cfg.share_inventory, " flashlight", S.cfg.sync_flashlight)
P("avatar", tostring(S.avatar and S.avatar:IsValid()), " model", tostring(S.avatarModel), " pelvisScale", tostring(S.pelvisScale), " jamesRefZ", tostring(S.jamesRefZ))
P("held comps", S.heldComps and #S.heldComps or 0)
P("my flash", S.myFlash and table.concat(S.myFlash, " ") or "none")
local l = S.lightComp
if l and l:IsValid() then
    local r = l:K2_GetComponentRotation()
    local w = l:K2_GetComponentLocation()
    P(string.format("light: visible %s  intensity %.1f  cone %.0f/%.0f  rot P%.1f Y%.1f  pos %.0f %.0f %.0f",
        tostring(S.lightVisible), l.Intensity, l.InnerConeAngle, l.OuterConeAngle, r.Pitch, r.Yaw, w.X, w.Y, w.Z))
else
    P("light: none")
end
if S.avatarComp and S.avatarComp:IsValid() then
    P("avatar bones", S.avatarComp:GetNumBones())
    local n = 0
    for _, b in ipairs({ "pelvis_bn", "spine_03_bn", "head_bn", "upperarm_r_bn", "hand_r_bn", "hand_r_socket", "thigh_l_bn", "foot_r_bn", "ball_l_bn" }) do
        if S.avatarComp:GetBoneIndex(FName(b)) >= 0 then n = n + 1 else P("  missing bone", b) end
    end
    P("  sample bones present:", n, "of 9", " FlashlightSocket:", tostring(S.avatarComp:DoesSocketExist(FName("FlashlightSocket"))))
end

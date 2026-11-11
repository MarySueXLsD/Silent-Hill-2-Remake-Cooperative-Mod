-- Turn on the solo mirror and compare the avatar's bones with the real James.
S.mirror = true
P("mirror on; avatar valid:", tostring(S.avatar and S.avatar:IsValid()), " comp valid:", tostring(S.avatarComp and S.avatarComp:IsValid()))
P("my pose numbers:", S.myPose and #S.myPose or "none")
if S.avatarComp and S.avatarComp:IsValid() then
    local pawn = getPawn()
    for _, b in ipairs({ "pelvis_bn", "spine_03_bn", "head_bn", "lowerarm_r_bn", "hand_l_bn", "calf_l_bn", "foot_r_bn" }) do
        local src = pawn.Mesh:GetSocketTransform(FName(b), 2).Translation
        local dst = S.avatarComp:GetBoneLocationByName(FName(b), 1)
        P(string.format("  %-14s real %7.1f %7.1f %7.1f   avatar %7.1f %7.1f %7.1f   off %.1f", b,
            src.X, src.Y, src.Z, dst.X, dst.Y, dst.Z,
            math.sqrt((src.X - dst.X) ^ 2 + (src.Y - dst.Y) ^ 2 + (src.Z - dst.Z) ^ 2)))
    end
    local a, p = S.avatar:K2_GetActorLocation(), pawn:K2_GetActorLocation()
    P(string.format("  avatar actor at %.0f %.0f %.0f, player at %.0f %.0f %.0f", a.X, a.Y, a.Z, p.X, p.Y, p.Z))
end

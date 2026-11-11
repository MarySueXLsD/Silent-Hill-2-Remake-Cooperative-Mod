-- Health check of the running mod.
P(string.format("clock %.3f  frames %d  ticks %d  gen %d  mirror %s", os.clock(), S.frameCount or 0, S.tickCount, S.gen, tostring(S.mirror)))
P("snaps", #S.snaps, " avatar", tostring(S.avatar and S.avatar:IsValid()), " held comps", S.heldComps and #S.heldComps or 0)
P("my held:", S.myHeld or "none")
if #S.snaps >= 2 then
    local a, b = S.snaps[#S.snaps - 1], S.snaps[#S.snaps]
    P(string.format("last snapshot gap %.0f ms, newest is %.0f ms old", (b.t - a.t) * 1000, (os.clock() - b.t) * 1000))
end
if S.avatarComp and S.avatarComp:IsValid() then
    local pawn = getPawn()
    local worst = 0
    for _, b in ipairs({ "pelvis_bn", "head_bn", "hand_r_bn", "hand_l_bn", "foot_l_bn", "foot_r_bn" }) do
        local src = pawn.Mesh:GetSocketTransform(FName(b), 2).Translation
        local dst = S.avatarComp:GetBoneLocationByName(FName(b), 1)
        local d = math.sqrt((src.X - dst.X) ^ 2 + (src.Y - dst.Y) ^ 2 + (src.Z - dst.Z) ^ 2)
        if d > worst then worst = d end
    end
    P(string.format("worst bone offset vs real James right now: %.1f (he is drawn 100 ms in the past)", worst))
end
for i, c in ipairs(S.heldComps or {}) do
    if c:IsValid() then
        local w = c:K2_GetComponentLocation()
        P(string.format("  held %d: %s socket %s at %.0f %.0f %.0f", i, c:GetClass():GetFName():ToString(), c:GetAttachSocketName():ToString(), w.X, w.Y, w.Z))
    end
end

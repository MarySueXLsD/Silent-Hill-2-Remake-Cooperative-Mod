local pawn = getPawn()
P(string.format("frames %s  hooked %s  lastFrame age %.2fs", tostring(S.frameCount), tostring(S.frameHooked), os.clock() - (S.lastFrame or 0)))
P("cfg my_model", S.cfg.my_model, " show_my_model_to_me", S.cfg.show_my_model_to_me, " other_model", S.cfg.other_model)
P("self model", tostring(S.selfModel), " comp", tostring(S.selfComp and S.selfComp:IsValid()), " bones", S.selfBones and #S.selfBones or 0, " scale", tostring(S.selfScale))
P("real James visible:", tostring(pawn.Mesh:IsVisible()), " tick option:", tostring(pawn.Mesh.VisibilityBasedAnimTickOption))
if S.selfComp and S.selfComp:IsValid() then
    local worst = 0
    for _, b in ipairs({ "head_bn", "hand_r_bn", "hand_l_bn", "foot_l_bn", "index_02_r_bn" }) do
        local src = pawn.Mesh:GetSocketLocation(FName(b))
        local dst = S.selfComp:GetBoneLocationByName(FName(b), 0)   -- world space
        local d = math.sqrt((src.X - dst.X) ^ 2 + (src.Y - dst.Y) ^ 2 + (src.Z - dst.Z) ^ 2)
        P(string.format("  %-14s real-vs-model distance %.1f", b, d))
    end
end
P("avatar model", tostring(S.avatarModel), " held comps", S.heldComps and #S.heldComps or 0)
for i, c in ipairs(S.heldComps or {}) do
    if c:IsValid() then
        local w = c:K2_GetComponentLocation()
        local a = S.avatar:K2_GetActorLocation()
        P(string.format("  held %d on '%s', %.0f above the avatar's feet", i, c:GetAttachSocketName():ToString(), w.Z - a.Z))
    end
end
local l = S.lightComp
if l and l:IsValid() then
    local r = l:K2_GetComponentRotation()
    P(string.format("light on '%s': visible %s, rot P%.1f Y%.1f (mine P%.1f Y%.1f)", l:GetAttachSocketName():ToString(), tostring(l:IsVisible()), r.Pitch, r.Yaw, (S.myFlash and S.myFlash[2] or 0) / 10, (S.myFlash and S.myFlash[3] or 0) / 10))
else
    P("light: none")
end
local warned = {}
for k in pairs(S.warned) do warned[#warned + 1] = k end
P("warnings:", #warned)
for _, k in ipairs(warned) do P("  " .. k) end

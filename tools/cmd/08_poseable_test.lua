-- Can we build a second James whose bones we set ourselves? Staged: each step prints first.
local pawn = getPawn()
P("0 world and statics")
local world = pawn:GetWorld()
local statics = UEHelpers.GetGameplayStatics()
P("  ", world:GetFullName(), statics:GetFullName())

P("1 find classes")
local actorCls = StaticFindObject("/Script/Engine.Actor")
local poseCls = StaticFindObject("/Script/Engine.PoseableMeshComponent")
P("  ", actorCls:IsValid(), poseCls:IsValid())

P("2 spawn plain actor")
local loc = pawn:K2_GetActorLocation()
local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = loc.X + 150, Y = loc.Y, Z = loc.Z - 90 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
local actor = statics:BeginDeferredActorSpawnFromClass(world, actorCls, xf, 1, nil)
statics:FinishSpawningActor(actor, xf)
P("  ", actor:GetFullName())

P("3 add poseable mesh component")
local ident = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
local comp = actor:AddComponentByClass(poseCls, false, ident, false)
P("  ", comp:GetFullName())

P("4 root component")
local root = actor.RootComponent
P("  ", root and root:IsValid() and root:GetFullName() or "none")

P("5 find James's mesh asset")
local asset
local ok, a = pcall(function() return pawn.Mesh.SkeletalMeshAsset end)
if ok and a and a:IsValid() then asset = a end
if not asset then
    ok, a = pcall(function() return pawn.Mesh.SkeletalMesh end)
    if ok and a and a:IsValid() then asset = a end
end
P("  ", asset and asset:GetFullName() or "none")

P("6 assign mesh")
comp:SetSkinnedAssetAndUpdate(asset, true)
P("  bones:", comp:GetNumBones())

P("7 read a bone from the real James (component space)")
local t = pawn.Mesh:GetSocketTransform(FName("head_bn"), 2)
P(string.format("  rot %.3f %.3f %.3f %.3f  pos %.1f %.1f %.1f", t.Rotation.X, t.Rotation.Y, t.Rotation.Z, t.Rotation.W, t.Translation.X, t.Translation.Y, t.Translation.Z))

P("8 read same bone on the copy")
local r0 = comp:GetBoneRotationByName(FName("head_bn"), 1)
P(string.format("  P%.1f Y%.1f R%.1f", r0.Pitch, r0.Yaw, r0.Roll))

P("9 set that bone on the copy")
comp:SetBoneRotationByName(FName("head_bn"), { Pitch = 10, Yaw = 20, Roll = 30 }, 1)
local r1 = comp:GetBoneRotationByName(FName("head_bn"), 1)
P(string.format("  P%.1f Y%.1f R%.1f", r1.Pitch, r1.Yaw, r1.Roll))

P("10 move the actor")
actor:K2_SetActorLocation({ X = loc.X + 200, Y = loc.Y, Z = loc.Z - 90 }, false, {}, true)
local l2 = actor:K2_GetActorLocation()
P(string.format("  %.0f %.0f %.0f", l2.X, l2.Y, l2.Z))

S.poseTest = { actor = actor, comp = comp }
P("done")

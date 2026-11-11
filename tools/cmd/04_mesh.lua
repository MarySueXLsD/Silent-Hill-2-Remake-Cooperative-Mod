-- Staged on purpose: every step prints before it runs, so if the game dies the last line in
-- result.txt names the culprit.
local pawn = UEHelpers.GetPlayerController().Pawn
local mesh = pawn.Mesh

P("step 1: main mesh name")
P("  ", mesh:GetFullName())

P("step 2: mesh asset")
local a = mesh.SkeletalMeshAsset
P("  ", a and a:IsValid() and a:GetFullName() or "none")

P("step 3: anim class")
local ac = mesh.AnimClass
P("  ", ac and ac:IsValid() and ac:GetFullName() or "none")

P("step 4: bone count")
local n = mesh:GetNumBones()
P("  ", n)

P("step 5: first bone name")
local b0 = mesh:GetBoneName(0)
P("  ", b0:ToString())

P("step 6: all bone names")
local names = {}
for i = 0, n - 1 do names[#names + 1] = mesh:GetBoneName(i):ToString() end
P("  " .. table.concat(names, " "))

P("step 7: parent of bone 1")
if n > 1 then P("  ", mesh:GetParentBone(mesh:GetBoneName(1)):ToString()) end

P("step 8: all parents")
local parents = {}
for i = 1, n - 1 do parents[#parents + 1] = mesh:GetParentBone(mesh:GetBoneName(i)):ToString() end
P("  " .. table.concat(parents, " "))

P("step 9: attached children of main mesh")
local kids = mesh.AttachChildren
P("  count", #kids)
kids:ForEach(function(i, e)
    local c = e:get()
    if c and c:IsValid() then P("   " .. c:GetClass():GetFName():ToString() .. "  " .. c:GetFName():ToString()) end
end)
P("done")

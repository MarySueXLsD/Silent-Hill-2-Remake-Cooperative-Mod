-- What is James holding / wearing? Staged: each step prints before it runs.
local pawn = getPawn()

local function describe(a)
    P("  actor:", a:GetFullName())
    P("    class:", a:GetClass():GetFName():ToString())
    local mesh = a.Mesh
    if mesh and mesh:IsValid() then
        local mc = mesh:GetClass():GetFName():ToString()
        P("    mesh comp:", mc, mesh:GetFName():ToString())
        if mc:find("Static") then
            local sm = mesh.StaticMesh
            P("    static mesh:", sm and sm:IsValid() and sm:GetFullName() or "none")
        else
            local ok, sk = pcall(function() return mesh.SkeletalMesh end)
            P("    skeletal mesh:", ok and sk and sk:IsValid() and sk:GetFullName() or "none")
        end
        P("    mesh attach socket:", mesh:GetAttachSocketName():ToString())
        local ap = mesh.AttachParent
        P("    mesh attach parent:", ap and ap:IsValid() and ap:GetFullName() or "none")
        local l, r = mesh.RelativeLocation, mesh.RelativeRotation
        P(string.format("    mesh rel loc %.2f %.2f %.2f  rot P%.1f Y%.1f R%.1f", l.X, l.Y, l.Z, r.Pitch, r.Yaw, r.Roll))
        P("    mesh visible:", tostring(mesh:IsVisible()))
    else
        P("    no Mesh")
    end
    local root = a.RootComponent
    if root and root:IsValid() then
        P("    root:", root:GetClass():GetFName():ToString(), " socket:", root:GetAttachSocketName():ToString())
        local ap = root.AttachParent
        P("    root attach parent:", ap and ap:IsValid() and ap:GetFullName() or "none")
        local l, r = root.RelativeLocation, root.RelativeRotation
        P(string.format("    root rel loc %.2f %.2f %.2f  rot P%.1f Y%.1f R%.1f", l.X, l.Y, l.Z, r.Pitch, r.Yaw, r.Roll))
    end
    P("    EquipAttachSocket:", a.EquipAttachSocket:ToString())
    P("    hidden actor:", tostring(a.bHidden))
end

P("1 equipment actors")
local eq = pawn.Items.EquipmentActors
P("  count", #eq)
eq:ForEach(function(i, e)
    local a = e:get()
    if a and a:IsValid() then describe(a) end
end)

P("2 weapons in the world")
local all = FindAllOf("SHItemWeapon")
P("  found", all and #all or 0)
if all then
    for i = 1, #all do
        local w = all[i]
        if w:IsValid() then
            local owner = w.OwnerCharacter
            P("  weapon", i, "owner is player:", tostring(owner and owner:IsValid() and owner:GetFullName() == pawn:GetFullName()))
            describe(w)
        end
    end
end
P("done")

-- How do doors and ammo counters look at runtime? Staged: each step prints before it runs.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()

P("1 find doors manager")
local mgr = FindFirstOf("SHDoorsManagerComponent")
P("  ", mgr and mgr:IsValid() and mgr:GetFullName() or "none")
if mgr and mgr:IsValid() then
    P("2 registered door movement components")
    local arr = mgr.RegisteredDoorMovementComponents
    P("  count", #arr)
    local near = {}
    arr:ForEach(function(i, e)
        local c = e:get()
        if c and c:IsValid() then
            local owner = c:GetOwner()
            local l = owner:K2_GetActorLocation()
            local d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2)
            near[#near + 1] = { d = d, c = c, owner = owner }
        end
    end)
    table.sort(near, function(a, b) return a.d < b.d end)
    P("3 nearest doors")
    for i = 1, math.min(5, #near) do
        local n = near[i]
        local c = n.c
        P(string.format("  %.0f away: %s", n.d, n.owner:GetFullName()))
        P("     comp name:", c:GetFName():ToString())
        P(string.format("     angle %.1f  closed %.1f  opened %.1f  other side %.1f  both sides %s", c:GetCurrentDoorAngle(), c.ClosedAngle, c.OpenedAngle, c.OtherSideOpenedAngle, tostring(c.OpenBothSides)))
        P(string.format("     fake speed %.1f  blend %.2f  frozen %s  state %s", c.FakeMovementSpeed, c.FakeMovementBlendExp, tostring(c.bIsDoorFrozen), tostring(c:GetCurrentDoorState())))
        local lock = c.ManagedDoorLockComponent
        P("     lock:", lock and lock:IsValid() and tostring(lock.bIsDoorLocked) or "no lock component")
    end
end

P("4 ranged combat subcomponent")
local ranged = FindFirstOf("SHRangedCmbSubcomp")
P("  ", ranged and ranged:IsValid() and ranged:GetFullName() or "none")
if ranged and ranged:IsValid() then
    P("5 ammo in clips")
    local total = 0
    ranged.WeaponsAmmoCounts:ForEach(function(k, v)
        local name, count = k:get():ToString(), v:get()
        total = total + count
        P("    ", name, count)
    end)
    P("  total", total)
    P("6 equipped ranged weapon")
    local w = ranged:GetEquippedRangedWeapon()
    P("  ", w and w:IsValid() and w:GetFullName() or "none")
    if w and w:IsValid() then
        local o, d = w:GetStartTraceLoc(), w:GetPerfectShootVector()
        P(string.format("  trace start %.0f %.0f %.0f   shoot vector %.3f %.3f %.3f   max distance %.0f", o.X, o.Y, o.Z, d.X, d.Y, d.Z, w.MaxShootDistance))
    end
end

P("7 melee subcomponent and damage classes")
local melee = FindFirstOf("SHMeleeCmbSubcomp")
P("  ", melee and melee:IsValid() and melee:GetFullName() or "none")
for _, n in ipairs({ "/Script/SHProto.SHFirearmBaseDamage", "/Script/SHProto.SHMeleeBaseDamage" }) do
    local c = StaticFindObject(n)
    P("  ", n, tostring(c and c:IsValid()))
end
local cap = pawn.CapsuleComponent
P(string.format("8 capsule radius %.1f half height %.1f", cap:GetScaledCapsuleRadius(), cap:GetScaledCapsuleHalfHeight()))
P("done")

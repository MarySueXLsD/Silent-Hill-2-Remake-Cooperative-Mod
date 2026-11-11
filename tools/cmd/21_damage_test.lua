-- Apply 1 point of friendly-fire style damage through the game's own path, then heal it back.
-- Staged: each step prints before it runs.
local pawn = getPawn()
local before = pawn.Health.HealthValue
P("1 health before", before)
local cls = StaticFindObject("/Script/SHProto.SHMeleeBaseDamage")
P("2 damage class", tostring(cls and cls:IsValid()))
P("3 calling Combat:ReceiveDamage(1)")
local ok, err = pcall(function() pawn.Combat:ReceiveDamage(1, pawn, { X = 1, Y = 0, Z = 0 }, cls) end)
P("  ", tostring(ok), tostring(err))
local after = pawn.Health.HealthValue
P("4 health after", after)
if after < before then
    P("5 healing back", before - after)
    pawn.Health:ReceiveHeal(before - after, pawn)
    P("  health now", pawn.Health.HealthValue)
else
    P("5 health did not change through the combat path; trying Health:ReceiveDamage(1)")
    local ok2, err2 = pcall(function() pawn.Health:ReceiveDamage(1, pawn, false) end)
    P("  ", tostring(ok2), tostring(err2), " health", pawn.Health.HealthValue)
    local now = pawn.Health.HealthValue
    if now < before then pawn.Health:ReceiveHeal(before - now, pawn) P("  healed back to", pawn.Health.HealthValue) end
end
P("done")

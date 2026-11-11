-- Does the combat path apply damage when the attacker is another actor (the avatar), not ourselves?
-- Staged; heals back whatever it took.
local pawn = getPawn()
local before = pawn.Health.HealthValue
P("1 health before", before, " avatar", tostring(S.avatar and S.avatar:IsValid()))
if not (S.avatar and S.avatar:IsValid()) then P("need the mirror on (F9)") return end
local cls = StaticFindObject("/Script/SHProto.SHMeleeBaseDamage")
P("2 Combat:ReceiveDamage(1) with the avatar as attacker")
local ok, err = pcall(function() pawn.Combat:ReceiveDamage(1, S.avatar, { X = 1, Y = 0, Z = 0 }, cls) end)
P("  ", tostring(ok), tostring(err))
local after = pawn.Health.HealthValue
P("3 health after", after)
if after < before then
    pawn.Health:ReceiveHeal(before - after, pawn)
    P("4 healed back to", pawn.Health.HealthValue)
end
P("done")

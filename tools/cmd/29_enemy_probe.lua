-- What enemies and spawners are loaded, and what can we read from them? Staged.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
P(string.format("player at %.0f %.0f %.0f", me.X, me.Y, me.Z))

P("1 spawners")
local sp = FindAllOf("SHAISpawner")
P("  loaded:", sp and #sp or 0)
local list = {}
if sp then
    for i = 1, #sp do
        local s = sp[i]
        if s:IsValid() then
            local l = s:K2_GetActorLocation()
            list[#list + 1] = { s = s, d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2) }
        end
    end
end
table.sort(list, function(a, b) return a.d < b.d end)
for i = 1, math.min(6, #list) do
    local s = list[i].s
    P(string.format("  %.0f away  %s", list[i].d, s:GetFullName():match("PersistentLevel%.(.+)$") or "?"))
    P("     enabled", tostring(s._Enabled), " spawned count", tostring(s._Spawned), " auto", tostring(s._AutoSpawn))
    local a = s:GetSpawnedActor()
    if a and a:IsValid() then
        local al = a:K2_GetActorLocation()
        P(string.format("     actor %s at %.0f %.0f %.0f", a:GetClass():GetFName():ToString(), al.X, al.Y, al.Z))
        local h = a.healthComponent
        if h and h:IsValid() then
            P(string.format("     health %s / %s  dead %s  immortal %s", tostring(h:GetHealth()), tostring(h:GetMaxHealth()), tostring(h:IsDead()), tostring(h:IsImmortal())))
        end
        local c = a.Controller
        if c and c:IsValid() then
            P("     controller", c:GetClass():GetFName():ToString())
            local arch, forced, fight = c:GetArchEnemy(), c:GetForcedEnemy(), c:GetFightingEnemy()
            P("     arch enemy:", arch and arch:IsValid() and arch:GetFName():ToString() or "none",
                " forced:", forced and forced:IsValid() and forced:GetFName():ToString() or "none",
                " fighting:", fight and fight:IsValid() and fight:GetFName():ToString() or "none")
        else
            P("     no controller")
        end
    else
        P("     nothing spawned")
    end
end

P("2 enemy characters loaded (any source)")
local chars = FindAllOf("SHAICharacter")
P("  loaded:", chars and #chars or 0)
P("done")

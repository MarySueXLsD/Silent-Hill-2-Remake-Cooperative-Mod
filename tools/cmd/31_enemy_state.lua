-- State of the enemy sync.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
P("version check: enemies tracked", #S.enemies, " role", S.role, " mirror", tostring(S.mirror), " avatar shown", tostring(S.avatarVisible))
P("my enemy line:", tostring(S.myEnemies))
P("my hunted line:", tostring(S.myHunted))
local alive, forced = 0, 0
for _, e in ipairs(S.enemies) do
    if e.actor:IsValid() then
        local hp = e.health:GetHealth()
        local st = S.enemyState[e.id]
        if hp > 0 then alive = alive + 1 end
        if st and st.forced then forced = forced + 1 end
        local l = e.actor:K2_GetActorLocation()
        local d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2)
        if d < 3000 then
            local who = "?"
            pcall(function()
                local arch = e.actor.Controller:GetArchEnemy()
                who = (arch and arch:IsValid()) and arch:GetFName():ToString() or "none"
            end)
            P(string.format("  %s  %-22s %5.0f away  hp %d  hunting %s%s", e.id, e.actor:GetClass():GetFName():ToString(), d, hp, who, (st and st.forced) and "  [sent after the other player]" or ""))
        end
    end
end
P("alive", alive, " sent after the other player", forced, " outbox", #S.outbox)
local warned = {}
for k in pairs(S.warned) do warned[#warned + 1] = k end
P("warnings:", #warned)
for _, k in ipairs(warned) do P("  " .. k) end

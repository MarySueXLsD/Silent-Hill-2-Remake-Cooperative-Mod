-- Read-only: every enemy spawner loaded here, whether it has spawned, and the state of its enemy.
local pawn = getPawn()
if not pawn then P("not in game") return end
local me = pawn:K2_GetActorLocation()
local spawners = FindAllOf("SHAISpawner") or {}
P("spawners loaded:", #spawners, " role:", tostring(S.role), " peer connected:", tostring(peer and peer.connected))
local rows = {}
for i = 1, #spawners do
    local sp = spawners[i]
    if sp:IsValid() then
        local l = sp:K2_GetActorLocation()
        local d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2)
        local row = { d = d, text = string.format("%5.0fm  %s", d / 100, sp:GetFName():ToString()) }
        pcall(function() row.text = row.text .. "  enabled=" .. tostring(sp._Enabled) .. " auto=" .. tostring(sp._AutoSpawn) .. " spawned=" .. tostring(sp._Spawned) end)
        pcall(function() row.text = row.text .. " active=" .. tostring(sp:IsActive()) end)
        local actor
        pcall(function() actor = sp:GetSpawnedActor() end)
        if actor and actor:IsValid() then
            row.text = row.text .. "  | " .. actor:GetClass():GetFName():ToString()
            pcall(function()
                local h = actor.healthComponent
                row.text = row.text .. string.format(" hp=%d/%d dead=%s", math.floor(h:GetHealth()), math.floor(h:GetMaxHealth()), tostring(h:IsDead()))
            end)
            pcall(function() row.text = row.text .. " knocked=" .. tostring(actor:IsKnockedDown()) end)
            pcall(function() row.text = row.text .. " hidden=" .. tostring(actor.bHidden) .. " collision=" .. tostring(actor:GetActorEnableCollision()) end)
        else
            row.text = row.text .. "  | no actor"
        end
        rows[#rows + 1] = row
    end
end
table.sort(rows, function(a, b) return a.d < b.d end)
for i = 1, math.min(#rows, 25) do P(rows[i].text) end

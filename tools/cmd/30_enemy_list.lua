-- List every loaded enemy: distance, health, target, aggro. Read-only.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
local pawnAddr = pawn:GetAddress()
local chars = FindAllOf("SHAICharacter")
local rows = {}
if chars then
    for i = 1, #chars do
        local a = chars[i]
        if a:IsValid() then
            local l = a:K2_GetActorLocation()
            rows[#rows + 1] = { a = a, d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2) }
        end
    end
end
table.sort(rows, function(x, y) return x.d < y.d end)
P("enemies loaded:", #rows, " avatar valid:", tostring(S.avatar and S.avatar:IsValid()), " mirror:", tostring(S.mirror))
for _, r in ipairs(rows) do
    local a = r.a
    local line = string.format("%5.0f away  %-24s", r.d, a:GetClass():GetFName():ToString())
    pcall(function()
        local h = a.healthComponent
        line = line .. string.format("  hp %s/%s%s", tostring(h:GetHealth()), tostring(h:GetMaxHealth()), h:IsDead() and " DEAD" or "")
    end)
    pcall(function()
        local c = a.Controller
        if c and c:IsValid() then
            local arch = c:GetArchEnemy()
            local who = "none"
            if arch and arch:IsValid() then who = (arch:GetAddress() == pawnAddr) and "ME" or arch:GetFName():ToString() end
            line = line .. "  hunting " .. who
            local forced = c:GetForcedEnemy()
            if forced and forced:IsValid() then line = line .. "  forced " .. forced:GetFName():ToString() end
        else
            line = line .. "  (no controller)"
        end
    end)
    pcall(function()
        local hidden = a.bHidden
        if hidden then line = line .. "  hidden" end
    end)
    P(line)
end

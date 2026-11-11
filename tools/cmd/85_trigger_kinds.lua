-- Which kinds of trigger are loaded, and what each is built on (the mod shares a trigger with the
-- other player or not by its family, see TRIGGER_SHARED in core.lua).
-- ipc\stage.txt: "list" (default), "light" (send the nearest light trigger as if the other
-- player had set it off: 0.22 must refuse it), "spent" (the same for a spent plain trigger,
-- which must still fire).
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "list"
if f then f:close() end
local pawn = getPawn()
local impl = SH2CoopMod.impl
if not (pawn and impl) then P("not in game") return end
local me = pawn:K2_GetActorLocation()
local function id(a)
    local s = a:GetFullName():match("^%S+%s+(.+)$") or ""
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) & 0xFFFFFFFF end
    return string.format("%08x", h)
end
local function dist(a)
    local l = a:K2_GetActorLocation()
    return math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2) / 100
end
local function chain(a)
    local names, cls = {}, a:GetClass()
    for _ = 1, 8 do
        if not (cls and cls:IsValid()) then break end
        local n = cls:GetFName():ToString()
        names[#names + 1] = n
        if n == "TriggerBase_BP_C" or n == "Actor" then break end
        local ok, up = pcall(function() return cls:GetSuperStruct() end)
        if not ok then names[#names + 1] = "(GetSuperStruct failed: " .. tostring(up) .. ")" break end
        cls = up
    end
    return table.concat(names, " < ")
end
P("mod:", tostring(impl.version))

if stage == "light" then
    local pick, best
    for _, t in ipairs(FindAllOf("TriggerLightWoodside_BP_C") or {}) do
        if t:IsValid() and (not best or dist(t) < best) then pick, best = t, dist(t) end
    end
    if not pick then P("no light trigger loaded here") return end
    P("light trigger:", pick:GetFName():ToString(), string.format("%.0f m away", best), " flashlight row:", tostring(pick["Flashlight Row Name"] and pick["Flashlight Row Name"]:ToString()))
    impl.debugEvent("trig " .. id(pick))
    P("sent it as the other player; see the log for what the mod did with it")
elseif stage == "spent" then
    local spent, best
    for _, t in ipairs(FindAllOf("TriggerBase_BP_C") or {}) do
        if t:IsValid() and t:GetClass():GetFName():ToString() == "TriggerBase_BP_C" then
            local once, enabled = false, true
            pcall(function() once, enabled = t.DoOnce, t.TriggerCurrentState end)
            if once and not enabled and (not best or dist(t) < best) then spent, best = t, dist(t) end
        end
    end
    if not spent then P("no spent plain trigger loaded") return end
    P("spent plain trigger:", spent:GetFName():ToString(), string.format("%.0f m away", best))
    impl.debugEvent("trig " .. id(spent))
    impl.debugEvent("trigx " .. id(spent))
    P("sent 'entered' and 'left' as the other player")
else
    local kinds = {}
    for _, family in ipairs({ "TriggerBase_BP_C", "OneShotEventController_BP_C" }) do
        for _, t in ipairs(FindAllOf(family) or {}) do
            if t:IsValid() then
                local c = chain(t)
                kinds[c] = (kinds[c] or 0) + 1
            end
        end
    end
    local list = {}
    for c, n in pairs(kinds) do list[#list + 1] = string.format("%4d  %s", n, c) end
    table.sort(list)
    for _, l in ipairs(list) do P(l) end
    P("the mod's verdict per kind so far:")
    for k, v in pairs(S.trigClass or {}) do P("   " .. k .. ": " .. (v and "shared" or "private")) end
end

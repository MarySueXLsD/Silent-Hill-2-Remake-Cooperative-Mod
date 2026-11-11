-- Feed the mod lines as if the other player had sent them, to exercise the 0.20 story and enemy
-- paths on one PC. ipc\stage.txt: "trigger" (a spent trigger: nothing in the story changes),
-- "drawer" (opens the nearest closed drawer or cupboard door), "message", "report".
local f = io.open("H:\\Projects\\Personal\\SH2CoopGhost\\SH2-CoopMod\\ipc\\stage.txt", "r")
local stage = f and (f:read("a") or ""):match("%a+") or "report"
if f then f:close() end
local pawn = getPawn()
local impl = SH2CoopMod.impl
if not (pawn and impl and impl.debugEvent) then P("not in game, or the mod has no debug entry") return end
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
P("mod:", impl.version, " story hooks:", tostring(S.storyHooks))

if stage == "trigger" then
    local spent, best
    for _, t in ipairs(FindAllOf("TriggerBase_BP_C") or {}) do
        if t:IsValid() then
            local once, enabled = false, true
            pcall(function() once, enabled = t.DoOnce, t.TriggerCurrentState end)
            if once and not enabled and (not best or dist(t) < best) then spent, best = t, dist(t) end
        end
    end
    if not spent then P("no spent trigger loaded") return end
    S.simTrigger = spent
    P("spent trigger:", spent:GetClass():GetFName():ToString(), spent:GetFName():ToString(), string.format("%.0fm", best), " entered:", tostring(spent.CharacterEntered))
    impl.debugEvent("trig " .. id(spent))
    impl.debugEvent("trigx " .. id(spent))
    P("sent 'entered' and 'left' as the other player; the mod applies them within a second")
elseif stage == "drawer" then
    local pick, best
    for _, a in ipairs(FindAllOf("GenericBase_BP_C") or {}) do
        if a:IsValid() then
            local cls = a:GetClass():GetFName():ToString()
            local opened = true
            pcall(function() opened = a.WasOpened end)
            if (cls:find("InteractiveDrawer") or cls:find("InteractiveKitchenDrawer") or cls:find("InteractiveDoor")) and opened == false and (not best or dist(a) < best) then
                pick, best = a, dist(a)
            end
        end
    end
    if not pick then P("no closed drawer or cupboard door loaded") return end
    S.simDrawer = pick
    P("closed:", pick:GetClass():GetFName():ToString(), string.format("%.0fm", best))
    impl.debugEvent("use " .. id(pick))
    P("sent 'used' as the other player")
elseif stage == "message" then
    impl.debugEvent("died")
    P("sent 'died' as the other player: the message shows, and three seconds later the game reloads its last save")
else
    if S.simTrigger and S.simTrigger:IsValid() then P("trigger now: entered =", tostring(S.simTrigger.CharacterEntered)) end
    if S.simDrawer and S.simDrawer:IsValid() then P("drawer now: opened =", tostring(S.simDrawer.WasOpened)) end
    P("pending from the other player: triggers", tostring(next(S.trigPending or {}) ~= nil), " uses", tostring(next(S.usePending or {}) ~= nil))
    P("restart pending:", tostring(S.restart ~= nil), " message showing:", tostring(S.msgUntil ~= nil))
    local w = {}
    for k in pairs(S.warned) do if k:find("story") or k:find("death") or k:find("restart") or k:find("enem") then w[#w + 1] = k end end
    P("warnings:", #w)
    for _, k in ipairs(w) do P("  " .. k:sub(1, 200)) end
end

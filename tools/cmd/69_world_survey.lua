-- Read-only survey for the story / death / enemy work: what exists in the running game right now.
local pawn = getPawn()
P("in game:", tostring(pawn ~= nil), " mod:", SH2CoopMod.impl and SH2CoopMod.impl.version, " role:", tostring(S.role),
    " other player here:", tostring(S.avatar ~= nil and S.avatar:IsValid()))
if not pawn then return end
local me = pawn:K2_GetActorLocation()
local function dist(a)
    local l = a:K2_GetActorLocation()
    return math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2) / 100
end

P("== health")
pcall(function() P("  value:", pawn.Health:GetHealthValue(), " state:", pawn.Health:GetHealthState(), " death blocked:", tostring(pawn.Health:IsDeathSequenceBlocked())) end)

P("== menus that can load a slot (MainMenuWidget and children)")
for _, w in ipairs(FindAllOf("MainMenuWidget") or {}) do
    if w:IsValid() then
        local vis = "?"
        pcall(function() vis = tostring(w:IsVisible()) end)
        P("  ", w:GetClass():GetFName():ToString(), " visible:", vis)
    end
end

P("== triggers")
local byClass, total = {}, 0
local sample
for _, t in ipairs(FindAllOf("TriggerBase_BP_C") or {}) do
    if t:IsValid() then
        total = total + 1
        local c = t:GetClass():GetFName():ToString()
        byClass[c] = (byClass[c] or 0) + 1
        sample = sample or t
    end
end
P("  total:", total)
for c, n in pairs(byClass) do P("    ", c, n) end
if sample then
    local base = sample:GetClass()
    for _ = 1, 6 do
        if base:GetFName():ToString() == "TriggerBase_BP_C" then break end
        base = base:GetSuperStruct()
    end
    P("  base class path:", base:GetFullName())
end
local shots = FindAllOf("OneShotEventController_BP_C") or {}
P("  one-shot event controllers:", #shots)
if shots[1] and shots[1]:IsValid() then P("  one-shot class path:", shots[1]:GetClass():GetFullName()) end

P("== enemies within 40 m")
for _, sp in ipairs(FindAllOf("SHAISpawner") or {}) do
    if sp:IsValid() then
        local a
        pcall(function() a = sp:GetSpawnedActor() end)
        if a and a:IsValid() and dist(a) < 40 then
            local t = string.format("  %4.0fm %s", dist(a), a:GetClass():GetFName():ToString())
            pcall(function() t = t .. string.format(" hp=%d dead=%s", math.floor(a.healthComponent:GetHealth()), tostring(a.healthComponent:IsDead())) end)
            pcall(function() t = t .. " active=" .. tostring(a:IsActive()) .. " knocked=" .. tostring(a:IsKnockedDown()) .. " hidden=" .. tostring(a.bHidden) end)
            pcall(function() t = t .. " deathAnim=" .. tostring(a.AnimComponent:IsInDeathState(true)) end)
            P(t)
        end
    end
end

P("== HUD widgets")
for _, name in ipairs({ "SHGameplayHudWidget", "SHGameplayGameOverWidget", "SHGameplayItemNotificationWidget", "SHGameplayTutorialWidget" }) do
    local n = 0
    for _, w in ipairs(FindAllOf(name) or {}) do if w:IsValid() then n = n + 1 end end
    P("  ", name, n)
end

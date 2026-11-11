-- Story triggers: can the mod (a) notice when the player walks into one and (b) make a trigger
-- fire as if the player had walked in? Tested on a trigger that has already fired (single-use and
-- switched off), so nothing in the story changes. Also finishes the enemy probe. Staged prints.
local pawn = getPawn()
if not pawn then P("not in game") return end
local me = pawn:K2_GetActorLocation()
local FN = "BndEvt__Box_K2Node_ComponentBoundEvent_0_ComponentBeginOverlapSignature__DelegateSignature"
local PATH = "/Game/Game/Gameplay/Triggers/TriggerBase_BP.TriggerBase_BP_C:" .. FN

P("1 hook the triggers' own 'something entered my box' handler")
if S.probeTrigHook == nil then
    S.probeTrigSeen = 0
    local ok, err = pcall(RegisterHook, PATH, function(self, comp, other)
        S.probeTrigSeen = (S.probeTrigSeen or 0) + 1
        pcall(function()
            local t, o = self:get(), other:get()
            S.probeTrigLast = t:GetFName():ToString() .. " <- " .. ((o and o:IsValid()) and o:GetFName():ToString() or "?")
        end)
    end)
    S.probeTrigHook = ok
    P("   ", tostring(ok), tostring(err))
else
    P("    already hooked:", tostring(S.probeTrigHook), " calls seen so far:", tostring(S.probeTrigSeen), " last:", tostring(S.probeTrigLast))
end

P("2 pick a spent trigger (single-use, switched off)")
local spent, best
for _, t in ipairs(FindAllOf("TriggerBase_BP_C") or {}) do
    if t:IsValid() then
        local once, enabled = false, true
        pcall(function() once, enabled = t.DoOnce, t.TriggerCurrentState end)
        local l = t:K2_GetActorLocation()
        local d = math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2)
        if once and not enabled and (not best or d < best) then spent, best = t, d end
    end
end
if not spent then P("    none loaded") return end
local function state() return string.format("once=%s enabled=%s entered=%s", tostring(spent.DoOnce), tostring(spent.TriggerCurrentState), tostring(spent.CharacterEntered)) end
P("   ", spent:GetClass():GetFName():ToString(), spent:GetFName():ToString(), string.format("%.0fm", best / 100), state())

P("3 call its handler with our player as the one who entered")
local before = S.probeTrigSeen or 0
local ok, err = pcall(function() spent[FN](spent, spent.Box, pawn, pawn.CapsuleComponent, 0, false, {}) end)
P("   ", tostring(ok), tostring(err))
P("    after:", state(), " hook saw the call:", tostring((S.probeTrigSeen or 0) > before), " last:", tostring(S.probeTrigLast))
P("done")

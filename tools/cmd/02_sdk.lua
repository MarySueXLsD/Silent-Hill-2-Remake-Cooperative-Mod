for _, n in ipairs({ "GenerateSDK", "GenerateUHTCompatibleHeaders", "GenerateLuaTypes", "DumpAllObjects", "DumpAllActors", "DumpUSMAP", "ForEachUObject", "LoadAsset", "StaticConstructObject", "NotifyOnNewObject", "RegisterHook" }) do
    P(n, type(_G[n]))
end

local function listComps(actor, label)
    P("--- " .. label .. " components ---")
    local acClass = StaticFindObject("/Script/Engine.ActorComponent")
    local comps = actor:K2_GetComponentsByClass(acClass)
    comps:ForEach(function(i, e)
        local c = e:get()
        if c and c:IsValid() then
            P("  " .. c:GetClass():GetFName():ToString() .. "   " .. c:GetFName():ToString())
        end
    end)
end

local pc = UEHelpers.GetPlayerController()
local ok, err = pcall(listComps, pc.Pawn, "pawn")
if not ok then P("comp list failed: " .. tostring(err)) end
ok, err = pcall(listComps, pc, "controller")
if not ok then P("comp list failed: " .. tostring(err)) end

if type(GenerateSDK) == "function" then
    local ok2, e2 = pcall(GenerateSDK)
    P("GenerateSDK:", ok2, e2)
end

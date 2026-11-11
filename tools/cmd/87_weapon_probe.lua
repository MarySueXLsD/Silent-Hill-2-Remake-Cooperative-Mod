-- Read-only: the player's firearms and the game objects a shot goes through, to see what the mod
-- can listen to for "a shot was fired" and what it can show at the other player's gun.
local pawn = getPawn()
if not pawn then P("not in game") return end
local function cls(o) return o:GetClass():GetFName():ToString() end
local combat = pawn.Combat
P("combat component:", combat and combat:IsValid() and cls(combat) or "none")
local ranged
pcall(function() ranged = combat:FindSubcomponentByClass(StaticFindObject("/Script/SHProto.SHRangedCmbSubcomp")) end)
P("ranged subcomponent:", ranged and ranged:IsValid() and ranged:GetFullName():sub(1, 110) or "not found this way")
if not (ranged and ranged:IsValid()) then
    for _, r in ipairs(FindAllOf("SHRangedCmbSubcomp") or {}) do
        if r:IsValid() then ranged = r P("   found by search:", r:GetFullName():sub(1, 110)) end
    end
end
if ranged and ranged:IsValid() then
    pcall(function()
        local n = 0
        ranged.WeaponsAmmoCounts:ForEach(function(k, v) n = n + 1 P("   in the clip:", k:get():ToString(), tostring(v:get())) end)
        if n == 0 then P("   no clip counts yet") end
    end)
    pcall(function() P("   listeners for a successful shot:", #ranged.OnRangedFireSuccess:GetBindings()) end)
    pcall(function()
        for _, b in ipairs(ranged.OnRangedFireSuccess:GetBindings()) do
            P("      ", b.Object and b.Object:IsValid() and cls(b.Object) or "?", b.FunctionName:ToString())
        end
    end)
end
for _, w in ipairs(FindAllOf("SHItemWeaponRanged") or {}) do
    if w:IsValid() then
        local mine = false
        pcall(function() mine = w.OwnerCharacter:GetAddress() == pawn:GetAddress() end)
        P("firearm:", cls(w), mine and "(ours)" or "(not ours)", " hidden:", tostring(w.bHidden), " clip size:", tostring(w.WeaponClipSize))
        pcall(function() P("   shot sound:", w.WeaponItemAudioComponent.ShootAudioEvent:GetFullName()) end)
        pcall(function()
            local fp = w.RegisteredFirePoint
            if fp and fp:IsValid() then
                local l = fp.RelativeLocation
                P("   fire point:", cls(fp), fp:GetFName():ToString(), " attached to socket:", fp:GetAttachSocketName():ToString(),
                    string.format(" rel %.1f %.1f %.1f", l.X, l.Y, l.Z))
            end
        end)
        pcall(function()
            local names = {}
            w:GetClass():ForEachProperty(function(p)
                local n = p:GetFName():ToString()
                local c = p:GetClass():GetFName():ToString()
                if n:find("FX") or n:find("Flash") or n:find("Muzzle") or n:find("Niagara") or n:find("Particle") or n:find("Effect") or n:find("Light") then
                    names[#names + 1] = n .. ":" .. c
                end
            end)
            P("   effect-like properties on its own class:", table.concat(names, ", "))
        end)
        pcall(function()
            local comps = {}
            for _, c in ipairs(w:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent")) or {}) do
                comps[#comps + 1] = cls(c) .. " " .. c:GetFName():ToString()
            end
            P("   components:", table.concat(comps, " | "):sub(1, 600))
        end)
    end
end
P("shot hook:", tostring(S.shotHook), " last shot sent:", S.lastShotSent and string.format("%.0f s ago", os.clock() - S.lastShotSent) or "never")

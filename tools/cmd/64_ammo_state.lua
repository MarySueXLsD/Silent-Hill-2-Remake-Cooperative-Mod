-- Unlimited ammo: is it on, which kinds of ammunition are known, how much of each is held.
local pawn = getPawn()
if not pawn then P("not in game") return end
P("mod:", SH2CoopMod.impl and SH2CoopMod.impl.version, " option here:", tostring(cfg and cfg.unlimited_ammo), " running:", tostring(S.ammoWasOn == true))
local names = {}
for n in pairs(S.ammoNames or {}) do names[#names + 1] = n end
P("ammunition kinds known:", #names)
local held = {}
pawn.Items.CollectedItems:ForEach(function(_, e)
    local d = e:get()
    held[d.ItemRowName:ToString()] = d.Quantity
end)
for _, n in ipairs(names) do P("  ", n, "held:", tostring(held[n] or 0)) end
local w = {}
for k in pairs(S.warned) do if k:find("ammo") then w[#w + 1] = k end end
P("ammo warnings:", #w)
for _, k in ipairs(w) do P("  " .. k:sub(1, 160)) end

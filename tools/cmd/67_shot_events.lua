-- Read-only: which gunshot audio events are in memory right now, and which firearm classes exist.
local all = FindAllOf("AkAudioEvent") or {}
local hits = {}
for i = 1, #all do
    local e = all[i]
    if e:IsValid() then
        local n = e:GetFName():ToString()
        local l = n:lower()
        if l:find("shoot") or l:find("shot") or l:find("fire") or l:find("gun") or l:find("pistol") or l:find("rifle") then
            hits[#hits + 1] = n
        end
    end
end
table.sort(hits)
P("audio events in memory:", #all, " gun-like:", #hits)
for i = 1, math.min(#hits, 40) do P("  ", hits[i]) end
local guns = FindAllOf("SHItemWeaponRanged") or {}
P("firearm actors:", #guns)
local items = FindAllOf("SHItemWeapon") or {}
P("weapon actors of any kind:", #items)
for i = 1, math.min(#items, 8) do if items[i]:IsValid() then P("  ", items[i]:GetClass():GetFName():ToString()) end end

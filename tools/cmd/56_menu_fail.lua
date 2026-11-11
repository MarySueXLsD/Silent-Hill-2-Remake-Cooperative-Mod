-- Press the Join co-op entry (fires its click event) without printing much; used to test the
-- failure path, where the launcher answers with an error.
local btn = S.menuBtn
if not (btn and btn:IsValid()) then P("no entry") return end
P("before: label", tostring(S.menuLabel), "enabled", tostring(S.menuEnabled))
local ok, err = pcall(function() btn.OnClicked:Broadcast() end)
P("click fired:", tostring(ok), tostring(err), " seen:", tostring(S.menuClicked))

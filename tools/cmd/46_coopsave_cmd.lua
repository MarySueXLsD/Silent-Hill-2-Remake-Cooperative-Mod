-- Report whether the save-on-request round trip happened (run after dropping command.txt = coopsave).
local dir = os.getenv("LOCALAPPDATA") .. "\\SilentHill2\\Saved\\SaveGames\\76561197960271872\\"
local f = io.open(dir .. "SaveGameData_9.sav", "rb")
P("slot 9 size:", f and f:seek("end") or "missing")
if f then f:close() end
P("in game:", tostring(getPawn() ~= nil), " role:", S.role)
local warned = {}
for k in pairs(S.warned) do warned[#warned + 1] = k end
P("warnings:", #warned)
for _, k in ipairs(warned) do P("  " .. k:sub(1, 110)) end

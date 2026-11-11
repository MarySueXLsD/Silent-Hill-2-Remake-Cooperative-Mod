-- State of the puzzle sync.
local tracked, solved, settling = 0, 0, 0
local now = os.clock()
for id, v in pairs(S.puzzleState) do
    tracked = tracked + 1
    if v then solved = solved + 1 end
    if S.puzzleSince and S.puzzleSince[id] and now - S.puzzleSince[id] < 6 then settling = settling + 1 end
end
local waiting = 0
for _ in pairs(S.solvedRemote) do waiting = waiting + 1 end
P("puzzles tracked", tracked, " solved", solved, " still settling", settling, " waiting to be solved here", waiting)
P("sync_puzzles", S.cfg.sync_puzzles, " mirror", tostring(S.mirror), " outbox", #S.outbox)
local warned = {}
for k in pairs(S.warned) do if k:find("puzzle") then warned[#warned + 1] = k end end
P("puzzle warnings:", #warned)
for _, k in ipairs(warned) do P("  " .. k) end

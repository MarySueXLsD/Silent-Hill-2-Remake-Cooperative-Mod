-- SH2-CoopMod bootstrap.
-- Stays tiny and stable. The actual mod lives in core.lua, which this file loads and then
-- reloads automatically whenever core.lua changes on disk (no game restart needed).
--
-- Keys:  F9 = solo mirror test (second James follows you)

local UEHelpers = require("UEHelpers")

SH2CoopMod = SH2CoopMod or {}          -- global on purpose: survives core reloads
SH2CoopMod.state = SH2CoopMod.state or {}

local function modRoot()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]*$")
end
local ROOT = modRoot()
local CORE = ROOT .. "\\Scripts\\core.lua"

local function log(s) print("[SH2-CoopMod] " .. tostring(s) .. "\n") end

local loadedSrc = nil
local function loadCore()
    local f = io.open(CORE, "r")
    if not f then return end
    local src = f:read("a")
    f:close()
    if not src or src == "" or src == loadedSrc then return end
    loadedSrc = src
    local chunk, err = load(src, "@core.lua")
    if not chunk then log("core.lua does not compile: " .. tostring(err)) return end
    if SH2CoopMod.impl and SH2CoopMod.impl.shutdown then pcall(SH2CoopMod.impl.shutdown) end
    local ok, impl = pcall(chunk, { root = ROOT, UEHelpers = UEHelpers, log = log })
    if ok and type(impl) == "table" then
        SH2CoopMod.impl = impl
        log("core loaded (" .. tostring(impl.version) .. ")")
    else
        log("core.lua failed to start: " .. tostring(impl))
    end
end

local busy = false
local n = 0
LoopAsync(33, function()
    if busy then return false end
    busy = true
    ExecuteInGameThread(function()
        n = n + 1
        if n % 30 == 1 then pcall(loadCore) end
        local impl = SH2CoopMod.impl
        if impl and impl.tick then
            local ok, err = pcall(impl.tick)
            if not ok and SH2CoopMod.lastTickError ~= err then
                SH2CoopMod.lastTickError = err
                log("tick error: " .. tostring(err))
            end
        end
        busy = false
    end)
    return false
end)

RegisterKeyBind(Key.F9, function()
    local impl = SH2CoopMod.impl
    if impl and impl.onKey then pcall(impl.onKey, "F9") end
end)

log("bootstrap loaded from " .. tostring(ROOT))

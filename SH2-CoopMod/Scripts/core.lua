-- SH2-CoopMod core - co-op for a single-player game.
-- Loaded (and hot-reloaded on change) by main.lua. Returns a table of entry points.
--
-- Each player runs their own copy of the game. This mod keeps the two copies in agreement by
-- exchanging messages with the other PC. Lua here has no sockets, so the mod talks to relay.ps1
-- through small files in <this mod>\ipc:
--   out.txt   what we send: one state line plus pose, held items and unacknowledged events
--   in.txt    what the other player sent, written by relay.ps1
--   role.txt  "host" or "join", written by relay.ps1 (the host's world is the authority)
--
-- Wire format (text, one message per line):
--   S <session> <seq> <x> <y> <z> <yaw> <speed> <ack> <role> <ms>   state, ~30x a second, lossy
--   P <103 integers>                 pelvis position + one quaternion per streamed bone
--   H <item> <item> ...              what the player holds/wears: kind|asset|socket|loc|rot
--   E <id> inv <item> <delta>        reliable: inventory changed
--   E <id> invfull <item>=<qty>,...  reliable: host's whole inventory
-- Events are resent until the other side acknowledges their id in its state line.
--
-- Two loops: tick() runs ~30x a second (measure ourselves, exchange messages, inventory);
-- frame() runs every rendered frame and draws the other player by interpolating between the
-- two most recent snapshots, slightly in the past, so motion is smooth at any frame rate.
--
-- Health is deliberately not synced. Map and item-inspection screens are local by nature.

local ctx = ...
local UEHelpers = ctx.UEHelpers
local log = ctx.log
local VERSION = "0.17"

local DIR = ctx.root .. "\\ipc"
local OUT_FILE = DIR .. "\\out.txt"
local IN_FILE = DIR .. "\\in.txt"
local ROLE_FILE = DIR .. "\\role.txt"
local CMD_FILE = DIR .. "\\run.lua"
local RES_FILE = DIR .. "\\result.txt"

local SNAP_DISTANCE = 1500   -- teleport the avatar instead of gliding when further than this
local INTERP_DELAY = 0.10    -- seconds in the past the other player is drawn (hides jitter)
local MAX_SNAPS = 8
local INVENTORY_EVERY = 6    -- ticks between inventory checks (~200 ms)
local HELD_EVERY = 10        -- ticks between checks of what we are holding (~330 ms)
local MIRROR_OFFSET = 150    -- solo test: the copy stands this far to the side

-- Everything that must survive a hot reload lives in S.
local S = SH2CoopMod.state
if not S.session then
    math.randomseed(os.time())
    S.session = string.format("%06x", math.random(0, 0xFFFFFF))
    S.seq = 0
    S.tickCount = 0
    S.role = "host"
    S.mirror = false
    S.outbox = {}        -- reliable events not yet acknowledged: { id = n, text = "inv X 1" }
    S.nextEventId = 1
    S.known = nil        -- item name -> quantity both sides are believed to agree on
    S.peer = { session = nil, lastSeq = nil, lastTime = 0, connected = false, applied = 0 }
    S.warned = {}
end
S.snaps = S.snaps or {}      -- recent snapshots of the other player, oldest first
S.gen = (S.gen or 0) + 1     -- bumped on every reload; older frame loops see it and stop
local myGen = S.gen
local peer = S.peer

local function warnOnce(key, msg)
    if not S.warned[key] then S.warned[key] = true log(msg) end
end

-- ================================================================ settings
-- <this mod>\config.txt, one key=value per line, written by the launcher. Re-read about once a
-- second, so changes apply while the game runs.

local CONFIG_FILE = ctx.root .. "\\config.txt"
local DEFAULTS = {
    share_inventory = "1",      -- pickups and item use are shared between the players
    host_inventory_wins = "1",  -- on connect the host's inventory replaces the joiner's
    show_held_items = "1",      -- show the other player's weapon / flashlight / radio
    sync_flashlight = "1",      -- the other player's flashlight lights up your world too
    flashlight_shadows = "0",   -- their beam casts shadows (costs performance)
    share_ammo = "1",           -- within shared inventory: ammunition
    share_healing = "1",        --   health drinks, syringes, ampoules
    share_documents = "1",      --   maps, notes, memos, photos
    share_key_items = "1",      --   weapons, keys, puzzle pieces, everything else
    sync_doors = "1",           -- doors open, close and unlock for both players
    sync_cutscenes = "1",       -- both watch each cutscene together, then regroup at the host
    sync_enemies = "1",         -- enemies share health and targets, and follow the host's positions
    sync_puzzles = "1",         -- a puzzle solved by one player is solved for both
    sync_pushables = "1",       -- furniture one player pushes moves for both
    sync_saves = "1",           -- the joiner saves when the host saves, and loads when the host loads
    other_player_collision = "0", -- the other player's body blocks me (and enemies)
    friendly_fire = "0",        -- my attacks hurt the other player (both must enable it)
    ff_hit_damage = "10",       -- health lost per melee hit, my estimate of one enemy hit; a shot is double
    show_other_player = "1",    -- draw the other player at all
    other_player_scale = "100", -- their size on my screen, percent
    flashlight_brightness = "100", -- brightness of their beam on my screen, percent
    send_rate_hz = "30",        -- how often my position and pose are sent
    peer_timeout_s = "3",       -- seconds without news before the other player is hidden
    interp_delay_ms = "100",    -- how far in the past the other player is drawn
    my_model = "james",         -- how the other player sees me
    show_my_model_to_me = "1",  -- ...and whether I see myself as that model too
    other_model = "auto",       -- how I see the other player; auto = what they chose
    player_name = "Player",
}
-- Character models that exist in the game's own files.
local MODELS = {
    james = "/Game/Game/Characters/Humans/JamesSunderland/Mesh/JamesSunderland_2022_08_29.JamesSunderland_2022_08_29",
    maria = "/Game/Game/Characters/Humans/Maria/Meshes/Maria.Maria",
    angela = "/Game/Game/Characters/Humans/Angela/Meshes/Angela_rig.Angela_rig",
    mary = "/Game/Game/Characters/Humans/Mary/Meshes/Mary_SkeletalMesh.Mary_SkeletalMesh",
}

S.cfg = S.cfg or {}
for k, v in pairs(DEFAULTS) do if S.cfg[k] == nil then S.cfg[k] = v end end
local cfg = S.cfg
local function on(key) return cfg[key] == "1" end

local function readConfig()
    local f = io.open(CONFIG_FILE, "r")
    if not f then return end
    local text = f:read("a")
    f:close()
    if text == S.cfgText then return end
    S.cfgText = text
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
    for line in text:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k and DEFAULTS[k] ~= nil and v ~= "" then cfg[k] = v end
    end
    log("settings loaded")
end

local function enqueue(text)
    -- With nobody connected there is no one to acknowledge events; keep only the recent ones.
    if not peer.connected then
        while #S.outbox >= 64 do table.remove(S.outbox, 1) end
    end
    S.outbox[#S.outbox + 1] = { id = S.nextEventId, text = text }
    S.nextEventId = S.nextEventId + 1
end

local getPC = rawget(_G, "SH2CoopMod_GetPC") or UEHelpers.GetPlayerController
local function getPawn()
    local pc = getPC()
    if not pc or not pc:IsValid() then return nil end
    local pawn = pc.Pawn
    if not pawn or not pawn:IsValid() then return nil end
    return pawn
end

local function lerpAngle(a, b, t)
    local d = (b - a) % 360
    if d > 180 then d = d - 360 end
    return a + d * t
end

local IDENT = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }

-- ================================================================ inventory (shared)

local function readInventory(pawn)
    local items = pawn.Items
    if not items or not items:IsValid() then return nil end
    local m = {}
    items.CollectedItems:ForEach(function(_, e)
        local d = e:get()
        local name = d.ItemRowName:ToString()
        m[name] = (m[name] or 0) + d.Quantity
    end)
    return m
end

local function applyItemDelta(pawn, name, delta)
    if delta == 0 then return end
    local items = pawn.Items
    if delta > 0 then
        items:CollectItem(FName(name), delta, false)
    else
        items:RemoveItem(FName(name), -delta, false)
    end
end

-- Which kinds of item are shared is a setting. Kinds are told apart by the item's internal name.
local function itemShared(name)
    local n = name:lower()
    if n:find("ammo") then return on("share_ammo") end
    if n:find("healthdrink") or n:find("syringe") or n:find("ampoule") then return on("share_healing") end
    if n:find("map") or n:find("note") or n:find("memo") or n:find("letter") or n:find("photo") or n:find("reflections") then
        return on("share_documents")
    end
    return on("share_key_items")   -- weapons, keys, puzzle pieces, everything else
end

-- Compare the real inventory with S.known and queue an event for every difference.
local function pollInventory(pawn)
    local cur = readInventory(pawn)
    if not cur then return end
    if not S.known then S.known = cur return end
    for name, qty in pairs(cur) do
        local d = qty - (S.known[name] or 0)
        if d ~= 0 and itemShared(name) then enqueue(string.format("inv %s %d", name, d)) end
    end
    for name, qty in pairs(S.known) do
        if cur[name] == nil and qty ~= 0 and itemShared(name) then
            enqueue(string.format("inv %s %d", name, -qty))
        end
    end
    S.known = cur
end

local function sendFullInventory(pawn)
    local cur = readInventory(pawn)
    if not cur then return end
    S.known = cur
    local parts = {}
    for name, qty in pairs(cur) do parts[#parts + 1] = name .. "=" .. qty end
    enqueue("invfull " .. table.concat(parts, ","))
    log("sent full inventory (" .. #parts .. " items)")
end

local function onRemoteInv(pawn, name, delta)
    if not itemShared(name) then return end
    -- Queue our own pending changes first so they are not swallowed by the merge.
    pollInventory(pawn)
    applyItemDelta(pawn, name, delta)
    S.known = S.known or {}
    local v = (S.known[name] or 0) + delta
    S.known[name] = (v > 0) and v or nil
    log(string.format("inventory from peer: %s %+d", name, delta))
end

local function onRemoteInvFull(pawn, list)
    local full = {}
    for name, qty in list:gmatch("([^,=]+)=(%-?%d+)") do full[name] = tonumber(qty) end
    local cur = readInventory(pawn) or {}
    local changed = 0
    for name, qty in pairs(full) do
        local d = qty - (cur[name] or 0)
        if d ~= 0 and itemShared(name) then applyItemDelta(pawn, name, d) changed = changed + 1 end
    end
    for name, qty in pairs(cur) do
        if full[name] == nil and itemShared(name) then applyItemDelta(pawn, name, -qty) changed = changed + 1 end
    end
    S.known = readInventory(pawn) or full
    log("inventory replaced with host's (" .. changed .. " differences)")
end

local onRemoteLock, onRemoteFriendlyFire, onRemoteCutscene, onRemoteTook, onRemoteEnemyDamage, onRemoteSolved, onRemotePush   -- defined further down
local onRemoteSaved, onRemoteLoaded, onRemoteEnemyDead

local function handleEvent(pawn, text)
    local kind, rest = text:match("^(%S+)%s*(.*)$")
    if kind == "saved" then
        onRemoteSaved(pawn, tonumber(rest:match("^(%-?%d+)$")) or -1)
        return
    elseif kind == "loaded" then
        onRemoteLoaded(pawn)
        return
    elseif kind == "push" then
        local id, x, y, z = rest:match("^(%x+) (%-?%d+) (%-?%d+) (%-?%d+)$")
        if id and on("sync_pushables") then onRemotePush(id, tonumber(x), tonumber(y), tonumber(z)) end
        return
    elseif kind == "solved" then
        local id = rest:match("^(%x+)$")
        if id and on("sync_puzzles") then onRemoteSolved(id) end
        return
    elseif kind == "edead" then
        local id = rest:match("^(%x+)$")
        if id then onRemoteEnemyDead(id) end
        return
    elseif kind == "edmg" then
        local id, amount = rest:match("^(%x+) (%d+)$")
        if id then onRemoteEnemyDamage(pawn, id, tonumber(amount)) end
        return
    elseif kind == "cut" then
        local id, x, y, z, yaw = rest:match("^(%x+) (%-?%d+) (%-?%d+) (%-?%d+) (%-?%d+)$")
        if id then onRemoteCutscene(id, tonumber(x), tonumber(y), tonumber(z), tonumber(yaw)) end
        return
    elseif kind == "took" then
        local id = rest:match("^(%x+)$")
        if id and on("share_inventory") then onRemoteTook(id) end
        return
    elseif kind == "lock" then
        local id, v = rest:match("^(%x+) (%d)$")
        if id then onRemoteLock(id, v == "1") end
        return
    elseif kind == "ff" then
        local how, amount, dx, dy = rest:match("^(%a+) (%d+) (%-?%d+) (%-?%d+)$")
        if how then onRemoteFriendlyFire(pawn, how, tonumber(amount), tonumber(dx) / 100, tonumber(dy) / 100) end
        return
    end
    if (kind == "inv" or kind == "invfull") and not on("share_inventory") then
        return   -- acknowledged but ignored: this player keeps a separate inventory
    end
    if kind == "inv" then
        local name, delta = rest:match("^(%S+) (%-?%d+)$")
        if name then onRemoteInv(pawn, name, tonumber(delta)) end
    elseif kind == "invfull" then
        onRemoteInvFull(pawn, rest)
    else
        warnOnce("ev:" .. tostring(kind), "unknown event from peer: " .. tostring(kind))
    end
end

-- ================================================================ pose capture

-- The other player's body is a plain actor with a PoseableMeshComponent using James's mesh.
-- No animation blueprint runs on it: we set its main bones to the rotations the other player's
-- game measured on their real James, so whatever they do (walk, aim, swing, climb) shows here.

-- Bones we stream, parents before children. Fingers, face, cloth and twist bones are left in
-- their rest pose relative to these.
local BONE_NAMES = {
    "pelvis_bn", "spine_01_bn", "spine_02_bn", "spine_03_bn", "spine_04_bn", "spine_05_bn",
    "neck_01_bn", "neck_02_bn", "head_bn",
    "clavicle_01_r_bn", "upperarm_r_bn", "lowerarm_r_bn", "hand_r_bn", "hand_r_socket",
    "clavicle_01_l_bn", "upperarm_l_bn", "lowerarm_l_bn", "hand_l_bn", "hand_l_socket",
    "thigh_l_bn", "calf_l_bn", "foot_l_bn", "ball_l_bn",
    "thigh_r_bn", "calf_r_bn", "foot_r_bn", "ball_r_bn",
}
local BONES = {}
for i, n in ipairs(BONE_NAMES) do BONES[i] = FName(n) end
-- A pose is: pelvis position (tenths), then X Y Z W per bone (thousandths).

-- For our own on-screen model nothing goes over the network, so fingers are included too.
local SELF_BONES = {}
for i = 1, #BONES do SELF_BONES[i] = BONES[i] end
for _, side in ipairs({ "r", "l" }) do
    for _, finger in ipairs({ "thumb", "index", "middle", "ring", "pinky" }) do
        for n = 1, 3 do
            SELF_BONES[#SELF_BONES + 1] = FName(string.format("%s_0%d_%s_bn", finger, n, side))
        end
    end
end

local RAD = 180 / math.pi
local function normAxis(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end
-- Same convention as the engine's quaternion-to-rotator conversion.
local function quatToRot(X, Y, Z, W)
    local st = Z * X - W * Y
    local yaw = math.atan(2 * (W * Z + X * Y), 1 - 2 * (Y * Y + Z * Z)) * RAD
    if st < -0.4999995 then
        return -90, yaw, normAxis(-yaw - 2 * math.atan(X, W) * RAD)
    elseif st > 0.4999995 then
        return 90, yaw, normAxis(yaw - 2 * math.atan(X, W) * RAD)
    end
    return math.asin(2 * st) * RAD, yaw, math.atan(-2 * (W * X + Y * Z), 1 - 2 * (X * X + Y * Y)) * RAD
end

local function round(v) return math.floor(v + 0.5) end

-- Measure our own James: a flat array of integers. `bones` defaults to the networked set.
local function capturePose(pawn, bones)
    bones = bones or BONES
    local mesh = pawn.Mesh
    local pose = {}
    for i = 1, #bones do
        local t = mesh:GetSocketTransform(bones[i], 2)   -- 2 = component space
        if i == 1 then
            local p = t.Translation
            pose[1], pose[2], pose[3] = round(p.X * 10), round(p.Y * 10), round(p.Z * 10)
        end
        local q = t.Rotation
        local k = 4 * i - 1
        pose[k + 1], pose[k + 2], pose[k + 3], pose[k + 4] =
            round(q.X * 1000), round(q.Y * 1000), round(q.Z * 1000), round(q.W * 1000)
    end
    return pose
end

-- Set the avatar's bones to a blend of two captured poses (alpha 0 = a, 1 = b).
local function applyPose(comp, a, b, alpha, scale, bones)
    bones = bones or BONES
    local need = 3 + 4 * #bones
    if #a < need or #b < need then return end
    local BONES = bones
    local inv = 1 - alpha
    local ps = (scale or 1) / 10   -- shorter or taller models keep their feet on the floor
    comp:SetBoneLocationByName(BONES[1], {
        X = (a[1] * inv + b[1] * alpha) * ps,
        Y = (a[2] * inv + b[2] * alpha) * ps,
        Z = (a[3] * inv + b[3] * alpha) * ps,
    }, 1)
    for i = 1, #BONES do
        local k = 4 * i - 1
        local ax, ay, az, aw = a[k + 1], a[k + 2], a[k + 3], a[k + 4]
        local bx, by, bz, bw = b[k + 1], b[k + 2], b[k + 3], b[k + 4]
        -- q and -q are the same rotation; blend along the short way round
        if ax * bx + ay * by + az * bz + aw * bw < 0 then bx, by, bz, bw = -bx, -by, -bz, -bw end
        local x, y, z, w = ax * inv + bx * alpha, ay * inv + by * alpha, az * inv + bz * alpha, aw * inv + bw * alpha
        local len = math.sqrt(x * x + y * y + z * z + w * w)
        if len > 0 then
            local pitch, yaw, roll = quatToRot(x / len, y / len, z / len, w / len)
            comp:SetBoneRotationByName(BONES[i], { Pitch = pitch, Yaw = yaw, Roll = roll }, 1) -- 1 = component space
        end
    end
end

-- ================================================================ held items

-- Things attached to our James's body: the equipped weapon, flashlight, radio.
-- Returned as one string; each item is kind|asset path|socket|x,y,z|pitch,yaw,roll.
local function collectHeld(pawn)
    local parts = {}
    local bodyAddr = pawn.Mesh:GetAddress()
    local pawnAddr = pawn:GetAddress()

    local function add(a)
        if not a or not a:IsValid() or a.bHidden then return end
        local root = a.RootComponent
        if not root or not root:IsValid() then return end
        local parent = root.AttachParent
        if not parent or not parent:IsValid() or parent:GetAddress() ~= bodyAddr then return end
        local mesh = a.Mesh
        if not mesh or not mesh:IsValid() or not mesh:IsVisible() then return end

        local kind, asset
        if mesh:GetClass():GetFName():ToString():find("Static") then
            kind, asset = "S", mesh.StaticMesh
        else
            kind = "K"
            local ok, sk = pcall(function() return mesh.SkeletalMesh end)
            asset = ok and sk or nil
        end
        if not asset or not asset:IsValid() then return end
        local path = asset:GetFullName():match("^%S+%s+(%S+)$")
        if not path then return end

        local l, r = root.RelativeLocation, root.RelativeRotation
        parts[#parts + 1] = string.format("%s|%s|%s|%.2f,%.2f,%.2f|%.1f,%.1f,%.1f",
            kind, path, root:GetAttachSocketName():ToString(), l.X, l.Y, l.Z, r.Pitch, r.Yaw, r.Roll)
    end

    pawn.Items.EquipmentActors:ForEach(function(_, e) add(e:get()) end)
    local weapons = FindAllOf("SHItemWeapon")
    if weapons then
        for i = 1, #weapons do
            local w = weapons[i]
            if w:IsValid() then
                local owner = w.OwnerCharacter
                if owner and owner:IsValid() and owner:GetAddress() == pawnAddr then add(w) end
            end
        end
    end
    table.sort(parts)
    return table.concat(parts, " ")
end

local function clearHeld()
    for _, c in ipairs(S.heldComps or {}) do
        if c:IsValid() then pcall(function() c:K2_DestroyComponent(c) end) end
    end
    S.heldComps = {}
    S.heldApplied = nil
end

local function findAsset(path)
    local a = StaticFindObject(path)
    if a and a:IsValid() then return a end
    pcall(LoadAsset, path)
    a = StaticFindObject(path)
    if a and a:IsValid() then return a end
    return nil
end

-- Where to attach something that sits on James's `socket`, on whatever body `comp` has.
-- Returns the name to attach to and, when that body lacks the socket, the socket's offset from
-- the bone it hangs on (measured on our own James) so the spot can be reproduced by hand.
-- Returns nil when the body has neither.
local function attachPoint(pawn, comp, socket)
    local name = FName(socket)
    if comp:DoesSocketExist(name) then return name, nil end
    local mesh = pawn.Mesh
    local bone = mesh:GetSocketBoneName(name)
    if bone:ToString() == socket then bone = mesh:GetParentBone(name) end   -- it was a bone itself
    if comp:GetBoneIndex(bone) < 0 then return nil end
    return bone, mesh:GetSocketTransform(name, 3)   -- 3 = relative to its parent bone
end

local function placeAttached(child, parentComp, name, rel, scale)
    child:K2_AttachToComponent(parentComp, name, 2, 2, 2, false)   -- 2 = snap to target
    if rel then
        local p, q = rel.Translation, rel.Rotation
        local pitch, yaw, roll = quatToRot(q.X, q.Y, q.Z, q.W)
        child:K2_SetRelativeLocationAndRotation(
            { X = p.X * scale, Y = p.Y * scale, Z = p.Z * scale },
            { Pitch = pitch, Yaw = yaw, Roll = roll }, false, {}, true)
    end
end

-- Make the avatar hold exactly what `desc` lists.
local function applyHeld(desc)
    if desc == S.heldApplied then return end
    clearHeld()
    S.heldApplied = desc
    if not (S.avatar and S.avatar:IsValid() and S.avatarComp and S.avatarComp:IsValid()) then return end

    local staticCls = StaticFindObject("/Script/Engine.StaticMeshComponent")
    local skelCls = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    for entry in desc:gmatch("%S+") do
        local kind, path, socket, lx, ly, lz, rp, ry, rr =
            entry:match("^(%a)|([^|]+)|([^|]*)|([^,]+),([^,]+),([^|]+)|([^,]+),([^,]+),(.+)$")
        local asset = kind and findAsset(path)
        local pawn = getPawn()
        local attachName, rel
        if asset and pawn then attachName, rel = attachPoint(pawn, S.avatarComp, socket) end
        if asset and not attachName then
            -- this body has nowhere comparable to put it: leave it out
        elseif not asset then
            warnOnce("held:" .. tostring(path), "cannot show held item, asset not available: " .. tostring(path))
        else
            local comp = S.avatar:AddComponentByClass(kind == "S" and staticCls or skelCls, true, IDENT, false)
            if comp and comp:IsValid() then
                comp:SetMobility(2)   -- movable; static-mesh components default to static
                if kind == "S" then comp:SetStaticMesh(asset) else comp:SetSkinnedAssetAndUpdate(asset, true) end
                pcall(function() comp:SetCollisionEnabled(0) end)
                placeAttached(comp, S.avatarComp, attachName, rel, S.pelvisScale or 1)
                local loc = { X = tonumber(lx), Y = tonumber(ly), Z = tonumber(lz) }
                local rot = { Pitch = tonumber(rp), Yaw = tonumber(ry), Roll = tonumber(rr) }
                if rel then
                    -- already placed at the socket's spot by hand; add the item's own offset on top
                    comp:K2_AddLocalOffset(loc, false, {}, true)
                    comp:K2_AddLocalRotation(rot, false, {}, true)
                else
                    comp:K2_SetRelativeLocationAndRotation(loc, rot, false, {}, true)
                end
                S.heldComps[#S.heldComps + 1] = comp
            end
        end
    end
    log("avatar now holds " .. #S.heldComps .. " item(s)")
end

-- ================================================================ second player avatar

local function meshAssetOf(comp)
    local ok, a = pcall(function() return comp.SkeletalMeshAsset end)
    if ok and a and a:IsValid() then return a end
    ok, a = pcall(function() return comp.SkeletalMesh end)
    if ok and a and a:IsValid() then return a end
    return nil
end

local function destroyActor(a)
    if a and a:IsValid() then pcall(function() a:K2_DestroyActor() end) end
end

-- A new actor with a poseable copy of James's mesh. Returns the actor and its mesh component.
local function spawnBody(pawn)
    local statics = UEHelpers.GetGameplayStatics()
    local actorCls = StaticFindObject("/Script/Engine.Actor")
    local poseCls = StaticFindObject("/Script/Engine.PoseableMeshComponent")
    if not (actorCls and actorCls:IsValid() and poseCls and poseCls:IsValid()) then
        warnOnce("cls", "engine classes for the avatar not found")
        return nil
    end
    local asset = meshAssetOf(pawn.Mesh)
    if not asset then warnOnce("asset", "player mesh asset not found") return nil end

    local loc = pawn:K2_GetActorLocation()
    local xf = {
        Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
        Translation = { X = loc.X, Y = loc.Y, Z = loc.Z },
        Scale3D = { X = 1, Y = 1, Z = 1 },
    }
    local actor = statics:BeginDeferredActorSpawnFromClass(pawn:GetWorld(), actorCls, xf, 1, nil) -- 1 = AlwaysSpawn
    if not actor or not actor:IsValid() then warnOnce("spawn", "avatar spawn failed") return nil end
    statics:FinishSpawningActor(actor, xf)

    local comp = actor:AddComponentByClass(poseCls, false, IDENT, false)
    if not comp or not comp:IsValid() then
        warnOnce("comp", "could not add the avatar's mesh component")
        destroyActor(actor)
        return nil
    end
    comp:SetSkinnedAssetAndUpdate(asset, true)
    pcall(function() comp:SetCollisionEnabled(0) end)
    pcall(function() actor:SetActorEnableCollision(false) end)
    S.jamesRefZ = comp:GetBoneLocationByName(BONES[1], 1).Z   -- James's rest-pose pelvis height
    return actor, comp
end

local function spawnAvatar(pawn)
    local actor, comp = spawnBody(pawn)
    if not actor then return nil end
    S.avatarComp = comp
    S.avatarModel = "james"
    S.pelvisScale = 1
    S.heldComps = {}
    S.heldApplied = nil
    S.lightComp = nil
    S.capsule = nil
    S.collisionOn = nil
    S.avatarScale = nil
    for _, st in pairs(S.enemyState or {}) do st.forced = nil end   -- they were after the old body
    log("avatar spawned: " .. actor:GetFullName())
    return actor
end

-- ---------------------------------------------------------------- my own model on my screen

-- Seeing yourself as another character: the real James keeps running all the game's animation
-- but is made invisible, and a poseable body of the chosen model is attached to him and copies
-- his pose every frame (fingers included). Weapons stay attached to the real, hidden skeleton.

local function showRealBody(pawn, visible)
    local mesh = pawn.Mesh
    if visible then
        mesh:SetVisibility(true, false)
        if S.savedTickOption ~= nil then
            pcall(function() mesh.VisibilityBasedAnimTickOption = S.savedTickOption end)
            S.savedTickOption = nil
        end
    else
        if S.savedTickOption == nil then
            pcall(function() S.savedTickOption = mesh.VisibilityBasedAnimTickOption end)
        end
        pcall(function() mesh.VisibilityBasedAnimTickOption = 0 end)   -- keep animating while unseen
        mesh:SetVisibility(false, false)   -- false: do not hide what is attached to him
    end
end

local function removeSelfBody(pawn)
    destroyActor(S.selfActor)
    S.selfActor, S.selfComp, S.selfBones = nil, nil, nil
    if pawn then showRealBody(pawn, true) end
end

-- Runs from tick(): create, swap or remove the on-screen model as the settings ask.
local function manageSelf(pawn)
    local want = nil
    if on("show_my_model_to_me") and cfg.my_model ~= "james" and MODELS[cfg.my_model] then want = cfg.my_model end

    local addr = pawn:GetAddress()
    if S.selfPawn ~= addr then   -- a different James than last time (save loaded): start over
        S.selfPawn = addr
        S.selfActor, S.selfComp, S.selfBones, S.selfModel, S.savedTickOption = nil, nil, nil, nil, nil
    end
    if want == S.selfModel then
        -- the game may turn him visible again (cutscenes, loading); keep him hidden while swapped
        if want and S.selfComp and S.selfComp:IsValid() and pawn.Mesh:IsVisible() then showRealBody(pawn, false) end
        return
    end
    S.selfModel = want   -- also remembers a choice that failed, so it is not retried every tick

    if not want then removeSelfBody(pawn) return end
    local asset = findAsset(MODELS[want])
    if not asset then
        warnOnce("self-missing:" .. want, "model '" .. want .. "' could not be loaded for your own character")
        removeSelfBody(pawn)
        return
    end
    if not (S.selfComp and S.selfComp:IsValid()) then
        S.selfActor, S.selfComp = spawnBody(pawn)
        if not S.selfActor then return end
        S.selfComp:K2_AttachToComponent(pawn.Mesh, FName("None"), 2, 2, 2, false)   -- rides on James
    end
    local comp = S.selfComp
    comp:SetSkinnedAssetAndUpdate(asset, true)
    if comp:GetBoneIndex(BONES[1]) < 0 then
        warnOnce("self-bones:" .. want, "model '" .. want .. "' has a different skeleton; keeping James")
        removeSelfBody(pawn)
        return
    end
    local refZ = comp:GetBoneLocationByName(BONES[1], 1).Z
    S.selfScale = (S.jamesRefZ and S.jamesRefZ > 1 and refZ > 1) and (refZ / S.jamesRefZ) or 1
    local bones = {}
    for i = 1, #SELF_BONES do
        if comp:GetBoneIndex(SELF_BONES[i]) >= 0 then bones[#bones + 1] = SELF_BONES[i] end
    end
    S.selfBones = bones
    showRealBody(pawn, false)
    log(string.format("you now appear as %s on your own screen (%d bones)", want, #bones))
end

-- Runs every frame: copy the hidden James's pose onto the model we see.
local function selfFrame(pawn)
    local comp = S.selfComp
    if not (comp and comp:IsValid() and S.selfBones and S.selfPawn == pawn:GetAddress()) then return end
    local pose = capturePose(pawn, S.selfBones)
    applyPose(comp, pose, pose, 0, S.selfScale, S.selfBones)
end

-- Which model the other player should have here: our override, else their own choice.
local function desiredModel()
    local m = cfg.other_model
    if m == "auto" or not MODELS[m] then m = peer.model end
    if not m or not MODELS[m] then m = "james" end
    return m
end

local function applyModel(pawn)
    local want = desiredModel()
    local comp = S.avatarComp
    if want == S.avatarModel or not (comp and comp:IsValid()) then return end

    local asset = (want == "james") and meshAssetOf(pawn.Mesh) or findAsset(MODELS[want])
    if asset then
        comp:SetSkinnedAssetAndUpdate(asset, true)
        if comp:GetBoneIndex(BONES[1]) < 0 then
            warnOnce("model-bones:" .. want, "model '" .. want .. "' has a different skeleton; using James")
            asset = nil
        end
    else
        warnOnce("model-missing:" .. want, "model '" .. want .. "' could not be loaded; using James")
    end
    if not asset then
        want = "james"
        comp:SetSkinnedAssetAndUpdate(meshAssetOf(pawn.Mesh), true)
    end

    local refZ = comp:GetBoneLocationByName(BONES[1], 1).Z
    if want == "james" then S.jamesRefZ = refZ end
    S.pelvisScale = (S.jamesRefZ and S.jamesRefZ > 1 and refZ > 1) and (refZ / S.jamesRefZ) or 1
    S.avatarModel = desiredModel() == want and want or desiredModel()   -- remember a failed choice too
    S.heldApplied = nil   -- re-attach held items to the new body
    if S.lightComp and S.lightComp:IsValid() then   -- and rebuild the flashlight beam on it
        pcall(function() S.lightComp:K2_DestroyComponent(S.lightComp) end)
    end
    S.lightComp = nil
    log(string.format("other player's model: %s (height scale %.2f)", want, S.pelvisScale))
end

-- ---------------------------------------------------------------- flashlight beam

-- Our own flashlight, as "F <on> <pitch*10> <yaw*10>" (world direction of the beam).
local function flashlightState(pawn)
    if not (S.myFl and S.myFl:IsValid()) or S.tickCount % HELD_EVERY == 0 then
        S.myFl = nil
        pawn.Items.EquipmentActors:ForEach(function(_, e)
            local a = e:get()
            if a and a:IsValid() and a:GetClass():GetFName():ToString():find("Flashlight") then S.myFl = a end
        end)
    end
    local fl = S.myFl
    if not fl then S.myFlash = { 0, 0, 0 } return "F 0 0 0" end
    local r = fl.LightMain:K2_GetComponentRotation()
    S.myFlash = { fl:IsTurnOn() and 1 or 0, round(r.Pitch * 10), round(r.Yaw * 10) }
    return string.format("F %d %d %d", S.myFlash[1], S.myFlash[2], S.myFlash[3])
end

-- A spot light on the avatar's chest, set up like our own flashlight's main light.
local function ensureLight(pawn)
    if S.lightComp and S.lightComp:IsValid() then return end
    if not (S.avatar and S.avatar:IsValid() and S.avatarComp and S.avatarComp:IsValid()) then return end
    local cls = StaticFindObject("/Script/Engine.SpotLightComponent")
    local light = S.avatar:AddComponentByClass(cls, true, IDENT, false)
    if not light or not light:IsValid() then warnOnce("light", "could not create the flashlight beam") return end
    light:SetMobility(2)
    local attachName, rel = attachPoint(pawn, S.avatarComp, "FlashlightSocket")
    if attachName then
        placeAttached(light, S.avatarComp, attachName, rel, S.pelvisScale or 1)
    else
        light:K2_AttachToComponent(S.avatarComp, FName("None"), 2, 2, 2, false)
        light:K2_SetRelativeLocation({ X = 0, Y = 15, Z = 135 }, false, {}, true)   -- roughly chest height
    end
    light:SetAbsolute(false, true, false)   -- we aim it in world space every frame

    -- Values measured on the game's own flashlight; replaced by live ones when we carry one.
    -- The falloff mode matters most: the game uses the exponent falloff, where an intensity of
    -- 48 is bright. A fresh light defaults to inverse-squared falloff, where 48 is invisible.
    local intensity, inner, outer, radius = 48, 16, 30, 1200
    local inverseSquared, exponent = false, 8.0
    local sourceRadius, softRadius, volumetric, specular, fnFade = 3.0, 2.0, 0.5, 0.5, 1050
    local src = S.myFl and S.myFl:IsValid() and S.myFl.LightMain or nil
    if src and src:IsValid() then
        if src.Intensity > 1 then intensity = src.Intensity end
        inner, outer, radius = src.InnerConeAngle, src.OuterConeAngle, src.AttenuationRadius
        pcall(function() inverseSquared = src.bUseInverseSquaredFalloff end)
        pcall(function() exponent = src.LightFalloffExponent end)
        pcall(function() sourceRadius, softRadius = src.SourceRadius, src.SoftSourceRadius end)
        pcall(function() volumetric, specular = src.VolumetricScatteringIntensity, src.SpecularScale end)
        pcall(function() fnFade = src.LightFunctionFadeDistance end)
        pcall(function() light:SetLightFunctionMaterial(src.LightFunctionMaterial) end)
        pcall(function() light:SetLightFunctionScale(src.LightFunctionScale) end)
        pcall(function() light:SetIESTexture(src.IESTexture) end)
    end
    pcall(function() light:SetIntensityUnits(0) end)   -- unitless, like the game's own
    pcall(function() light.bUseInverseSquaredFalloff = inverseSquared end)
    -- A property write alone does not reach the renderer; these setters do, but only when the
    -- value actually changes, hence the nudge on the first one.
    pcall(function() light:SetLightFalloffExponent(exponent + 0.01) end)
    pcall(function() light:SetLightFalloffExponent(exponent) end)
    pcall(function() light:SetSourceRadius(sourceRadius) end)
    pcall(function() light:SetSoftSourceRadius(softRadius) end)
    pcall(function() light:SetVolumetricScatteringIntensity(volumetric) end)
    pcall(function() light:SetSpecularScale(specular) end)
    pcall(function() light:SetLightFunctionFadeDistance(fnFade) end)
    light:SetIntensity(intensity)
    S.lightBase = intensity
    S.lightBrightness = nil   -- makes the tick apply the brightness setting to this new light
    light:SetInnerConeAngle(inner)
    light:SetOuterConeAngle(outer)
    light:SetAttenuationRadius(radius)
    light:SetLightColor({ R = 1.0, G = 0.988, B = 0.941, A = 1.0 }, true)
    light:SetCastShadows(on("flashlight_shadows"))
    S.lightShadows = cfg.flashlight_shadows
    light:SetVisibility(false, false)
    S.lightVisible = false
    S.lightComp = light
    log("flashlight beam created for the other player")
end

local function setAvatarVisible(v)
    if S.avatar and S.avatar:IsValid() and S.avatarVisible ~= v then
        pcall(function() S.avatar:SetActorHiddenInGame(not v) end)
        S.avatarVisible = v
        if not v and S.lightComp and S.lightComp:IsValid() then   -- a hidden body must not keep shining
            pcall(function() S.lightComp:SetVisibility(false, false) end)
            S.lightVisible = false
        end
    end
end

local function staleSeconds()
    local s = tonumber(cfg.peer_timeout_s) or 3
    if s < 1 then s = 1 elseif s > 30 then s = 30 end
    return s
end

-- Left over from earlier versions of this file in the same game session: remove them.
if S.avatarKind ~= "poseable-v3" then
    destroyActor(S.avatar)
    S.avatar = nil
    S.avatarKind = "poseable-v3"
end
if S.poseTest then
    destroyActor(S.poseTest.actor)
    S.poseTest = nil
end
-- After a reload, rebuild what hangs on the avatar so it is made by the current code.
S.heldApplied = nil
if S.lightComp and S.lightComp:IsValid() then
    pcall(function() S.lightComp:K2_DestroyComponent(S.lightComp) end)
end
S.lightComp = nil

local function pushSnap(snap)
    local snaps = S.snaps
    local last = snaps[#snaps]
    if last and snap.t <= last.t then snap.t = last.t + 0.001 end
    snaps[#snaps + 1] = snap
    while #snaps > MAX_SNAPS do table.remove(snaps, 1) end
end

-- The two snapshots around time rt and how far between them rt lies.
local function sampleSnaps(rt)
    local snaps = S.snaps
    local n = #snaps
    if n == 0 then return nil end
    if n == 1 or rt >= snaps[n].t then return snaps[n], snaps[n], 0 end
    for i = n - 1, 1, -1 do
        if snaps[i].t <= rt then
            local a, b = snaps[i], snaps[i + 1]
            local span = b.t - a.t
            return a, b, (span > 0) and ((rt - a.t) / span) or 0
        end
    end
    return snaps[1], snaps[1], 0
end

-- Runs every rendered frame: draw the other player.
local function frame()
    S.frameCount = (S.frameCount or 0) + 1
    local pawn = getPawn()
    if not pawn then return end

    local okSelf, errSelf = pcall(selfFrame, pawn)
    if not okSelf then warnOnce("self:" .. tostring(errSelf), "own model error: " .. tostring(errSelf)) end

    local now = os.clock()
    -- hidden when there is no news of them, when switched off, and while we watch a cutscene
    if #S.snaps == 0 or (now - peer.lastTime) > staleSeconds() or not on("show_other_player") or S.cutPlaying then
        setAvatarVisible(false)
        return
    end
    if not S.avatar or not S.avatar:IsValid() then
        S.avatar = spawnAvatar(pawn)
        S.avatarVisible = true
        if not S.avatar then return end
    end
    setAvatarVisible(true)

    local delay = (tonumber(cfg.interp_delay_ms) or 100) / 1000
    if delay < 0 then delay = 0 elseif delay > 0.5 then delay = 0.5 end
    local a, b, alpha = sampleSnaps(now - delay)
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    if dx * dx + dy * dy + dz * dz > SNAP_DISTANCE * SNAP_DISTANCE then alpha = 1 end

    local offZ, offYaw = -90.0, -90.0
    pcall(function()
        offZ = pawn.Mesh.RelativeLocation.Z
        offYaw = pawn.Mesh.RelativeRotation.Yaw
    end)
    S.avatar:K2_SetActorLocationAndRotation(
        { X = a.x + dx * alpha, Y = a.y + dy * alpha, Z = a.z + dz * alpha + offZ },
        { Pitch = 0, Yaw = lerpAngle(a.yaw, b.yaw, alpha) + offYaw, Roll = 0 },
        false, {}, true)

    if a.pose and b.pose and S.avatarComp and S.avatarComp:IsValid() then
        applyPose(S.avatarComp, a.pose, b.pose, alpha, S.pelvisScale)
    end

    -- their flashlight beam
    local light = S.lightComp
    if light and light:IsValid() then
        local want = on("sync_flashlight") and b.fl == 1
        if want ~= S.lightVisible then
            light:SetVisibility(want, false)
            S.lightVisible = want
        end
        if want and a.fp and b.fp then
            light:K2_SetWorldRotation(
                { Pitch = (a.fp + (b.fp - a.fp) * alpha) / 10, Yaw = lerpAngle(a.fy / 10, b.fy / 10, alpha), Roll = 0 },
                false, {}, true)
        end
    end
end

-- ================================================================ collision with the other player

-- An invisible capsule on the avatar, the same size as our own, that blocks pawns only: us and
-- enemies walk into it, while doors, bullets and the camera pass through.
local function updateCollision(pawn)
    local want = on("other_player_collision") and S.avatarVisible == true
    if want == S.collisionOn and (not want or (S.capsule and S.capsule:IsValid())) then return end
    if want then
        if not (S.capsule and S.capsule:IsValid()) then
            local cap = S.avatar:AddComponentByClass(StaticFindObject("/Script/Engine.CapsuleComponent"), true, IDENT, false)
            if not cap or not cap:IsValid() then warnOnce("capsule", "could not create the collision capsule") return end
            cap:SetMobility(2)
            cap:K2_AttachToComponent(S.avatarComp, FName("None"), 2, 2, 2, false)
            local radius, half = 40, 90
            pcall(function()
                radius = pawn.CapsuleComponent:GetScaledCapsuleRadius()
                half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
            end)
            cap:SetCapsuleSize(radius, half, false)
            cap:K2_SetRelativeLocation({ X = 0, Y = 0, Z = half }, false, {}, true)   -- the avatar's origin is at its feet
            cap:SetCollisionObjectType(1)             -- world dynamic
            cap:SetCollisionResponseToAllChannels(0)  -- ignore everything...
            cap:SetCollisionResponseToChannel(2, 2)   -- ...except pawns, which it blocks
            S.capsule = cap
        end
        S.avatar:SetActorEnableCollision(true)
        S.capsule:SetCollisionEnabled(3)   -- query and physics
    else
        if S.capsule and S.capsule:IsValid() then S.capsule:SetCollisionEnabled(0) end
        pcall(function() S.avatar:SetActorEnableCollision(false) end)
    end
    S.collisionOn = want
    log("collision with the other player " .. (want and "on" or "off"))
end

-- ================================================================ doors

-- Every door near either player is driven by exactly one game: the one whose player stands
-- closer to it. That game lets the door behave normally (pushed open, auto-closing) and reports
-- its angle; the other game moves its copy of the door to match. So when the other player walks
-- through a door, it opens here too. Locks are synced as reliable events in both directions.
--
-- A door is identified by a hash of its level path and component name, which is the same on
-- both PCs because doors are placed in the level, not spawned.

local DOOR_RANGE = 1500      -- only doors this close to a player are handled (centimetres)
local DOOR_TIE = 60          -- distances this close count as a tie; the host drives the door
local DOOR_TOUCH = 120       -- the other player's body this close to a door leaf pushes it open
local SETTLE_SECONDS = 6     -- how long a freshly loaded door or pickup is left alone
S.doorState = S.doorState or {}       -- id -> { lock = bool, lastTarget = angle }
S.pendingLocks = S.pendingLocks or {} -- id -> bool, for doors not loaded here yet
S.doors = S.doors or {}               -- currently loaded doors: { id, comp, lock, x, y, z }

local function hashName(s)   -- djb2, 32 bit
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) & 0xFFFFFFFF end
    return string.format("%08x", h)
end

local function scanDoors()
    if not (S.doorMgr and S.doorMgr:IsValid()) then
        S.doorMgr = FindFirstOf("SHDoorsManagerComponent")
        if not (S.doorMgr and S.doorMgr:IsValid()) then S.doors = {} return end
    end
    local list, seen = {}, {}
    local now = os.clock()
    S.doorMgr.RegisteredDoorMovementComponents:ForEach(function(_, e)
        local comp = e:get()
        if comp and comp:IsValid() then
            local owner = comp:GetOwner()
            local path = owner:GetFullName():match("^%S+%s+(.+)$") or owner:GetFullName()
            local id = hashName(path .. "." .. comp:GetFName():ToString())
            local loc = owner:K2_GetActorLocation()
            local door = { id = id, comp = comp, lock = comp.ManagedDoorLockComponent, x = loc.X, y = loc.Y, z = loc.Z }
            -- Where the door leaf is when closed, and where it would be swung 30 degrees either
            -- way: enough to tell which side of the door somebody stands on.
            pcall(function()
                local c0 = comp:GetDoorTraceLoc(comp.ClosedAngle)
                local cp = comp:GetDoorTraceLoc(comp.ClosedAngle + 30)
                local cn = comp:GetDoorTraceLoc(comp.ClosedAngle - 30)
                door.leaf = { c0.X, c0.Y, c0.Z, cp.X, cp.Y, cn.X, cn.Y }
            end)
            list[#list + 1] = door

            local st = S.doorState[id]
            if not st then st = {} S.doorState[id] = st end
            seen[id] = true
            -- A door that has just streamed in is still being set up by the game (its saved lock
            -- state is applied a moment after it appears). Those changes are not player actions,
            -- so nothing is reported, or applied, until the door has been around for a while.
            if not (S.doorSeen and S.doorSeen[id]) then st.since = now end
            local settled = now - (st.since or now) >= SETTLE_SECONDS
            if door.lock and door.lock:IsValid() then
                local locked = door.lock.bIsDoorLocked
                if not settled then
                    st.lock = locked
                elseif S.pendingLocks[id] ~= nil then      -- a change that arrived before the door loaded
                    door.lock:SetLocked(S.pendingLocks[id], false)
                    st.lock = S.pendingLocks[id]
                    S.pendingLocks[id] = nil
                elseif st.lock == nil then
                    st.lock = locked
                elseif st.lock ~= locked then
                    st.lock = locked
                    -- Only unlocking is shared. The game also locks doors behind the player to
                    -- gate areas; copying that could shut the other player out, and their own
                    -- game applies the same gating when they get there.
                    if not locked then
                        enqueue("lock " .. id .. " 0")
                        log("door unlocked here, telling the other player")
                    end
                end
            end
        end
    end)
    -- Sliding doors are not in the manager's list and are not moved by this mod yet, but their
    -- locks work the same way, so unlocking one is shared like any other door.
    local sliding = {}
    local slidingAll = FindAllOf("SHSlidingDoorMovementComponent")
    if slidingAll then
        for i = 1, #slidingAll do
            local comp = slidingAll[i]
            if comp:IsValid() then
                local owner = comp:GetOwner()
                local lock = comp.ManagedDoorLockComponent
                if owner and owner:IsValid() and lock and lock:IsValid() then
                    local path = owner:GetFullName():match("^%S+%s+(.+)$") or owner:GetFullName()
                    local id = hashName(path .. "." .. comp:GetFName():ToString())
                    sliding[#sliding + 1] = { id = id, lock = lock }
                    seen[id] = true
                    local st = S.doorState[id]
                    if not st then st = {} S.doorState[id] = st end
                    if not (S.doorSeen and S.doorSeen[id]) then st.since = now end
                    local locked = lock.bIsDoorLocked
                    if now - (st.since or now) < SETTLE_SECONDS then
                        st.lock = locked
                    elseif S.pendingLocks[id] ~= nil then
                        lock:SetLocked(S.pendingLocks[id], false)
                        st.lock = S.pendingLocks[id]
                        S.pendingLocks[id] = nil
                    elseif st.lock == nil then
                        st.lock = locked
                    elseif st.lock ~= locked then
                        st.lock = locked
                        if not locked then
                            enqueue("lock " .. id .. " 0")
                            log("sliding door unlocked here, telling the other player")
                        end
                    end
                end
            end
        end
    end
    S.slidingDoors = sliding
    S.doors = list
    S.doorSeen = seen
end

onRemoteLock = function(id, locked)
    if locked then return end   -- only unlocks are applied (see scanDoors)
    local st = S.doorState[id]
    if not st then st = {} S.doorState[id] = st end
    st.lock = locked
    for _, list in ipairs({ S.doors, S.slidingDoors or {} }) do
        for _, door in ipairs(list) do
            if door.id == id and door.lock and door.lock:IsValid() then
                door.lock:SetLocked(locked, false)
                log("door " .. (locked and "locked" or "unlocked") .. " by the other player")
                return
            end
        end
    end
    S.pendingLocks[id] = locked
end

local function dist3(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ~10x a second: decide who drives each nearby door, report ours, follow theirs.
local function doorsTick(pawn)
    local me = pawn:K2_GetActorLocation()
    local newest = S.snaps[#S.snaps]
    local havePeer = peer.connected and newest ~= nil and not S.mirror
    local theirs = peer.doors or {}
    local mine = {}
    local now = os.clock()
    local body = nil   -- where the other player's body stands in this world, if it is shown
    if S.avatar and S.avatar:IsValid() and S.avatarVisible then body = S.avatar:K2_GetActorLocation() end
    if S.testBody then body = S.testBody end   -- development: pretend the body stands somewhere
    for _, door in ipairs(S.doors) do
        local comp = door.comp
        if comp:IsValid() then
            local myDist = dist3(me.X, me.Y, me.Z, door.x, door.y, door.z)
            local peerDist = havePeer and dist3(newest.x, newest.y, newest.z, door.x, door.y, door.z) or math.huge
            local bodyDist = body and dist3(body.X, body.Y, body.Z, door.x, door.y, door.z) or math.huge
            local prior = S.doorState[door.id]
            -- also visit doors we are still holding, however far away, so they are always released
            if myDist < DOOR_RANGE or peerDist < DOOR_RANGE or bodyDist < DOOR_RANGE
                or (prior and (prior.held or prior.pushed)) then
                local iDrive = (not havePeer) or myDist < peerDist - DOOR_TIE
                    or (math.abs(myDist - peerDist) <= DOOR_TIE and S.role == "host")
                local st = S.doorState[door.id]
                if not st then st = {} S.doorState[door.id] = st end
                local target = (not iDrive) and theirs[door.id] or nil
                if target and not comp.bIsDoorFrozen then
                    -- A door closes itself when no player of *this* game stands near it, which
                    -- would undo every move we copy. Hold that off while the other game drives it.
                    if not st.held then
                        comp:SetAutocloseBlocked(true, pawn)
                        st.held = true
                    end
                    if math.abs(comp:GetCurrentDoorAngle() - target) > 2 and st.lastTarget ~= target then
                        st.lastTarget = target
                        comp:RequestCustomFakeMovement(target, math.max(comp.FakeMovementSpeed * 2, 10), comp.FakeMovementBlendExp, true)
                    end
                else
                    -- Nobody is driving this door remotely. The game only opens doors for its own
                    -- player, so when the other player's body walks into one here we open it for
                    -- them, away from the side they are on. (In a real session their own game
                    -- normally drives the door; this covers the solo test and any gap.)
                    local leaf = door.leaf
                    local touching = false
                    if body and leaf and not comp.bIsDoorFrozen
                        and not (door.lock and door.lock:IsValid() and door.lock.bIsDoorLocked) then
                        local dx, dy = body.X - leaf[1], body.Y - leaf[2]
                        touching = dx * dx + dy * dy < DOOR_TOUCH * DOOR_TOUCH and math.abs(body.Z + 90 - leaf[3]) < 170
                    end
                    if touching then
                        if not st.pushed then
                            local toPlus = (body.X - leaf[4]) ^ 2 + (body.Y - leaf[5]) ^ 2
                            local toMinus = (body.X - leaf[6]) ^ 2 + (body.Y - leaf[7]) ^ 2
                            local wantSign = (toPlus < toMinus) and -1 or 1   -- swing away from them
                            local openTo = comp.OpenedAngle
                            if comp.OpenBothSides and (comp.OpenedAngle - comp.ClosedAngle) * wantSign < 0 then
                                openTo = comp.OtherSideOpenedAngle
                            end
                            if not st.held then
                                comp:SetAutocloseBlocked(true, pawn)
                                st.held = true
                            end
                            comp:RequestCustomFakeMovement(openTo, math.max(comp.FakeMovementSpeed * 2, 10), comp.FakeMovementBlendExp, true)
                            log(string.format("opened a door for the other player (to %.0f degrees)", openTo))
                        end
                        st.pushed = now
                    elseif st.pushed and now - st.pushed > 1.2 then
                        st.pushed = nil           -- they have moved on
                    end
                    if st.held and not st.pushed then   -- give the door back to the game
                        comp:SetAutocloseBlocked(false, pawn)
                        st.held = nil
                    end
                    st.lastTarget = nil
                    if iDrive and myDist < DOOR_RANGE and #mine < 8 then
                        mine[#mine + 1] = door.id .. ":" .. math.floor(comp:GetCurrentDoorAngle() * 10 + 0.5)
                    end
                end
            end
        end
    end
    S.myDoors = (#mine > 0) and table.concat(mine, " ") or nil
end

-- ================================================================ moving to the other player

local function teleportPawn(pawn, x, y, z, yaw, why)
    local p = pawn:K2_GetActorLocation()
    local far = dist3(p.X, p.Y, p.Z, x, y, z) > 1500
    pawn:K2_TeleportTo({ X = x, Y = y, Z = z + 5 }, { Pitch = 0, Yaw = yaw, Roll = 0 })
    pcall(function() getPC():SetControlRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }) end)
    if far then
        -- The area may still be streaming in. Hold the player in place for a moment so they
        -- cannot fall through a floor that is not there yet.
        pcall(function() pawn.CharacterMovement:SetMovementMode(0, 0) end)   -- 0 = no movement
        S.releaseMoveAt = os.clock() + 2.0
    end
    log("moved to the other player (" .. why .. ")")
end

-- ================================================================ cutscenes

-- The story follows the host, and both players watch every cutscene together:
--   * When a cutscene starts in one game, the other player is moved to where it was triggered.
--     Usually that makes their own game trigger the same cutscene, with all the game logic
--     attached to it. If it has not started after a moment, it is started directly.
--   * When it is over, the joiner is placed right beside the host.
-- Cutscenes are placed in the level, so a hash of their level path identifies them on both PCs.

S.cutPlayers = S.cutPlayers or {}

local function scanCutscenes()
    local list = {}
    local all = FindAllOf("SHCutscenePlayer")
    if all then
        for i = 1, #all do
            local c = all[i]
            if c:IsValid() then
                local path = c:GetFullName():match("^%S+%s+(.+)$") or c:GetFullName()
                list[#list + 1] = { id = hashName(path), actor = c }
            end
        end
    end
    S.cutPlayers = list
    S.cutScanned = os.clock()
end

local function findCutscene(id)
    for _, c in ipairs(S.cutPlayers) do
        if c.id == id and c.actor:IsValid() then return c.actor end
    end
    return nil
end

local function playingCutscene()
    for _, c in ipairs(S.cutPlayers) do
        if c.actor:IsValid() and c.actor:IsPlaying() then return c.id end
    end
    return nil
end

onRemoteCutscene = function(id, x, y, z, yaw)
    if not on("sync_cutscenes") or S.cutPlaying == id then return end
    S.cutRequest = { id = id, x = x, y = y, z = z, yaw = yaw, deadline = os.clock() + 12 }
    S.cutExpected = id   -- when it starts here we must not announce it back
    log("the other player started a cutscene; joining it")
end

-- ~3x a second.
local function cutsceneTick(pawn)
    local now = os.clock()
    if not S.cutScanned or now - S.cutScanned > 5 then scanCutscenes() end

    local playing = playingCutscene()
    if playing ~= S.cutPlaying then
        if playing then
            log("cutscene started here")
            if S.cutExpected ~= playing and not S.mirror then
                local f = S.freePos
                if f then enqueue(string.format("cut %s %d %d %d %d", playing, f[1], f[2], f[3], f[4])) end
            end
            S.cutExpected, S.cutRequest = nil, nil
        else
            log("cutscene ended here")
            S.regroupAt = now + 0.5
        end
        S.cutPlaying = playing
    end
    if not playing then
        local p, r = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
        S.freePos = { math.floor(p.X), math.floor(p.Y), math.floor(p.Z), math.floor(r.Yaw) }
    end

    -- a cutscene the other player started and we have not joined yet
    local req = S.cutRequest
    if req and not playing then
        if now > req.deadline then
            S.cutRequest, S.cutExpected = nil, nil
            log("could not join the other player's cutscene in time")
        else
            local actor = findCutscene(req.id)
            if not actor and now - S.cutScanned > 1 then scanCutscenes() actor = findCutscene(req.id) end
            if actor and actor:IsAlreadyPlayedOnce() then
                S.cutRequest, S.cutExpected = nil, nil      -- this game has already been through it
            elseif not req.moved then
                teleportPawn(pawn, req.x, req.y, req.z, req.yaw, "cutscene")
                req.moved = now
            elseif actor and not req.started and now - req.moved > 1.5 then
                req.started = true
                pcall(function() actor:Activate() end)
                log("started the cutscene directly")
            end
        end
    end

    -- afterwards the joiner stands beside the host
    if S.regroupAt and now >= S.regroupAt and not playing then
        if S.role ~= "join" or not peer.connected or not on("sync_cutscenes") then
            S.regroupAt = nil
        elseif peer.cut == "0" then
            local n = S.snaps[#S.snaps]
            if n then
                local p = pawn:K2_GetActorLocation()
                if dist3(p.X, p.Y, p.Z, n.x, n.y, n.z) > 150 then
                    local yaw = n.yaw / RAD
                    teleportPawn(pawn, n.x - math.sin(yaw) * 80, n.y + math.cos(yaw) * 80, n.z, n.yaw, "after the cutscene")
                end
            end
            S.regroupAt = nil
        end
    end
end

-- ================================================================ world pickups

-- With a shared inventory, something picked up in one game is given to both players. The copy
-- of that pickup lying in the other game's world is then marked collected and removed, so it
-- cannot be taken a second time.

S.itemState = S.itemState or {}       -- id -> collected?
S.takenRemote = S.takenRemote or {}   -- id -> true, taken by the other player

onRemoteTook = function(id)
    S.takenRemote[id] = true
    S.itemsDue = true
end

local function itemsTick(pawn)
    local all = FindAllOf("SHItem")
    if not all then return end
    local now = os.clock()
    local seen = {}
    S.itemSince = S.itemSince or {}
    for i = 1, #all do
        local item = all[i]
        if item:IsValid() then
            local id = hashName(item:GetFullName():match("^%S+%s+(.+)$") or "")
            local collected = item.bWasCollected
            seen[id] = true
            -- Like doors, a pickup that just streamed in gets its saved state a moment later;
            -- wait before reading anything into it.
            if not (S.itemSeen and S.itemSeen[id]) then S.itemSince[id] = now end
            if now - (S.itemSince[id] or now) < SETTLE_SECONDS then
                S.itemState[id] = collected
            elseif S.takenRemote[id] and not collected then
                pcall(function() item.bWasCollected = true end)
                item:SetItemDisabled(true, pawn)
                item:SetActorHiddenInGame(true)
                item:SetActorEnableCollision(false)
                collected = true
                S.itemState[id] = true
                log("removed a pickup the other player already took")
            end
            local known = S.itemState[id]
            if known == nil then
                S.itemState[id] = collected
            elseif collected and not known then
                S.itemState[id] = true
                local row = ""
                pcall(function() row = item.ItemData.RowName:ToString() end)
                if row == "" or itemShared(row) then enqueue("took " .. id) end
            end
        end
    end
    S.itemSeen = seen
end

-- ================================================================ pushable objects

-- Furniture and carts the player can push. Whoever is pushing drives the object: their game
-- reports its position ~10x a second, and the other game moves its copy with the pushable's own
-- "teleport to" call. When they let go, the resting place is sent once more as a reliable event
-- so it sticks even if a packet was lost.

S.pushables = S.pushables or {}     -- loaded: { id, comp, owner }
S.pushState = S.pushState or {}     -- id -> { since = first seen, mine = true while we push it }
S.pushRemote = S.pushRemote or {}   -- id -> { x, y, z }, resting places reported by the other player

local function scanPushables()
    local list, seen = {}, {}
    local now = os.clock()
    local all = FindAllOf("SHPushableComponent")
    if all then
        for i = 1, #all do
            local comp = all[i]
            if comp:IsValid() then
                local owner = comp:GetOwner()
                if owner and owner:IsValid() then
                    local id = hashName(owner:GetFullName():match("^%S+%s+(.+)$") or "")
                    list[#list + 1] = { id = id, comp = comp, owner = owner }
                    seen[id] = true
                    local st = S.pushState[id]
                    if not st then st = {} S.pushState[id] = st end
                    if not (S.pushSeen and S.pushSeen[id]) then st.since = now end   -- just streamed in
                end
            end
        end
    end
    S.pushables = list
    S.pushSeen = seen
end

onRemotePush = function(id, x, y, z)
    S.pushRemote[id] = { x, y, z }
end

-- ~10x a second.
local function pushablesTick(pawn)
    local pawnAddr = pawn:GetAddress()
    local theirs = peer.pushing or {}
    local mine = {}
    local now = os.clock()
    for _, p in ipairs(S.pushables) do
        if p.comp:IsValid() and p.owner:IsValid() then
            local st = S.pushState[p.id]
            if not st then st = { since = now } S.pushState[p.id] = st end
            local loc = p.owner:K2_GetActorLocation()
            local pushing = false
            pcall(function()
                local who = p.comp.InteractingCharacter
                pushing = who ~= nil and who:IsValid() and who:GetAddress() == pawnAddr
            end)
            if pushing then
                st.mine = true
                if #mine < 4 then
                    mine[#mine + 1] = string.format("%s:%d:%d:%d", p.id, math.floor(loc.X), math.floor(loc.Y), math.floor(loc.Z))
                end
            else
                if st.mine then   -- we just let go
                    st.mine = nil
                    if not S.mirror then
                        enqueue(string.format("push %s %d %d %d", p.id, math.floor(loc.X), math.floor(loc.Y), math.floor(loc.Z)))
                    end
                    log("you moved an object" .. (S.mirror and "" or ", telling the other player"))
                end
                -- follow the other player's copy, once ours has settled after loading
                local target = theirs[p.id] or S.pushRemote[p.id]
                if target and now - (st.since or now) >= SETTLE_SECONDS then
                    if dist3(target[1], target[2], target[3], loc.X, loc.Y, loc.Z) > 3 then
                        pcall(function() p.comp:TeleportAbsolute({ X = target[1], Y = target[2], Z = target[3] }) end)
                    end
                    if S.pushRemote[p.id] and not theirs[p.id] then
                        S.pushRemote[p.id] = nil
                        log("an object the other player moved is now in the same place here")
                    end
                end
            end
        end
    end
    S.myPushing = (#mine > 0) and table.concat(mine, " ") or nil
end

-- ================================================================ going to the other player

-- A catch-all for anything that separates the players and is not synced: elevators, jumping
-- down a hole, a one-way drop, or plain drift. F7 in game, or the launcher's button.
local function regroupNow(pawn)
    local n = S.snaps[#S.snaps]
    if not n or (os.clock() - peer.lastTime) > staleSeconds() then
        log("cannot go to the other player: no news of them")
        return
    end
    local yaw = n.yaw / RAD
    teleportPawn(pawn, n.x - math.sin(yaw) * 80, n.y + math.cos(yaw) * 80, n.z, n.yaw, "on request")
end

-- F7, because UE4SS's own console mod already takes F10 and tilde.
local function tryInstallRegroupKey()
    if S.regroupKeyF7 or S.regroupKeyFailed then return end
    local ok, err = pcall(RegisterKeyBind, Key.F7, function()
        local impl = SH2CoopMod.impl
        if impl and impl.onKey then pcall(impl.onKey, "F7") end
    end)
    if ok then S.regroupKeyF7 = true else S.regroupKeyFailed = true log("F7 could not be bound: " .. tostring(err)) end
end

-- The launcher can ask for things by dropping a one-word file into the ipc folder.
local function readLauncherCommand()
    local path = DIR .. "\\command.txt"
    local f = io.open(path, "r")
    if not f then return nil end
    local word = (f:read("a") or ""):match("%a+")
    f:close()
    os.remove(path)
    return word
end

-- ================================================================ saving and loading together

-- Each PC keeps its own save files, and the game can only "reload the latest save" from code,
-- not load a chosen slot. So the two games are kept in step like this:
--   * When the host's game saves, the joiner's game saves at the same moment (into the same
--     slot number when the host used one). Both PCs then hold a save of the same point.
--   * When the host loads, or dies and reloads, the joiner reloads its own latest save, which
--     is that matching one, and is then placed beside the host.
-- Limit: if the host deliberately loads an older slot, the joiner still gets its latest save.

local SAVE_FUNCTIONS = { "MakeFullSave", "SaveGame", "MakeQuickSave", "AutoSave" }

local function gameStatics()
    local st = StaticFindObject("/Script/GameBase.Default__GameBaseStatics")
    return (st and st:IsValid()) and st or nil
end

-- Called from the hooks below whenever this game saves.
local function onLocalSave(fn, slot)
    if S.savingForPeer or not on("sync_saves") then return end
    if S.role == "join" or S.mirror or not peer.connected then return end
    local now = os.clock()
    if now - (S.lastSaveSent or -100) < 5 then return end   -- one save can call several of these
    S.lastSaveSent = now
    enqueue("saved " .. tostring(slot))
    log("you saved; the joiner's game will save too")
end

local function tryInstallSaveHooks()
    if S.saveHooks then return end
    S.saveHooks = {}
    for _, fn in ipairs(SAVE_FUNCTIONS) do
        local ok = pcall(RegisterHook, "/Script/GameBase.GameBaseStatics:" .. fn, function(_, _, firstParam)
            local slot = -1
            if fn == "MakeFullSave" then pcall(function() slot = math.floor(firstParam:get()) end) end
            local impl = SH2CoopMod.impl
            if impl and impl.onLocalSave then pcall(impl.onLocalSave, fn, slot) end
        end)
        S.saveHooks[fn] = ok
    end
    local names = {}
    for fn, ok in pairs(S.saveHooks) do if ok then names[#names + 1] = fn end end
    log("save hooks installed: " .. (#names > 0 and table.concat(names, ", ") or "none"))
end

onRemoteSaved = function(pawn, slot)
    if not on("sync_saves") or S.role ~= "join" then return end
    local st = gameStatics()
    if not st then return end
    S.savingForPeer = true
    local ok, err = pcall(function()
        if slot >= 0 then
            st:MakeFullSave(pawn:GetWorld(), slot, "Co-op", false, true)
        else
            st:AutoSave(pawn:GetWorld(), "Co-op", false, true)
        end
    end)
    S.savingForPeer = nil
    log(ok and "saved here because the host saved" or ("could not save with the host: " .. tostring(err)))
end

onRemoteLoaded = function(pawn)
    if not on("sync_saves") or S.role ~= "join" then return end
    local now = os.clock()
    if now - (S.lastReloadAt or -100) < 20 then return end   -- one reload per host load
    S.lastReloadAt = now
    log("the host loaded; loading here too")
    local ok, err = pcall(function() UEHelpers.GetGameInstance():ReloadGame(false, "", false, nil, 0) end)
    if not ok then log("could not load with the host: " .. tostring(err)) end
end

-- Called when our player is back after not existing for a while, i.e. a load just finished.
local function onLoadedHere(pawn)
    local viaMenu = S.joinedViaMenu   -- we just loaded the host's save from the main menu
    S.joinedViaMenu = nil
    if S.role == "join" then
        if viaMenu or on("sync_saves") then
            S.regroupAfterLoad = os.clock() + 3  -- stand beside the host once they are visible
        end
    elseif on("sync_saves") and peer.connected and not S.mirror then
        enqueue("loaded")
        log("you loaded; the joiner's game will load too")
    end
end

-- ================================================================ puzzles

-- One player solves a puzzle, the story moves on for both. Every puzzle you zoom in on (safes,
-- padlocks and door locks, the coin cabinet and so on) carries the same component with a
-- "solved" state and a "set solved" call. When a puzzle becomes solved in one game, the other
-- game marks its copy solved too, which makes that game run the puzzle's own follow-up: the
-- lock opens, the item appears, the cutscene starts. Puzzles are placed in the level, so a
-- hash of their level path names them on both PCs.

S.puzzleState = S.puzzleState or {}     -- id -> solved?
S.solvedRemote = S.solvedRemote or {}   -- id -> true, solved by the other player

onRemoteSolved = function(id)
    S.solvedRemote[id] = true
    S.puzzlesDue = true
end

local function puzzlesTick(pawn)
    local all = FindAllOf("SHFocusableComponent")
    if not all then return end
    local now = os.clock()
    local seen = {}
    S.puzzleSince = S.puzzleSince or {}
    for i = 1, #all do
        local comp = all[i]
        if comp:IsValid() then
            local owner = comp:GetOwner()
            if owner and owner:IsValid() then
                local id = hashName(owner:GetFullName():match("^%S+%s+(.+)$") or "")
                local solved = comp:IsSolved()
                seen[id] = true
                -- like doors and pickups: leave a freshly loaded puzzle alone while the game
                -- is still applying its saved state
                if not (S.puzzleSeen and S.puzzleSeen[id]) then S.puzzleSince[id] = now end
                if now - (S.puzzleSince[id] or now) < SETTLE_SECONDS then
                    S.puzzleState[id] = solved
                else
                    -- solved by the other player: solve it here too, unless we are in the middle
                    -- of working on it ourselves (then wait until we step away)
                    if S.solvedRemote[id] and not solved and not comp:IsShown() then
                        pcall(function() comp:SetSolved() end)
                        solved = comp:IsSolved()
                        S.puzzleState[id] = true
                        log("a puzzle the other player solved is now solved here" .. (solved and "" or " (the game did not accept it)"))
                        if solved then S.solvedRemote[id] = nil end
                    end
                    local known = S.puzzleState[id]
                    if known == nil then
                        S.puzzleState[id] = solved
                    elseif solved and not known then
                        S.puzzleState[id] = true
                        if not S.mirror then enqueue("solved " .. id) end
                        log("you solved a puzzle" .. (S.mirror and "" or ", telling the other player"))
                    end
                end
            end
        end
    end
    S.puzzleSeen = seen
end

-- ================================================================ enemies

-- Both games keep running their own copy of every enemy (they come from the same spawners
-- placed in the level, so a hash of the spawner's path names an enemy on both PCs). Animation,
-- attacks and damage to the local player all stay native. The mod makes the copies agree:
--   * Health: damage either player deals is sent as a reliable event and applied to the other
--     copy; the host's health value is the reference the joiner follows.
--   * Target: an enemy that hunts one player hunts that player's body in the other game too,
--     so both copies chase the same person. Enemies treat whoever is closer as the threat.
--   * Position: the joiner's copy is nudged toward where the host's copy is.
-- Enemies not spawned by a single spawner (scripted groups, bosses) are left alone for now.

local ENEMY_RANGE = 3000     -- enemies this close to a player are handled (centimetres)
local ENEMY_MAX = 8          -- at most this many per packet
local ENEMY_SWITCH = 200     -- how much closer the other player must be before a target switches
S.enemies = S.enemies or {}        -- loaded: { id, actor, health }
S.enemyState = S.enemyState or {}  -- id -> { hp = last seen, forced = true when sent after the avatar }

S.enemyDead = S.enemyDead or {}    -- id -> true: dead in one of the games, so dead in both
S.spawnerById = S.spawnerById or {}
S.spawnTried = S.spawnTried or {}  -- id -> when we last asked its spawner to spawn

local function scanEnemies()
    local list, byId = {}, {}
    local spawners = FindAllOf("SHAISpawner")
    if spawners then
        for i = 1, #spawners do
            local sp = spawners[i]
            if sp:IsValid() then
                local path = sp:GetFullName():match("^%S+%s+(.+)$") or sp:GetFullName()
                local id = hashName(path)
                byId[id] = sp
                local actor = sp:GetSpawnedActor()
                if actor and actor:IsValid() then
                    local health = actor.healthComponent
                    if health and health:IsValid() then
                        list[#list + 1] = { id = id, actor = actor, health = health }
                    end
                end
            end
        end
    end
    S.enemies = list
    S.spawnerById = byId
end

-- An enemy died in the other game: it dies here too. The health component's own calls mark it
-- dead and switch its collision off, but on their own they can leave the body standing, so a
-- moment later a body that is not playing its death is simply taken out of sight.
local function killHere(pawn, e, st)
    local from = (S.avatar and S.avatar:IsValid()) and S.avatar or pawn
    pcall(function() e.health:ReceiveDamage(e.health:GetHealth() + 1, from) end)
    local dead = false
    pcall(function() dead = e.health:IsDead() end)
    if not dead then pcall(function() e.health:Kill() end) end
    pcall(function() st.hp = e.health:GetHealth() end)
    st.forced = nil
    st.tidyAt = os.clock() + 1.5
    log("an enemy the other player killed died here too")
end

local function tidyBody(e, st)
    st.tidyAt = nil
    local dying = false
    pcall(function() dying = e.actor.AnimComponent:IsInDeathState(true) end)
    if dying then return end
    pcall(function()
        e.actor:SetActorEnableCollision(false)
        e.actor:SetActorHiddenInGame(true)
    end)
end

-- The other game has a live enemy that does not exist here (a scene spawned it there, or only
-- that player walked into its area): have its spawner make it here as well.
local function spawnMissing(theirs, known)
    local now = os.clock()
    for id, t in pairs(theirs) do
        if t.hp > 0 and not known[id] and not S.enemyDead[id] and now - (S.spawnTried[id] or -100) > 10 then
            local sp = S.spawnerById[id]
            if sp and sp:IsValid() then
                local fresh = false
                pcall(function() fresh = sp._Spawned == 0 and sp._Enabled == true end)
                if fresh then
                    S.spawnTried[id] = now
                    local ok = pcall(function() sp:Spawn() end)
                    log(ok and "spawned an enemy that only the other player had" or "could not spawn an enemy the other player has")
                    S.enemiesDue = true   -- look for its actor on the next pass
                end
            end
        end
    end
end

local function findEnemy(id)
    for _, e in ipairs(S.enemies) do
        if e.id == id and e.actor:IsValid() then return e end
    end
    return nil
end

-- Send an enemy after the other player's body, or let it go back to its own judgement.
local function forceOntoAvatar(e, st, yes)
    local ctl = e.actor.Controller
    if not (ctl and ctl:IsValid()) then return end
    if yes then
        if st.forced or not (S.avatar and S.avatar:IsValid()) then return end
        local ok = pcall(function() ctl:SetForcedEnemy(S.avatar) end)
        if ok then
            st.forced = true
            log("an enemy now hunts the other player")
        end
    elseif st.forced then
        pcall(function() ctl:SetForcedEnemy(nil) end)
        pcall(function() ctl:ClearForceChase() end)
        st.forced = nil
        log("an enemy stopped hunting the other player")
    end
end

onRemoteEnemyDamage = function(pawn, id, amount)
    if not on("sync_enemies") then return end
    local e = findEnemy(id)
    if not e then return end      -- not loaded here; the host's health value catches it up later
    local st = S.enemyState[id]
    if not st then st = {} S.enemyState[id] = st end
    local from = (S.avatar and S.avatar:IsValid()) and S.avatar or pawn
    pcall(function() e.health:ReceiveDamage(amount, from) end)
    st.hp = e.health:GetHealth()   -- so we do not report this drop back as our own
end

local function hasPendingDamage(id)
    local prefix = "edmg " .. id .. " "
    for i = 1, #S.outbox do
        if S.outbox[i].text:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- ~10x a second.
local function enemiesTick(pawn)
    local me = pawn:K2_GetActorLocation()
    local pawnAddr = pawn:GetAddress()
    local newest = S.snaps[#S.snaps]
    local other = (newest and S.avatar and S.avatar:IsValid() and S.avatarVisible) and newest or nil
    local isHost = S.role ~= "join" or S.mirror
    local theirs = peer.enemies or {}
    local hunted = peer.hunted or {}
    local mineOut, deadOut, huntedOut, known = {}, {}, {}, {}

    for _, e in ipairs(S.enemies) do
        local actor = e.actor
        if actor:IsValid() and e.health:IsValid() then
            known[e.id] = true
            local loc = actor:K2_GetActorLocation()
            local dMe = dist3(me.X, me.Y, me.Z, loc.X, loc.Y, loc.Z)
            local dOther = other and dist3(other.x, other.y, other.z, loc.X, loc.Y, loc.Z) or math.huge
            local st = S.enemyState[e.id]
            local hp = e.health:GetHealth()
            local theirCopy = theirs[e.id]

            -- Dead in the other game means dead here, wherever it is. (Their packets list the
            -- dead ones near them, and every death is also sent once as a reliable event.)
            if hp > 0 and not S.mirror and (S.enemyDead[e.id] or (theirCopy and theirCopy.hp <= 0)) then
                if not st then st = {} S.enemyState[e.id] = st end
                S.enemyDead[e.id] = true
                if os.clock() - (st.killTried or -100) > 5 then   -- an enemy that cannot die yet is retried, not hammered
                    st.killTried = os.clock()
                    killHere(pawn, e, st)
                    hp = e.health:GetHealth()
                end
            end
            if st and st.tidyAt and os.clock() >= st.tidyAt then tidyBody(e, st) end

            if dMe < ENEMY_RANGE or dOther < ENEMY_RANGE or (st and st.forced) then
                if not st then st = {} S.enemyState[e.id] = st end

                -- damage we dealt here since the last look
                if st.hp and hp < st.hp and not S.mirror then
                    enqueue(string.format("edmg %s %d", e.id, math.ceil(st.hp - hp)))
                    if st.hp > 0 and hp <= 0 and not S.enemyDead[e.id] then
                        enqueue("edead " .. e.id)   -- we killed it; gets through even if they are far away
                    end
                end
                if hp <= 0 then S.enemyDead[e.id] = true end
                st.hp = hp

                local alive = hp > 0
                local huntsMe = false
                if alive then
                    pcall(function()
                        local arch = actor.Controller:GetArchEnemy()
                        huntsMe = arch ~= nil and arch:IsValid() and arch:GetAddress() == pawnAddr
                    end)
                end

                if isHost then
                    -- The host decides who each enemy is after.
                    if not alive or not other or dOther > ENEMY_RANGE then
                        forceOntoAvatar(e, st, false)
                    elseif st.forced then
                        -- back to us once we are clearly the closer one
                        if dMe + ENEMY_SWITCH < dOther then forceOntoAvatar(e, st, false) end
                    elseif huntsMe or hunted[e.id] then
                        -- Only enemies that are already alert in one of the games are redirected,
                        -- never sleeping ones. They go after the other player when only that
                        -- player's game has noticed them, or when that player is clearly closer.
                        if (hunted[e.id] and not huntsMe) or dOther + ENEMY_SWITCH < dMe then
                            forceOntoAvatar(e, st, true)
                        end
                    end
                else
                    -- The joiner follows the host's copy.
                    if huntsMe and alive and #huntedOut < ENEMY_MAX then huntedOut[#huntedOut + 1] = e.id end
                    local t = theirCopy
                    if t then
                        forceOntoAvatar(e, st, alive and t.target == "h")
                        if t.hp > 0 and alive and t.hp ~= hp and not hasPendingDamage(e.id) then
                            pcall(function() e.health:SetHealth(t.hp) end)
                            st.hp = e.health:GetHealth()
                        end
                        if alive then
                            local d = dist3(t.x, t.y, t.z, loc.X, loc.Y, loc.Z)
                            if d > 700 then
                                actor:K2_SetActorLocation({ X = t.x, Y = t.y, Z = t.z }, false, {}, true)
                            elseif d > 150 then
                                actor:K2_SetActorLocation({ X = loc.X + (t.x - loc.X) * 0.25, Y = loc.Y + (t.y - loc.Y) * 0.25,
                                    Z = loc.Z + (t.z - loc.Z) * 0.25 }, false, {}, false)
                            end
                        end
                    end
                end

                -- Both games list what they have, so the other one can spawn what it lacks and
                -- learn of deaths. Live enemies first; the dead fill what room is left.
                local entry = string.format("%s:%d:%d:%d:%d:%s", e.id, math.floor(loc.X), math.floor(loc.Y), math.floor(loc.Z),
                    math.floor(hp), (isHost and st.forced) and "j" or (huntsMe and "h" or "n"))
                if alive then mineOut[#mineOut + 1] = entry else deadOut[#deadOut + 1] = entry end
            end
        end
    end
    while #mineOut > ENEMY_MAX do mineOut[#mineOut] = nil end
    for i = 1, #deadOut do
        if #mineOut >= ENEMY_MAX + 4 then break end
        mineOut[#mineOut + 1] = deadOut[i]
    end
    if not S.mirror then spawnMissing(theirs, known) end
    S.myEnemies = (#mineOut > 0) and table.concat(mineOut, " ") or nil
    S.myHunted = (#huntedOut > 0) and table.concat(huntedOut, " ") or nil
end

onRemoteEnemyDead = function(id)
    if not on("sync_enemies") then return end
    S.enemyDead[id] = true   -- the next enemy pass kills our copy, now or whenever it shows up
end

-- ================================================================ friendly fire

-- Optional, and both players must enable it. The attacker's game decides whether an attack hit
-- the other player's body as drawn on the attacker's screen, and sends a reliable event; the
-- victim's game applies the damage through the game's own "player was hit" path.
--   melee: one hit  = ff_hit_damage (about one enemy hit)
--   shot:  one shot = twice that
-- Known limits: shots are tested along the aim line without checking for walls in between, and
-- melee is judged by reach and facing when the swing ends.

local BODY_RADIUS, BODY_HEIGHT = 40, 180
local MELEE_REACH = 190

local function sendFriendlyFire(pawn, how, dirX, dirY)
    local base = tonumber(cfg.ff_hit_damage) or 10
    if base < 1 then base = 1 elseif base > 100 then base = 100 end
    local amount = (how == "shot") and base * 2 or base
    local text = string.format("ff %s %d %d %d", how, math.floor(amount + 0.5), math.floor(dirX * 100), math.floor(dirY * 100))
    if S.mirror then
        onRemoteFriendlyFire(pawn, how, amount, dirX, dirY)   -- solo test: hitting your copy hurts you
    else
        enqueue(text)
    end
    log("friendly fire: your " .. how .. " hit the other player (" .. math.floor(amount + 0.5) .. ")")
end

onRemoteFriendlyFire = function(pawn, how, amount, dirX, dirY)
    if not on("friendly_fire") then return end
    local damageClass = StaticFindObject(how == "shot" and "/Script/SHProto.SHFirearmBaseDamage" or "/Script/SHProto.SHMeleeBaseDamage")
    local from = (S.avatar and S.avatar:IsValid()) and S.avatar or pawn
    -- Measured in game: the combat component's ReceiveDamage does not change health (it handles
    -- the reaction), the health component's does. So call both: reaction first, then the loss.
    pcall(function() pawn.Combat:ReceiveDamage(amount, from, { X = dirX, Y = dirY, Z = 0 }, damageClass) end)
    local ok, err = pcall(function() pawn.Health:ReceiveDamage(amount, from, false) end)
    if not ok then warnOnce("ffdmg:" .. tostring(err), "could not apply friendly fire damage: " .. tostring(err)) end
    log("friendly fire: the other player's " .. how .. " hit you (" .. math.floor(amount + 0.5) .. ")")
end

-- Does the line from `o` along unit direction `d`, up to `maxDist`, pass through the avatar?
local function rayHitsAvatar(o, d, maxDist)
    local a = S.avatar:K2_GetActorLocation()   -- feet
    local scale = ((tonumber(cfg.other_player_scale) or 100) / 100) * (S.pelvisScale or 1)
    local height, radius = BODY_HEIGHT * scale, BODY_RADIUS * scale
    -- closest approach between the ray and the vertical segment from the feet to the head
    local wx, wy, wz = o.X - a.X, o.Y - a.Y, o.Z - a.Z
    local b = d.Z
    local dw = d.X * wx + d.Y * wy + d.Z * wz
    local denom = 1 - b * b
    local s = (denom > 1e-6) and ((wz - b * dw) / denom) or wz
    if s < 0 then s = 0 elseif s > height then s = height end
    local t = d.X * (a.X - o.X) + d.Y * (a.Y - o.Y) + d.Z * (a.Z + s - o.Z)
    if t <= 0 or t > maxDist then return false end
    local px, py, pz = o.X + d.X * t - a.X, o.Y + d.Y * t - a.Y, o.Z + d.Z * t - (a.Z + s)
    return px * px + py * py + pz * pz <= radius * radius
end

local function onShotFired(pawn, weapon)
    if not (S.avatar and S.avatar:IsValid() and S.avatarVisible) then return end
    local o, v = weapon:GetStartTraceLoc(), weapon:GetPerfectShootVector()
    local dx, dy, dz = v.X, v.Y, v.Z
    if dx * dx + dy * dy + dz * dz > 4 then dx, dy, dz = dx - o.X, dy - o.Y, dz - o.Z end   -- it was an end point
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 1e-4 then return end
    local d = { X = dx / len, Y = dy / len, Z = dz / len }
    local maxDist = 5000
    pcall(function() if weapon.MaxShootDistance > 100 then maxDist = weapon.MaxShootDistance end end)
    if rayHitsAvatar(o, d, maxDist) then sendFriendlyFire(pawn, "shot", d.X, d.Y) end
end

-- A shot is recognised by the loaded-ammo total dropping; reloads raise it.
local function friendlyFireTick(pawn)
    if not (S.rangedComp and S.rangedComp:IsValid()) then
        S.rangedComp = FindFirstOf("SHRangedCmbSubcomp")
        S.ammoTotal = nil
        if not (S.rangedComp and S.rangedComp:IsValid()) then return end
    end
    local total = 0
    S.rangedComp.WeaponsAmmoCounts:ForEach(function(_, v) total = total + v:get() end)
    if S.ammoTotal and total < S.ammoTotal then
        local weapon = S.rangedComp:GetEquippedRangedWeapon()
        if weapon and weapon:IsValid() then onShotFired(pawn, weapon) end
    end
    S.ammoTotal = total
end

-- Called when one of our melee swings ends (hook below).
local function onMeleeSwing()
    if not on("friendly_fire") then return end
    local pawn = getPawn()
    if not (pawn and S.avatar and S.avatar:IsValid() and S.avatarVisible) then return end
    local p, a = pawn:K2_GetActorLocation(), S.avatar:K2_GetActorLocation()
    local dx, dy = a.X - p.X, a.Y - p.Y
    local flat = math.sqrt(dx * dx + dy * dy)
    if flat > MELEE_REACH or flat < 1 then return end
    if math.abs((a.Z + 90) - p.Z) > 130 then return end           -- on another floor
    local yaw = pawn:K2_GetActorRotation().Yaw / RAD
    local facing = (math.cos(yaw) * dx + math.sin(yaw) * dy) / flat  -- 1 = dead ahead
    if facing < 0.35 then return end                                -- more than ~70 degrees off
    sendFriendlyFire(pawn, "melee", dx / flat, dy / flat)
end

local MELEE_HOOK = "/Script/SHProto.SHMeleeCmbSubcomp:OnMeleeAttackEnd"
local function tryInstallMeleeHook()
    if S.meleeHooked or S.meleeHookFailed then return end
    local ok, err = pcall(RegisterHook, MELEE_HOOK, function()
        local impl = SH2CoopMod.impl
        if impl and impl.onMelee then pcall(impl.onMelee) end
    end)
    if ok then
        S.meleeHooked = true
        log("melee hook installed")
    else
        S.meleeHookFailed = true
        log("melee hook could not be installed, melee friendly fire is unavailable: " .. tostring(err))
    end
end

-- ================================================================ messaging

local function readRole()
    local f = io.open(ROLE_FILE, "r")
    if not f then return end
    local r = (f:read("a") or ""):match("%a+")
    f:close()
    if (r == "host" or r == "join") and r ~= S.role then
        S.role = r
        log("role: " .. r)
    end
end

local function writeOut(pawn)
    local loc = pawn:K2_GetActorLocation()
    local rot = pawn:K2_GetActorRotation()
    local vel = pawn:GetVelocity()
    local speed = math.sqrt(vel.X * vel.X + vel.Y * vel.Y)
    S.seq = S.seq + 1
    local lines = { string.format("S %s %d %.1f %.1f %.1f %.1f %.1f %d %s %d",
        S.session, S.seq, loc.X, loc.Y, loc.Z, rot.Yaw, speed, peer.applied, S.role,
        math.floor(os.clock() * 1000)) }

    local okPose, pose = pcall(capturePose, pawn)
    if okPose then
        S.myPose = pose
        lines[#lines + 1] = "P " .. table.concat(pose, " ")
    else
        warnOnce("cap:" .. tostring(pose), "pose capture error: " .. tostring(pose))
    end

    if S.tickCount % HELD_EVERY == 0 or not S.myHeld then
        local okHeld, held = pcall(collectHeld, pawn)
        if okHeld then S.myHeld = held else warnOnce("held:" .. tostring(held), "held items error: " .. tostring(held)) end
    end
    if S.myHeld then lines[#lines + 1] = "H " .. S.myHeld end
    if S.myDoors and on("sync_doors") then lines[#lines + 1] = "D " .. S.myDoors end
    lines[#lines + 1] = "C " .. (S.cutPlaying or "0")
    if S.myPushing and on("sync_pushables") then lines[#lines + 1] = "U " .. S.myPushing end
    if on("sync_enemies") then
        if S.myEnemies then lines[#lines + 1] = "N " .. S.myEnemies end   -- host: where its enemies are
        if S.myHunted then lines[#lines + 1] = "T " .. S.myHunted end     -- joiner: which ones hunt it
    end

    local okFl, fl = pcall(flashlightState, pawn)
    if okFl then lines[#lines + 1] = fl else warnOnce("fl:" .. tostring(fl), "flashlight read error: " .. tostring(fl)) end
    lines[#lines + 1] = "M " .. (MODELS[cfg.my_model] and cfg.my_model or "james")

    for i = 1, #S.outbox do
        lines[#lines + 1] = "E " .. S.outbox[i].id .. " " .. S.outbox[i].text
    end
    local f = io.open(OUT_FILE, "w")
    if f then
        f:write(table.concat(lines, "\n"))
        f:close()
    else
        warnOnce("out", "cannot write " .. OUT_FILE)
    end
    return loc, rot
end

local function onPeerConnected(pawn, isNewSession)
    log("peer connected (session " .. tostring(peer.session) .. ")")
    -- Whatever queued up while we played alone belongs to the time before this session.
    if isNewSession then
        for i = #S.outbox, 1, -1 do S.outbox[i] = nil end
    end
    -- Only a peer that just started needs the whole inventory. After a short network dropout
    -- the unacknowledged events on both sides are still queued and catch them up.
    if S.role == "host" and isNewSession and on("share_inventory") and on("host_inventory_wins") then
        sendFullInventory(pawn)
    end
end

-- Turn the sender's clock into ours, smoothing out network jitter.
local function peerTime(senderMs, now)
    if not senderMs then return now end
    local st = senderMs / 1000
    local raw = now - st
    if not peer.clockOffset or math.abs(raw - peer.clockOffset) > 1.0 then
        peer.clockOffset = raw
    else
        peer.clockOffset = peer.clockOffset + 0.05 * (raw - peer.clockOffset)
    end
    return st + peer.clockOffset
end

local function readIn(pawn)
    local f = io.open(IN_FILE, "r")
    if not f then return end
    local text = f:read("a")
    f:close()
    if not text or text == "" then return end

    local now = os.clock()
    local first = true
    local loopback = false
    local snap = nil
    local doorsSeen, enemiesSeen, huntedSeen, pushingSeen = {}, {}, {}, {}
    for line in text:gmatch("[^\r\n]+") do
        if first then
            first = false
            local sid, pseq, x, y, z, yaw, _, ack =
                line:match("^S (%x+) (%d+) (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+) (%d+)")
            if not sid then return end
            if pseq == peer.lastSeq and sid == peer.session then return end -- nothing new
            local senderMs = tonumber(line:match("%s(%d+)$"))

            if sid == S.session then
                -- Our own packets came back (relay pointed at this PC): show them as an avatar
                -- standing beside us, but never apply our own events to ourselves.
                loopback = true
                if peer.session ~= sid then peer.session = sid peer.clockOffset = nil end
                peer.lastSeq = pseq
                peer.lastTime = now
                snap = { t = peerTime(senderMs, now), x = tonumber(x) + MIRROR_OFFSET, y = tonumber(y), z = tonumber(z), yaw = tonumber(yaw) }
            else
                local newPeer = sid ~= peer.session
                if newPeer then
                    peer.session = sid
                    peer.applied = 0
                    peer.clockOffset = nil
                    S.snaps = {}
                end
                peer.lastSeq = pseq
                peer.lastTime = now
                snap = { t = peerTime(senderMs, now), x = tonumber(x), y = tonumber(y), z = tonumber(z), yaw = tonumber(yaw) }

                -- drop our events they have acknowledged
                local a = tonumber(ack)
                while #S.outbox > 0 and S.outbox[1].id <= a do table.remove(S.outbox, 1) end

                if newPeer or not peer.connected then
                    peer.connected = true
                    onPeerConnected(pawn, newPeer)
                end
            end
        elseif line:sub(1, 2) == "P " then
            local pose = {}
            for v in line:gmatch("%-?%d+") do pose[#pose + 1] = tonumber(v) end
            if snap then snap.pose = pose end
        elseif line:sub(1, 1) == "H" then
            peer.held = line:sub(3)
        elseif line:sub(1, 2) == "F " then
            local flOn, fp, fy = line:match("^F (%d) (%-?%d+) (%-?%d+)")
            if snap and flOn then snap.fl, snap.fp, snap.fy = tonumber(flOn), tonumber(fp), tonumber(fy) end
        elseif line:sub(1, 2) == "M " then
            peer.model = line:match("^M (%w+)")
        elseif line:sub(1, 2) == "D " then
            for id, angle in line:gmatch("(%x+):(%-?%d+)") do doorsSeen[id] = tonumber(angle) / 10 end
        elseif line:sub(1, 2) == "U " and not loopback then
            for id, x, y, z in line:gmatch("(%x+):(%-?%d+):(%-?%d+):(%-?%d+)") do
                pushingSeen[id] = { tonumber(x), tonumber(y), tonumber(z) }
            end
        elseif line:sub(1, 2) == "N " and not loopback then
            for id, x, y, z, hp, target in line:gmatch("(%x+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%a)") do
                enemiesSeen[id] = { x = tonumber(x), y = tonumber(y), z = tonumber(z), hp = tonumber(hp), target = target }
            end
        elseif line:sub(1, 2) == "T " and not loopback then
            for id in line:sub(3):gmatch("%x+") do huntedSeen[id] = true end
        elseif line:sub(1, 2) == "C " and not loopback then
            local cut = line:match("^C (%x+)") or "0"
            if peer.cut and peer.cut ~= "0" and cut == "0" and S.role == "join" then
                S.regroupAt = os.clock() + 0.7     -- the host's cutscene just ended
            end
            peer.cut = cut
        elseif not loopback then
            local id, body = line:match("^E (%d+) (.+)$")
            id = tonumber(id)
            if id and id > peer.applied then
                local ok, err = pcall(handleEvent, pawn, body)
                if not ok then log("event failed: " .. tostring(err)) end
                peer.applied = id
            end
        end
    end
    if snap then
        pushSnap(snap)
        if not loopback then
            peer.doors = doorsSeen       -- the doors they are driving right now
            peer.enemies = enemiesSeen   -- host's enemies (empty when they are the joiner)
            peer.hunted = huntedSeen     -- enemies hunting them in their own game
            peer.pushing = pushingSeen   -- objects they are pushing right now
        end
    end
end

-- ================================================================ dev channel
-- Development aid: if ipc\run.lua appears, run it on the game thread and write whatever it
-- prints with P(...) to ipc\result.txt. Lets the game be inspected while it runs.

local function runCmd()
    local f = io.open(CMD_FILE, "r")
    if not f then return end
    local src = f:read("a")
    f:close()
    os.remove(CMD_FILE)

    local buf = {}
    local function flush(final)
        local o = io.open(RES_FILE, "w")
        if o then
            o:write(table.concat(buf, "\n"))
            if final then o:write("\n<<END>>") end
            o:close()
        end
    end
    local function P(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
        buf[#buf + 1] = table.concat(t, " ")
        flush(false)   -- written as we go, so a crash still leaves the lines before it
    end
    local env = setmetatable({ P = P, UEHelpers = UEHelpers, S = S, getPawn = getPawn, enqueue = enqueue },
        { __index = _G })
    local chunk, err = load(src, "cmd", "t", env)
    if not chunk then
        P("COMPILE ERROR: " .. tostring(err))
    else
        local ok, e = pcall(chunk)
        if not ok then P("RUNTIME ERROR: " .. tostring(e)) end
    end
    flush(true)
end

-- ================================================================ joining from the main menu

-- The joiner gets an extra entry in the game's main menu. It is greyed out until the host is
-- actually in the game. Pressing it asks the launcher for the host's save: the host's game
-- writes a fresh save into a spare slot, the launchers copy that file across, and this game
-- loads it. The joiner then appears in the host's world, next to them.

local COOP_SLOT = 9   -- a slot the game's own menus never fill; both PCs use the same number
local REQUEST_FILE = DIR .. "\\request.txt"       -- us -> our launcher: "getsave"
local READY_FILE = DIR .. "\\save_ready.txt"      -- our launcher -> us: "ok <slot>" or "err <why>"
local SAVED_FILE = DIR .. "\\coopsave_done.txt"   -- host game -> host launcher: "<slot>"

local MENU_LABELS = {
    join = { "Join co-op", "Совместная игра" },
    wait = { "Join co-op (waiting for host)", "Совместная игра (ждём хоста)" },
    busy = { "Joining...", "Подключение..." },
    fail = { "Could not join, try again", "Не получилось, попробуй ещё раз" },
}

-- Host, in game: the launcher asked for a save the joiner can load.
local function coopSave(pawn)
    local st = gameStatics()
    if not st then return end
    S.savingForPeer = true   -- this save is for the joiner; do not announce it as a normal save
    local ok, err = pcall(function() st:MakeFullSave(pawn:GetWorld(), COOP_SLOT, "Co-op", false, false) end)
    S.savingForPeer = nil
    if ok then
        local f = io.open(SAVED_FILE, "w")
        if f then f:write(tostring(COOP_SLOT)) f:close() end
        log("saved for the joiner (slot " .. COOP_SLOT .. ")")
    else
        log("could not save for the joiner: " .. tostring(err))
    end
end

local MENU_ENTRY = "JoinCoop_but"
local BUTTON_EVENTS = { "OnClicked", "OnPressed", "OnReleased", "OnHovered", "OnUnhovered", "OnFocused", "OnUnfocused",
    "OnKeyDownEvent", "OnKeyUpEvent" }
-- Lua cannot be a click handler itself. So the entry's click is wired to a harmless function
-- that every menu button has, and we listen for that function being called on our entry.
local CLICK_FUNCTION = "ResetScrollState"

local function onMenuClick(widget)
    local btn = S.menuBtn
    if btn and btn:IsValid() and widget and widget:IsValid() and widget:GetAddress() == btn:GetAddress() then
        S.menuClicked = true   -- acted on by the next menu tick
    end
end

local function tryInstallMenuClickHook()
    if S.menuClickHook ~= nil then return end
    S.menuClickHook = pcall(RegisterHook, "/Script/UCW.TextButton:" .. CLICK_FUNCTION, function(self)
        local impl = SH2CoopMod.impl
        if impl and impl.onMenuClick then pcall(impl.onMenuClick, self:get()) end
    end)
end

local function createMenuButton(menu)
    local template = menu.Load_but
    if not (template and template:IsValid()) then return nil end
    local list = template:GetParent()
    if not (list and list:IsValid()) then return nil end

    local btn
    for i = 0, list:GetChildrenCount() - 1 do   -- still there from before a script reload?
        local child = list:GetChildAt(i)
        if child:IsValid() and child:GetFName():ToString() == MENU_ENTRY then btn = child end
    end
    if not btn then
        -- An engine-made copy of the menu's own "Load game" entry: same font, colours, sounds, size.
        btn = StaticConstructObject(template:GetClass(), template:GetOuter(), FName(MENU_ENTRY), 0, 0, false, false, template)
        if not (btn and btn:IsValid()) then return nil end
        -- The copy also inherited "open the load screen" as its click. That has to go before it is shown.
        for _, name in ipairs(BUTTON_EVENTS) do pcall(function() btn[name]:Clear() end) end
        local clean = false
        pcall(function() clean = #btn.OnClicked:GetBindings() == 0 end)
        if not clean then
            S.menuBroken = true
            log("could not prepare the co-op menu entry; the main menu is left as it is")
            return nil
        end
        local slot = list:AddChild(btn)
        pcall(function()
            local src = template.Slot
            slot:SetPadding(src.Padding)
            slot:SetHorizontalAlignment(src.HorizontalAlignment)
            slot:SetVerticalAlignment(src.VerticalAlignment)
        end)
        log("added the co-op entry to the main menu")
    end

    tryInstallMenuClickHook()
    S.menuClickWired = S.menuClickHook and pcall(function()
        btn.OnClicked:Clear()
        btn.OnClicked:Add(btn, FName(CLICK_FUNCTION))
    end)
    if not S.menuClickWired then log("co-op menu entry: watching the button instead of its click event") end
    S.menuRussian, S.menuLabel, S.menuEnabled, S.menuPressed, S.menuClicked = nil, nil, nil, false, nil
    return btn
end

local function setMenuButton(key, enabled)
    local btn = S.menuBtn
    if S.menuLabel ~= key then
        S.menuLabel = key
        local pair = MENU_LABELS[key]
        pcall(function() btn:SetText(FText(S.menuRussian and pair[2] or pair[1])) end)
    end
    if S.menuEnabled ~= enabled then
        S.menuEnabled = enabled
        pcall(function() btn:SetIsEnabled(enabled) end)
    end
end

-- Runs while there is no player, i.e. in the main menu and on loading screens.
local function menuTick()
    local now = os.clock()
    S.menuTicks = (S.menuTicks or 0) + 1
    if S.menuTicks % 30 == 1 then readRole() readConfig() end

    if not (S.menu and S.menu:IsValid()) then
        S.menuBtn = nil
        if S.menuTicks % 15 ~= 2 then return end
        S.menu = FindFirstOf("SHMainMenuWidget")
        if not (S.menu and S.menu:IsValid()) then return end
    end
    if S.role ~= "join" then   -- the host starts or loads a game the normal way
        if S.menuBtn and S.menuBtn:IsValid() then pcall(function() S.menuBtn:SetVisibility(1) end) end   -- 1 = collapsed
        return
    end
    if not (S.menuBtn and S.menuBtn:IsValid()) then
        if S.menuBroken then return end
        S.menuBtn = createMenuButton(S.menu)
        if not S.menuBtn then return end
    end
    pcall(function() S.menuBtn:SetVisibility(0) end)   -- 0 = visible

    -- The label follows the game's language: Russian when the menu is in Russian, English for
    -- every other language. Checked again now and then, since the language can be changed in
    -- the settings without leaving the menu.
    if S.menuRussian == nil or S.menuTicks % 30 == 3 then
        local russian = false
        pcall(function() russian = S.menu.Load_but:GetText():ToString():find("[\208\209]") ~= nil end)
        if russian ~= S.menuRussian then S.menuRussian, S.menuLabel = russian, nil end
    end

    -- Is the host in the game? Their game only sends while they are, so fresh packets mean yes.
    local f = io.open(IN_FILE, "r")
    if f then
        local seq = (f:read("l") or ""):match("^S %x+ (%d+)")
        f:close()
        if seq and seq ~= S.menuHostSeq then
            if S.menuHostSeq ~= nil then S.menuHostTime = now end   -- the first look only sets the baseline
            S.menuHostSeq = seq
        end
    end
    local hostInGame = S.menuHostTime ~= nil and now - S.menuHostTime < 3

    if S.join then
        -- waiting for our launcher to fetch the host's save
        local r = io.open(READY_FILE, "r")
        local answer = r and r:read("a") or nil
        if r then r:close() os.remove(READY_FILE) end
        local slot = answer and answer:match("^ok (%d+)")
        if slot then
            S.join = nil
            log("host's save received; loading it")
            setMenuButton("busy", false)
            S.joinedViaMenu = true
            pcall(function() S.menu:LoadSavedGame(tonumber(slot), nil, 0) end)
            return
        elseif answer or now - S.join > 40 then
            S.join = nil
            S.joinFailedUntil = now + 4
            log("could not get the host's save: " .. (answer and (answer:match("^err%s+(.-)%s*$") or answer) or "no answer from the launcher"))
        else
            setMenuButton("busy", false)
            return
        end
    end

    if S.joinFailedUntil and now < S.joinFailedUntil then
        setMenuButton("fail", false)
    elseif hostInGame then
        setMenuButton("join", true)
    else
        setMenuButton("wait", false)
    end

    -- A click arrives through the hook; without it, notice the button going down (30 looks a second).
    local pressed = false
    if not S.menuClickWired then pcall(function() pressed = S.menuBtn:IsPressed() end) end
    local clicked = S.menuClicked or (pressed and not S.menuPressed)
    S.menuClicked = nil
    if clicked and S.menuEnabled then
        os.remove(READY_FILE)
        local q = io.open(REQUEST_FILE, "w")
        if q then
            q:write("getsave")
            q:close()
            S.join = now
            setMenuButton("busy", false)
            log("asked the launcher for the host's save")
        else
            S.joinFailedUntil = now + 4
            log("could not ask the launcher for the host's save")
        end
    end
    S.menuPressed = pressed
end

-- ================================================================ entry points

-- ~30x a second, called by main.lua: measure ourselves and exchange messages.
local function tick()
    pcall(runCmd)

    local pawn = getPawn()
    if not pawn then
        S.avatar = nil
        S.snaps = {}
        S.known = nil   -- the inventory is rebuilt on load; start over when the player is back
        S.doors, S.doorState = {}, {}   -- doors are reloaded with the level, so forget what we held
        S.cutPlayers, S.cutPlaying, S.cutRequest, S.cutExpected, S.regroupAt = {}, nil, nil, nil, nil
        S.itemState, S.takenRemote, S.itemSeen, S.itemSince, S.doorSeen = {}, {}, nil, nil, nil
        S.enemies, S.enemyState, S.enemyDead, S.spawnerById, S.spawnTried = {}, {}, {}, {}, {}
        S.puzzleState, S.solvedRemote, S.puzzleSeen, S.puzzleSince = {}, {}, nil, nil
        S.pushables, S.pushState, S.pushRemote, S.pushSeen = {}, {}, {}, nil
        S.pawnGone = true   -- menu, loading screen or death: the next time we exist, a load has finished
        local okMenu, errMenu = pcall(menuTick)
        if not okMenu then warnOnce("menu:" .. tostring(errMenu), "main menu error: " .. tostring(errMenu)) end
        return
    end
    S.menu, S.menuBtn, S.join = nil, nil, nil   -- in game now; the menu widget is gone
    -- While a save is loading the pawn exists before its parts do; wait until it is whole.
    local whole = pcall(function() assert(pawn.Mesh:IsValid() and pawn.Items:IsValid() and pawn.Health:IsValid()) end)
    if not whole then return end
    S.tickCount = S.tickCount + 1

    if S.pawnGone then
        S.pawnGone = nil
        local ok, err = pcall(onLoadedHere, pawn)
        if not ok then warnOnce("loaded:" .. tostring(err), "load sync error: " .. tostring(err)) end
    end
    if on("sync_saves") then tryInstallSaveHooks() end
    if S.regroupAfterLoad then
        local now = os.clock()
        if now > S.regroupAfterLoad + 30 then
            S.regroupAfterLoad = nil                       -- the host never showed up; stay put
        elseif now >= S.regroupAfterLoad and #S.snaps > 0 and now - peer.lastTime < 2 and (peer.cut or "0") == "0" then
            S.regroupAfterLoad = nil
            S.regroupRequested = true                      -- carried out further down this tick
        end
    end

    if S.releaseMoveAt and os.clock() >= S.releaseMoveAt then
        S.releaseMoveAt = nil
        pcall(function() pawn.CharacterMovement:SetMovementMode(1, 0) end)   -- 1 = walking
    end
    if S.tickCount % 30 == 1 then readRole() end

    if S.tickCount % 30 == 1 then readConfig() end

    if not on("share_inventory") then
        S.known = nil
    elseif S.tickCount % INVENTORY_EVERY == 0 then
        local ok, err = pcall(pollInventory, pawn)
        if not ok then warnOnce("inv:" .. tostring(err), "inventory poll error: " .. tostring(err)) end
    end

    -- Measure and send ourselves at the configured rate (the tick itself runs at up to 30 Hz).
    local hz = tonumber(cfg.send_rate_hz) or 30
    if hz < 5 then hz = 5 elseif hz > 30 then hz = 30 end
    local sendEvery = math.floor(30 / hz + 0.5)
    if S.tickCount % sendEvery == 0 then
        local loc, rot = writeOut(pawn)
        if S.mirror then
            -- Solo test: feed our own measurements through the same path a real peer would use.
            local now = os.clock()
            peer.lastTime = now
            peer.held = S.myHeld
            peer.model = MODELS[cfg.my_model] and cfg.my_model or "james"
            local fl = S.myFlash or { 0, 0, 0 }
            pushSnap({ t = now, x = loc.X + MIRROR_OFFSET, y = loc.Y, z = loc.Z, yaw = rot.Yaw, pose = S.myPose,
                fl = fl[1], fp = fl[2], fy = fl[3] })
        end
    end
    if not S.mirror then readIn(pawn) end

    if on("sync_doors") then
        if S.tickCount % 90 == 3 then
            local ok, err = pcall(scanDoors)
            if not ok then warnOnce("doorscan:" .. tostring(err), "door scan error: " .. tostring(err)) end
        end
        if S.tickCount % 3 == 0 then
            local ok, err = pcall(doorsTick, pawn)
            if not ok then warnOnce("doors:" .. tostring(err), "door sync error: " .. tostring(err)) end
        end
    else
        S.myDoors = nil
    end

    if on("sync_enemies") then
        if S.tickCount % 60 == 11 or S.enemiesDue then
            S.enemiesDue = nil
            local ok, err = pcall(scanEnemies)
            if not ok then warnOnce("enemyscan:" .. tostring(err), "enemy scan error: " .. tostring(err)) end
        end
        if S.tickCount % 3 == 1 then
            local ok, err = pcall(enemiesTick, pawn)
            if not ok then warnOnce("enemies:" .. tostring(err), "enemy sync error: " .. tostring(err)) end
        end
    else
        S.myEnemies, S.myHunted = nil, nil
    end

    if on("sync_pushables") then
        if S.tickCount % 60 == 31 then
            local ok, err = pcall(scanPushables)
            if not ok then warnOnce("pushscan:" .. tostring(err), "pushable scan error: " .. tostring(err)) end
        end
        if S.tickCount % 3 == 2 then
            local ok, err = pcall(pushablesTick, pawn)
            if not ok then warnOnce("push:" .. tostring(err), "pushable sync error: " .. tostring(err)) end
        end
    else
        S.myPushing = nil
    end

    -- "go to the other player": F7, or the launcher's button
    tryInstallRegroupKey()
    if S.tickCount % 10 == 7 then
        local word = readLauncherCommand()
        if word == "regroup" then
            S.regroupRequested = true
        elseif word == "coopsave" then
            local ok, err = pcall(coopSave, pawn)
            if not ok then log("could not save for the joiner: " .. tostring(err)) end
        end
    end
    if S.regroupRequested then
        S.regroupRequested = nil
        local ok, err = pcall(regroupNow, pawn)
        if not ok then log("could not go to the other player: " .. tostring(err)) end
    end

    if on("sync_puzzles") and (S.puzzlesDue or S.tickCount % 60 == 23) then
        S.puzzlesDue = nil
        local ok, err = pcall(puzzlesTick, pawn)
        if not ok then warnOnce("puzzles:" .. tostring(err), "puzzle sync error: " .. tostring(err)) end
    end

    if on("sync_cutscenes") and S.tickCount % 10 == 5 then
        local ok, err = pcall(cutsceneTick, pawn)
        if not ok then warnOnce("cut:" .. tostring(err), "cutscene sync error: " .. tostring(err)) end
    end

    if on("share_inventory") and (S.itemsDue or S.tickCount % 60 == 7) then
        S.itemsDue = nil
        local ok, err = pcall(itemsTick, pawn)
        if not ok then warnOnce("items:" .. tostring(err), "pickup sync error: " .. tostring(err)) end
    end

    if on("friendly_fire") then
        tryInstallMeleeHook()
        local ok, err = pcall(friendlyFireTick, pawn)
        if not ok then warnOnce("ff:" .. tostring(err), "friendly fire error: " .. tostring(err)) end
    end

    -- Creating components and swapping meshes is kept out of the per-frame path on purpose.
    local okMine, errMine = pcall(manageSelf, pawn)
    if not okMine then warnOnce("manageSelf:" .. tostring(errMine), "own model setup error: " .. tostring(errMine)) end

    if S.avatar and S.avatar:IsValid() then
        local ok, err = pcall(applyModel, pawn)
        if not ok then warnOnce("model:" .. tostring(err), "model apply error: " .. tostring(err)) end

        ok, err = pcall(applyHeld, on("show_held_items") and (peer.held or "") or "")
        if not ok then warnOnce("applyHeld:" .. tostring(err), "held items apply error: " .. tostring(err)) end

        local newest = S.snaps[#S.snaps]
        if on("sync_flashlight") and newest and newest.fl == 1 then
            ok, err = pcall(ensureLight, pawn)
            if not ok then warnOnce("light:" .. tostring(err), "flashlight beam error: " .. tostring(err)) end
        end
        if S.lightComp and S.lightComp:IsValid() then
            if S.lightShadows ~= cfg.flashlight_shadows then
                S.lightShadows = cfg.flashlight_shadows
                pcall(function() S.lightComp:SetCastShadows(on("flashlight_shadows")) end)
            end
            if S.lightBrightness ~= cfg.flashlight_brightness then
                S.lightBrightness = cfg.flashlight_brightness
                local pct = tonumber(cfg.flashlight_brightness) or 100
                if pct < 0 then pct = 0 elseif pct > 400 then pct = 400 end
                pcall(function() S.lightComp:SetIntensity((S.lightBase or 48) * pct / 100) end)
            end
        end

        ok, err = pcall(updateCollision, pawn)
        if not ok then warnOnce("collision:" .. tostring(err), "collision setup error: " .. tostring(err)) end

        if S.avatarScale ~= cfg.other_player_scale then
            S.avatarScale = cfg.other_player_scale
            local s = (tonumber(cfg.other_player_scale) or 100) / 100
            if s < 0.25 then s = 0.25 elseif s > 3 then s = 3 end
            pcall(function() S.avatar:SetActorScale3D({ X = s, Y = s, Z = s }) end)
        end
    end

    if peer.connected and (os.clock() - peer.lastTime) > staleSeconds() then
        peer.connected = false
        log("peer lost")
    end
end

local function onKey(key)
    if key == "F7" then
        S.regroupRequested = true   -- carried out on the game thread by the next tick
        return
    end
    if key == "F9" then
        S.mirror = not S.mirror
        S.snaps = {}
        log("mirror test " .. (S.mirror and "ON" or "OFF"))
    end
end

-- Called on the game thread once per rendered frame, from the hook below.
local function onFrame()
    if S.gen ~= myGen then return end
    local now = os.clock()
    if S.lastFrame and now - S.lastFrame < 0.002 then return end   -- several anim instances can fire
    S.lastFrame = now
    local ok, err = pcall(frame)
    if not ok then warnOnce("frame:" .. tostring(err), "frame error: " .. tostring(err)) end
end

-- Per-frame driver: James's animation blueprint updates once per rendered frame on the game
-- thread, so we ride on it. (A fast LoopAsync timer was tried first and corrupted Lua state:
-- its callbacks run on another OS thread.) The hook is installed once per game session and
-- always calls whatever core is currently loaded.
local FRAME_HOOK = "/Game/Game/Characters/Humans/JamesSunderland/Animation/AnimationBlueprints/CH_JamesAnimBP.CH_JamesAnimBP_C:BlueprintUpdateAnimation"
local function tryInstallFrameHook()
    if S.frameHooked then return end
    local ok, err = pcall(RegisterHook, FRAME_HOOK, function()
        local impl = SH2CoopMod.impl
        if impl and impl.onFrame then impl.onFrame() end
    end)
    if ok then
        S.frameHooked = true
        log("per-frame hook installed")
    else
        warnOnce("hook:" .. tostring(err), "per-frame hook not installed yet: " .. tostring(err))
    end
end

-- The hook only fires while James's animation runs. Before it is installed, and whenever it
-- goes quiet (game paused or in the background, some cutscenes), draw from the 30 Hz tick
-- instead so nothing freezes half set up.
local function tickAndDraw()
    tick()
    if not S.frameHooked and S.tickCount % 30 == 2 and getPawn() then tryInstallFrameHook() end
    if not S.frameHooked or os.clock() - (S.lastFrame or 0) > 0.25 then
        local ok, err = pcall(frame)
        if not ok then warnOnce("frame:" .. tostring(err), "frame error: " .. tostring(err)) end
    end
end

return { version = VERSION, tick = tickAndDraw, onKey = onKey, onFrame = onFrame, onMelee = onMeleeSwing,
    onLocalSave = onLocalSave, onMenuClick = onMenuClick }

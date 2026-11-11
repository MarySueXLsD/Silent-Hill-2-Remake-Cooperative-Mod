-- CoopGhost core - two-player sync for a single-player game.
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
local VERSION = "0.8"

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
local S = CoopGhost.state
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
    eddie = "/Game/Game/Characters/Humans/Eddie/Meshes/Eddie_SkeletalMesh_GamePlayOnly.Eddie_SkeletalMesh_GamePlayOnly",
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
    S.outbox[#S.outbox + 1] = { id = S.nextEventId, text = text }
    S.nextEventId = S.nextEventId + 1
end

local getPC = rawget(_G, "CoopGhost_GetPC") or UEHelpers.GetPlayerController
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

local function handleEvent(pawn, text)
    local kind, rest = text:match("^(%S+)%s*(.*)$")
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

    local intensity, inner, outer, radius = 48, 16, 30, 1200
    local src = S.myFl and S.myFl:IsValid() and S.myFl.LightMain or nil
    if src and src:IsValid() then
        if src.Intensity > 1 then intensity = src.Intensity end
        inner, outer, radius = src.InnerConeAngle, src.OuterConeAngle, src.AttenuationRadius
        pcall(function() light:SetLightFunctionMaterial(src.LightFunctionMaterial) end)
        pcall(function() light:SetIESTexture(src.IESTexture) end)
    end
    pcall(function() light:SetIntensityUnits(0) end)   -- unitless, like the game's own
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
    if #S.snaps == 0 or (now - peer.lastTime) > staleSeconds() or not on("show_other_player") then
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
    if snap then pushSnap(snap) end
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

-- ================================================================ entry points

-- ~30x a second, called by main.lua: measure ourselves and exchange messages.
local function tick()
    pcall(runCmd)

    local pawn = getPawn()
    if not pawn then
        S.avatar = nil
        S.snaps = {}
        S.known = nil   -- the inventory is rebuilt on load; start over when the player is back
        return
    end
    S.tickCount = S.tickCount + 1
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
        local impl = CoopGhost.impl
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

return { version = VERSION, tick = tickAndDraw, onKey = onKey, onFrame = onFrame }

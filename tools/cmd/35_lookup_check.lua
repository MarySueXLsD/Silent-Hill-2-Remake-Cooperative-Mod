-- Are the zero counts real? Compare known-good lookups with the new ones. Read-only.
local pawn = getPawn()
local me = pawn:K2_GetActorLocation()
P(string.format("player at %.0f %.0f %.0f  world %s", me.X, me.Y, me.Z, pawn:GetWorld():GetFullName()))
local function count(name)
    local all = FindAllOf(name)
    return all and #all or 0
end
for _, n in ipairs({ "SHFocusableComponent", "SHAISpawner", "SHItem", "SHCutscenePlayer", "SHDoorMovementComponent",
    "SHPushableComponent", "SHPushableObjectDragComponent", "Pushable_Base_ABP_C", "SHSlidingDoorMovementComponent", "SHSlidingDoor",
    "SHSavePoint", "SavePoint_Base_ABP_C", "SHTraversalLadder", "SHTraversalBase", "SHTraversalObstacle",
    "GenericBase_BP_C", "InteractionSwitch_Base_BP_C", "FocusObject_BP_C", "SHItemsContainer", "SHValve", "TriggerBase_BP_C" }) do
    P(string.format("  %-34s %d", n, count(n)))
end
P("doors tracked by the mod:", #S.doors, " enemies:", #S.enemies, " cutscenes:", #S.cutPlayers)

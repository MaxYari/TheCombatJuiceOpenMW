-- Runs on every NPC and creature. Two jobs:
--
--  * tell the player about hits and kills that concern them - the victim is the
--    only one the engine tells whether an attack landed;
--  * hold this actor's own attack animation for a frame or two at its hit key,
--    so an enemy's weapon stays at the contact pose while the hit result makes
--    its way to the player script.

local mp = "scripts/MaxYari/cinematic combat/"

local omwself = require('openmw.self')
local core = require("openmw.core")
local types = require("openmw.types")
local storage = require("openmw.storage")
local animation = require("openmw.animation")
local nearby = require("openmw.nearby")
local async = require("openmw.async")
local I = require('openmw.interfaces')

local DEFS = require(mp .. "defs")

local selfObject = omwself.object

-- Birds and other harmless ambient creatures never take part in this.
local recordBlackList = { ab01alsonar = true, ab01bird01 = true }
if recordBlackList[omwself.recordId] then return end

-- Settings mirrored by the global script; player storage is not readable here.
local shared = storage.globalSection(DEFS.sharedStorage)
local freezeNpcAttacks = false
local hitFreezeFrames = 0
local function readShared()
    freezeNpcAttacks = shared:get("freezeNpcAttacks") == true
    hitFreezeFrames = shared:get("hitFreezeFrames") or 0
end
readShared()

-- Hits and kills ------------------------------------------------------------

local lastHitByPlayer = 0

local function playerIsFighting()
    local targets = I.MSS and I.MSS.getCombatTargets()
    if not targets then return false end
    for _, t in ipairs(targets) do
        if types.Player.objectIsInstance(t) then return true end
    end
    return false
end

I.Combat.addOnHitHandler(function(attack)
    local attacker = attack.attacker
    if not attacker or not types.Player.objectIsInstance(attacker) then return end
    if attack.successful then lastHitByPlayer = core.getRealTime() end
    attacker:sendEvent(DEFS.e.AttackLanded, {
        victim = selfObject,
        successful = attack.successful and true or false,
        hitPos = attack.hitPos,
    })
end)

-- Health decreases come from MSS, which reads health once per frame for every
-- listener instead of once per mod, and hands over the hit that caused them.
local function onHealthDecrease(e)
    if e.health > 0 then return end
    local damage = math.min(e.previousHealth, e.baseHealth) - e.health
    if damage <= 0 then return end

    -- Only tell the player about kills that are theirs: either the killing blow
    -- was theirs, or this actor was fighting them and something of theirs (a
    -- spell, a summon) finished the job a moment later.
    local attacker = e.hit and e.hit.attacker
    local byPlayer = attacker ~= nil and types.Player.objectIsInstance(attacker)
    if not byPlayer and not (core.getRealTime() - lastHitByPlayer < 1.0 and playerIsFighting()) then
        return
    end

    for _, player in ipairs(nearby.players) do
        player:sendEvent(DEFS.e.ActorKilled, { victim = selfObject })
    end
end

-- Hit key hold --------------------------------------------------------------

local freezeFramesLeft = 0

local function isHitKey(key)
    if key == "hit" then return true end
    -- "chop hit" / "slash hit" / "thrust hit", but not "chop min hit", which is
    -- only the earliest point the attack may be released at.
    return key:sub(-4) == " hit" and not key:find("min hit", 1, true)
end

I.AnimationController.addTextKeyHandler(nil, function(_, key)
    if not freezeNpcAttacks or hitFreezeFrames <= 0 then return end
    if isHitKey(key) then freezeFramesLeft = hitFreezeFrames end
end)

-- Engine handlers -----------------------------------------------------------

local registered = false

local function onActive()
    -- Interfaces appear one script at a time in load order, so MSS is only
    -- guaranteed to exist by the time onActive runs.
    if registered then return end
    registered = true
    if I.MSS then I.MSS.addDamageListener(onHealthDecrease) end
end

local function onUpdate(dt)
    if dt <= 0 then return end
    if freezeFramesLeft > 0 then
        freezeFramesLeft = freezeFramesLeft - 1
        animation.skipAnimationThisFrame(omwself)
    end
end

shared:subscribe(async:callback(readShared))

return {
    engineHandlers = {
        onActive = onActive,
        onUpdate = onUpdate,
    },
}

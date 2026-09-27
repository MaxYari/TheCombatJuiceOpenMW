-- Runs on every NPC and creature. It tells the player about hits and kills that
-- concern them - the victim is the only one the engine tells whether an attack
-- landed, and where - and when it dies, knocks its gear loose.

local mp = "scripts/MaxYari/combat juice/"

local omwself = require('openmw.self')
local core = require("openmw.core")
local types = require("openmw.types")
local nearby = require("openmw.nearby")
local I = require('openmw.interfaces')

local DEFS = require(mp .. "defs")
local looseGear = require(mp .. "loose_gear")

local selfObject = omwself.object

-- Birds and other harmless ambient creatures never take part in this.
local recordBlackList = { ab01alsonar = true, ab01bird01 = true }
if recordBlackList[omwself.recordId] then return end

local lastHitByPlayer = 0

local function playerIsFighting()
    local targets = I.MSS and I.MSS.getCombatTargets()
    if not targets then return false end
    for _, t in ipairs(targets) do
        if types.Player.objectIsInstance(t) then return true end
    end
    return false
end

-- The weapon's record, if it is still there to ask. A thrown weapon's is a
-- stand-in the engine lets go of before the hit reaches Lua, and asking it
-- anything throws; the thrown weapon's id comes as the hit's ammo instead.
local function weaponId(weapon)
    if weapon == nil then return nil end
    local ok, id = pcall(function() return weapon:isValid() and weapon.recordId or nil end)
    return ok and id or nil
end

local function reportHit(attack)
    local attacker = attack.attacker
    if not attacker or not types.Player.objectIsInstance(attacker) then return end
    if attack.successful then lastHitByPlayer = core.getRealTime() end
    -- A blow that only takes stamina: fists, unless the victim is down or the
    -- attacker is a werewolf. Read off the attack itself, so nobody's fatigue
    -- has to be watched - which is also why a stamina spell shows nothing.
    local damage = attack.damage or {}
    attacker:sendEvent(DEFS.e.AttackLanded, {
        victim = selfObject,
        successful = attack.successful and true or false,
        hitPos = attack.hitPos,
        staminaOnly = attack.successful and (damage.fatigue or 0) > 0 and (damage.health or 0) <= 0
            or false,
        -- A blow that landed and did nothing: into a foe that shrugs off normal
        -- weapons ("Your weapon had no effect"), or into a raised shield. The
        -- engine settles both before the hit reaches us, so it arrives at 0.
        noEffect = attack.successful and (damage.health or 0) <= 0 and (damage.fatigue or 0) <= 0
            or false,
        -- What struck, for the colour of the light if it was enchanted.
        weapon = weaponId(attack.weapon),
        ammo = attack.ammo,
        -- A projectile's hit position is where it actually struck; a melee one's is not.
        ranged = tostring(attack.sourceType):lower() == "ranged",
    })
end

-- Nothing may escape this handler. An error here stops every hit handler after
-- it, the engine's own that deals the damage among them, and the blow does
-- nothing at all - which is how thrown weapons came to miss every time.
local hitReportFailed = false
I.Combat.addOnHitHandler(function(attack)
    local ok, err = pcall(reportHit, attack)
    if not ok and not hitReportFailed then
        hitReportFailed = true
        print("[CombatJuice]: a hit could not be reported, the hit itself is unaffected: " .. tostring(err))
    end
end)

-- Health decreases come from MSS, which reads health once per frame for every
-- listener instead of once per mod, and hands over the hit that caused them.
local function onHealthDecrease(e)
    local damage = math.min(e.previousHealth, e.baseHealth) - e.health
    if damage <= 0 then return end

    local attacker = e.hit and e.hit.attacker
    local byPlayer = attacker ~= nil and types.Player.objectIsInstance(attacker)

    -- How hard the blow was, as a share of this actor's whole health. Taken
    -- from the health that was actually lost rather than from the attack's own
    -- damage figure, which is read before armour and difficulty are applied to
    -- it: our hit handler runs ahead of the one that does that.
    if byPlayer and e.baseHealth and e.baseHealth > 0 then
        -- Glancing hits come from a separate mod, if it is installed.
        local weak = false
        if I.GlancedHits and I.GlancedHits.lastHitInfo
            and core.getRealTime() - I.GlancedHits.lastHitInfo.time <= 0.1 then
            weak = I.GlancedHits.lastHitInfo.glancedHit and true or false
        end
        attacker:sendEvent(DEFS.e.DamageDealt, {
            victim = selfObject,
            fraction = damage / e.baseHealth,
            lethal = e.health <= 0,
            weak = weak,
        })
    end

    if e.health > 0 then return end

    -- Every death, whoever caused it. Only the blow that crosses zero counts,
    -- so a corpse loaded from a save, or hit again, sheds nothing.
    if e.previousHealth > 0 then looseGear.strip(omwself, attacker) end

    -- Only tell the player about kills that are theirs: either the killing blow
    -- was theirs, or this actor was fighting them and something of theirs (a
    -- spell, a summon) finished the job a moment later.
    if not byPlayer and not (core.getRealTime() - lastHitByPlayer < 1.0 and playerIsFighting()) then
        return
    end

    for _, player in ipairs(nearby.players) do
        player:sendEvent(DEFS.e.ActorKilled, { victim = selfObject })
    end
end

local registered = false

local function onActive()
    -- Interfaces appear one script at a time in load order, so MSS is only
    -- guaranteed to exist by the time onActive runs.
    if registered then return end
    registered = true
    if I.MSS then I.MSS.addDamageListener(onHealthDecrease) end
end

return {
    engineHandlers = {
        onActive = onActive,
    },
}

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

-- The player this actor is fighting, if it is fighting one.
local function fightingPlayer()
    local targets = I.MSS and I.MSS.getCombatTargets()
    if not targets then return nil end
    for _, t in ipairs(targets) do
        if types.Player.objectIsInstance(t) then return t end
    end
    return nil
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

-- Spells ----------------------------------------------------------------------
--
-- A spell never goes through I.Combat, so the health it takes comes with no
-- hit. The spell itself is still among this actor's active spells when the
-- health comes off, caster and all, since the engine only erases a spent effect
-- at the start of its next update. Spell Framework Plus and OSSC name the
-- caster when they apply theirs too.

-- The effects that take health.
local HEALTH_EFFECTS = {
    firedamage = true, frostdamage = true, shockdamage = true, damagehealth = true,
    poison = true, absorbhealth = true, drainhealth = true, sundamage = true,
}

-- A spell's effect that takes health, or nil.
local function healthEffect(spell)
    for _, effect in ipairs(spell.effects) do
        local id = tostring(effect.id):lower()
        if HEALTH_EFFECTS[id] then return id end
    end
    return nil
end

-- What magic is taking health off this actor: the effect of the newest spell
-- on it that takes health, whoever cast it, and the player, if one of those
-- spells is theirs.
local function healthSpells()
    local effect, playerCaster = nil, nil
    for _, spell in pairs(types.Actor.activeSpells(omwself)) do
        local id = healthEffect(spell)
        if id then
            effect = id
            local caster = spell.caster
            if caster and types.Player.objectIsInstance(caster) then playerCaster = caster end
        end
    end
    return effect, playerCaster
end

-- Health decreases ------------------------------------------------------------

-- Which of the player's marker settings a loss falls under: a blow's own kind,
-- and anything with no blow behind it - a spell, what it leaves burning, lava -
-- magic.
local function sourceOf(hit)
    if not hit then return "magic" end
    local kind = tostring(hit.sourceType):lower()
    if kind == "ranged" or kind == "magic" then return kind end
    return "melee"
end

-- Health decreases come from MSS, which reads health once per frame for every
-- listener instead of once per mod, and hands over the hit that caused them.
local function onHealthDecrease(e)
    local damage = math.min(e.previousHealth, e.baseHealth) - e.health
    if damage <= 0 then return end

    -- The player's own doing: their blow, or their spell if nothing struck.
    local attacker = e.hit and e.hit.attacker
    local effect = nil
    if not e.hit then
        local ok, spellEffect, caster = pcall(healthSpells)
        if ok then attacker, effect = caster, spellEffect end
    end
    local own = attacker ~= nil and types.Player.objectIsInstance(attacker)
    -- And whatever hurts an actor that is fighting them - their summon, their
    -- companion - is shown to them as well.
    local shownTo = own and attacker or fightingPlayer()

    -- Something burning on, or lava, takes health every frame; the player's
    -- script keeps the markers from coming too often.
    local lethal = e.health <= 0
    local now = core.getRealTime()

    -- How hard the blow was, as a share of this actor's whole health. Taken
    -- from the health that was actually lost rather than from the attack's own
    -- damage figure, which is read before armour and difficulty are applied to
    -- it: our hit handler runs ahead of the one that does that.
    if shownTo and e.baseHealth and e.baseHealth > 0 then
        -- Glancing hits come from a separate mod, if it is installed. It only
        -- knows the player's weapons.
        local weak = false
        if own and e.hit and I.GlancedHits and I.GlancedHits.lastHitInfo
            and now - I.GlancedHits.lastHitInfo.time <= 0.1 then
            weak = I.GlancedHits.lastHitInfo.glancedHit and true or false
        end
        shownTo:sendEvent(DEFS.e.DamageDealt, {
            victim = selfObject,
            fraction = damage / e.baseHealth,
            lethal = lethal,
            weak = weak,
            source = sourceOf(e.hit),
            -- The player's own, rather than their summon's or companion's.
            own = own or nil,
            -- A blow that came through I.Combat, whoever's: its marker shows at
            -- once, whatever the throttle.
            hit = e.hit ~= nil or nil,
            -- The magic effect taking the health when no blow did, for the
            -- colour of its marker. A blow's marker never takes one, even an
            -- enchanted weapon's.
            effect = effect,
        })
    end

    if e.health > 0 then return end

    -- Every death, whoever caused it. Only the blow that crosses zero counts,
    -- so a corpse loaded from a save, or hit again, sheds nothing.
    if e.previousHealth > 0 then looseGear.strip(omwself, attacker) end

    -- Only tell the player about kills that are theirs: either the killing blow
    -- was theirs, or this actor was fighting them and something of theirs (a
    -- summon, a companion) finished the job a moment later.
    if not own and not (now - lastHitByPlayer < 1.0 and fightingPlayer()) then
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

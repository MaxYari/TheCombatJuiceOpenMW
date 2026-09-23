-- Cinematic Combat - kill slow motion, an exposure blow-out on the kill,
-- camera shake and impact lights.
-- Mod version, published to Nexus by .github/workflows/nexus-release.yml
-- (the first `version = ...` in this file)
local VERSION = "1.1"

local mp = "scripts/MaxYari/cinematic combat/"

local omwself = require("openmw.self")
local core = require("openmw.core")
local camera = require("openmw.camera")
local types = require("openmw.types")
local ui = require("openmw.ui")
local I = require("openmw.interfaces")

local DEFS = require(mp .. "defs")
local gutils = require(mp .. "gutils")
local SettingsHelper = require(mp .. "settings_helper")
local shaderUtils = require(mp .. "shader_utils")
require(mp .. "settings")

-- Max Yari's Script Services (MSS) is a required dependency: checked once, when this script loads.
if not core.contentFiles.has("MaxYariScriptServices.omwscripts") then
    print("[Cinematic Combat] ERROR: critical dependency is missing: Max Yari's Script Services (MSS). Please install it.")
    ui.showMessage("Cinematic Combat: Critical dependency is missing, please install Max Yari's Script Services (MSS)")
end

local slowdownSettings = SettingsHelper:new(DEFS.settings.slowdown)
local cameraSettings = SettingsHelper:new(DEFS.settings.camera)
local flashSettings = SettingsHelper:new(DEFS.settings.flash)
local effectSettings = SettingsHelper:new(DEFS.settings.effects)

local selfObject = omwself.object

local function now()
    return core.getRealTime()
end

-- Encounters ----------------------------------------------------------------
--
-- OpenMW's combat music is driven by scripts/omw/music/actor.lua, which runs on
-- every NPC and creature, watches its own combat targets and sends every change
-- to the player as OMWMusicCombatTargetsChanged. That is the engine's own "a
-- fight is on / the fight is over" signal - the same one that starts and stops
-- the battle playlist - so listening to it tells us when a kill was the last
-- enemy standing, and how long the fight had been going. It keeps working with
-- combat music turned off.

local fighters = {} -- [actorId] = { actor = GameObject, targetsPlayer = boolean }
local encounterStartedAt = nil
local lastSeenFightingUs = -1000

-- Enemies that die before they ever draw a weapon are never reported as
-- fighting us, and one that runs away drops out of the table too. So a kill
-- counts as part of an encounter if the victim was fighting us, or if anything
-- was, recently enough.
local ENCOUNTER_MEMORY = 5.0

local function onCombatTargetsChanged(data)
    local actor = data.actor
    if not actor then return end
    if not data.targets or next(data.targets) == nil then
        fighters[actor.id] = nil
        return
    end
    local targetsPlayer = false
    for _, target in ipairs(data.targets) do
        if target == selfObject then
            targetsPlayer = true
            break
        end
    end
    fighters[actor.id] = { actor = actor, targetsPlayer = targetsPlayer }
    if targetsPlayer then
        lastSeenFightingUs = now()
        if not encounterStartedAt then encounterStartedAt = now() end
    end
end

-- How many actors are still fighting the player, ignoring `excluded`.
local function enemiesLeft(excluded)
    local count = 0
    for id, entry in pairs(fighters) do
        local actor = entry.actor
        local ok, dead = pcall(types.Actor.isDead, actor)
        if not actor:isValid() or not ok or dead then
            fighters[id] = nil
        elseif actor ~= excluded and entry.targetsPlayer then
            count = count + 1
        end
    end
    return count
end

-- What this kill counts as: the loosest trigger it satisfies, plus how strict
-- it is allowed to be. Nothing here rolls dice or reads settings.
local function classifyKill(victim)
    local entry = victim and fighters[victim.id]
    local inEncounter = (entry ~= nil and entry.targetsPlayer)
        or (now() - lastSeenFightingUs < ENCOUNTER_MEMORY)
    if victim then fighters[victim.id] = nil end

    local endsEncounter = inEncounter and enemiesLeft(victim) == 0
    local fightLength = (endsEncounter and encounterStartedAt) and (now() - encounterStartedAt) or 0
    local wasLong = endsEncounter and fightLength >= (slowdownSettings.LongEncounterSeconds or 20)

    if endsEncounter then encounterStartedAt = nil end

    return {
        rank = wasLong and DEFS.TRIGGER_RANK[DEFS.TRIGGER.LongEncounterEnd]
            or (endsEncounter and DEFS.TRIGGER_RANK[DEFS.TRIGGER.EncounterEnd])
            or DEFS.TRIGGER_RANK[DEFS.TRIGGER.EveryKill],
        endsEncounter = endsEncounter,
        wasLong = wasLong,
        fightLength = fightLength,
    }
end

-- A kill qualifies for a trigger when the kill is at least as strict as the
-- trigger asks: "every kill" takes anything, "long encounter end" only the one
-- kill that ends a long fight.
local function qualifies(kill, triggerValue)
    local want = DEFS.TRIGGER_RANK[triggerValue]
    return want ~= nil and kill.rank >= want
end

-- Camera shake --------------------------------------------------------------

local shake = nil -- { startedAt, duration, strength, seed }

local function startShake(strengthMult)
    if not cameraSettings.ShakeEnabled then return end
    local strength = (cameraSettings.ShakeStrength or 0) * (strengthMult or 1)
    local duration = cameraSettings.ShakeDuration or 0
    if strength <= 0 or duration <= 0 then return end
    shake = {
        startedAt = now(),
        duration = duration,
        strength = math.rad(strength),
        seed = math.random() * 100,
    }
end

local function applyCameraAngles(pitch, yaw, roll)
    if I.DynamicCamera and I.DynamicCamera.setExtraPitch then
        I.DynamicCamera.setExtraPitch(pitch, DEFS.modId)
        I.DynamicCamera.setExtraYaw(yaw, DEFS.modId)
        I.DynamicCamera.setExtraRoll(roll, DEFS.modId)
    else
        -- The built in camera script zeroes these in its onUpdate, which runs
        -- before our onFrame, so setting them every frame is the intended use.
        camera.setExtraPitch(camera.getExtraPitch() + pitch)
        camera.setExtraYaw(camera.getExtraYaw() + yaw)
        camera.setExtraRoll(camera.getExtraRoll() + roll)
    end
end

local function updateShake()
    if not shake then return end
    local t = (now() - shake.startedAt) / shake.duration
    if t >= 1 then
        shake = nil
        applyCameraAngles(0, 0, 0)
        return
    end
    local decay = (1 - t) * (1 - t)
    local amplitude = shake.strength * decay
    local f = (cameraSettings.ShakeFrequency or 38) * (now() - shake.startedAt)
    applyCameraAngles(
        amplitude * gutils.noise(f + shake.seed),
        amplitude * gutils.noise(f * 0.83 + shake.seed + 17.3),
        amplitude * gutils.noise(f * 1.17 + shake.seed + 41.7) * 1.35)
end

-- Kill flash ----------------------------------------------------------------
--
-- postprocessing.load throws if the shader does not compile or post processing
-- is off, and an error out here would take the whole script down with it. The
-- flash is the only thing that should be lost.
--
-- The shader is named cc_blowout rather than cc_killflash because OpenMW keeps
-- every uniform a player has touched in shaders.yaml, keyed by technique name,
-- and those saved values override the defaults shipped in the file
-- (technique.cpp: the parser looks each one up in ShaderManager). A new name
-- means the reworked effect starts from its own defaults.
local flashShader
do
    local ok, wrapper = pcall(shaderUtils.ShaderWrapper.new, shaderUtils.ShaderWrapper,
        "cc_blowout", { uStrength = 0 })
    if ok then
        flashShader = wrapper
    else
        gutils.print("kill flash is off, its shader did not load: " .. tostring(wrapper), 1)
    end
end

local flash = nil -- { startedAt, duration, strength }

local function startFlash()
    if not flashShader then return end
    local duration = flashSettings.FlashDuration or 0
    if duration <= 0 then return end
    flash = { startedAt = now(), duration = duration, strength = flashSettings.FlashStrength or 1 }
    flashShader:enable()
end

-- The envelope is Sanguine Symphony's, read off its death imagespace: every
-- curve in that record runs 0 at the start, peak a tenth of the way in, back to
-- 0 at the end, interpolated linearly. Over the default half second that is a
-- twentieth of a second to snap on and the rest to fade.
local FLASH_PEAK_AT = 0.1

local function flashEnvelope(t)
    if t < FLASH_PEAK_AT then return t / FLASH_PEAK_AT end
    return (1 - t) / (1 - FLASH_PEAK_AT)
end

local function updateFlash()
    if not flash then return end
    local t = (now() - flash.startedAt) / flash.duration
    if t >= 1 then
        flash = nil
        flashShader.u.uStrength = 0
        flashShader:disable()
        return
    end
    flashShader.u.uStrength = flash.strength * flashEnvelope(t)
end

-- Kills ---------------------------------------------------------------------

-- One duration knob per slow motion; the shape of the dip is fixed. The split is
-- Dynamic Reticle's, measured rather than copied: its 0.05/0.1/0.3 were ticked
-- with simulation dt, which is the very thing being slowed, so at its 0.2 floor
-- they came to 0.07/0.45/1.00 in real seconds. These are those, as fractions.
local SLOWDOWN_SHAPE = { inTime = 0.04, hold = 0.30, outTime = 0.66 }

local function requestSlowdown(scale, duration)
    core.sendGlobalEvent(DEFS.e.Slowdown, {
        scale = scale,
        inTime = duration * SLOWDOWN_SHAPE.inTime,
        hold = duration * SLOWDOWN_SHAPE.hold,
        outTime = duration * SLOWDOWN_SHAPE.outTime,
    })
end

local function onActorKilled(data)
    local kill = classifyKill(data.victim)

    if slowdownSettings.SlowdownEnabled then
        -- Both can qualify for the same kill. Work out which ones do, then take
        -- the longer of them.
        local best = nil
        local candidates = {
            {
                trigger = slowdownSettings.SmallSlowdownTrigger,
                chance = slowdownSettings.SmallSlowdownChance,
                scale = slowdownSettings.SmallSlowdownScale or 0.45,
                duration = slowdownSettings.SmallSlowdownDuration or 0.22,
            },
            {
                trigger = slowdownSettings.BigSlowdownTrigger,
                chance = slowdownSettings.BigSlowdownChance,
                scale = slowdownSettings.BigSlowdownScale or 0.2,
                duration = slowdownSettings.BigSlowdownDuration or 0.45,
            },
        }
        for _, c in ipairs(candidates) do
            if qualifies(kill, c.trigger) and math.random() < (c.chance or 0) then
                if not best or c.duration > best.duration then best = c end
            end
        end
        if best then requestSlowdown(best.scale, best.duration) end
    end

    if qualifies(kill, flashSettings.FlashTrigger) then startFlash() end
end

-- Hits ----------------------------------------------------------------------

local sparkDir = "meshes/MaxYari/cinematic combat/sparks/"

-- Variant 1 of each family keeps the name Impact Effects plays; the rest are
-- ours. A burst is picked out of the list every time one is thrown.
local SPARK_VARIANTS = {
    metal = { "meshes/e/impact/metalSpark.nif", sparkDir .. "metal_2.nif",
              sparkDir .. "metal_3.nif", sparkDir .. "metal_4.nif" },
    parry = { "meshes/e/impact/parrySpark.nif", sparkDir .. "parry_2.nif",
              sparkDir .. "parry_3.nif", sparkDir .. "parry_4.nif" },
    shield = { "meshes/e/impact/shieldBlock.nif", sparkDir .. "shield_2.nif",
               sparkDir .. "shield_3.nif" },
}

-- Loose clusters of hard-thrown sparks, for impacts whose own effect is left
-- alone because it is more than just sparks.
local SPARK_CLUSTERS = { sparkDir .. "cluster_1.nif", sparkDir .. "cluster_2.nif",
                         sparkDir .. "cluster_3.nif" }

-- Materials whose spark effect is a single mesh this mod replaces, so the whole
-- thing can be swapped for a random variant. Impact Effects scales the armour
-- one down; matching that keeps the burst the size it always was.
local SPARK_TAKEOVER = {
    Metal = { family = "metal", scale = 1 },
    MetalHeavy = { family = "metal", scale = 1 },
    Parry = { family = "parry", scale = 1 },
    ParryArmorHeavy = { family = "parry", scale = 0.5 },
}

local impactHooksDone = false

local function pick(list)
    return list[math.random(#list)]
end

local function spawnVfx(model, pos, scale)
    core.sendGlobalEvent("SpawnVfx", {
        model = model,
        position = pos,
        options = { mwMagicVfx = false, useAmbientLight = false, scale = scale or 1 },
    })
end

local function spawnLight(pos, radius, duration, color, fallback)
    if not pos then return end
    core.sendGlobalEvent(DEFS.e.SpawnLight, {
        player = selfObject,
        pos = pos,
        radius = radius,
        duration = duration,
        r = color and color.r or fallback[1],
        g = color and color.g or fallback[2],
        b = color and color.b or fallback[3],
    })
end

local function sparkLight(pos)
    if not effectSettings.SparkLightEnabled then return end
    spawnLight(pos, effectSettings.SparkLightRadius or 160,
        effectSettings.SparkLightDuration or 0.09,
        effectSettings.SparkLightColor, { 0.62, 0.78, 1.0 })
end

local function hitLight(pos)
    if not effectSettings.HitLightEnabled then return end
    spawnLight(pos, effectSettings.HitLightRadius or 90,
        effectSettings.HitLightDuration or 0.06,
        effectSettings.HitLightColor, { 1.0, 0.86, 0.6 })
end

-- Impact Effects casts its ray on the swing's "min hit" key, before the engine
-- has decided anything, so it reports a material for a swing that misses just
-- as it does for one that lands. Sparks are fine with that - a blade skating
-- off a pauldron rings either way - but a light on flesh should only appear
-- when the blow actually connected. So the warm light waits here for the victim
-- to say whether it did, which is an update or two behind the ray.
local pendingHitLight = nil
local PENDING_HIT_WINDOW = 0.35

-- Sent by the actor we hit, from its own I.Combat hit handler. Where the blow
-- landed is Impact Effects' business: the engine's own hit position is the
-- victim's feet plus a random fraction of their height, not a contact point.
local function onAttackLanded(data)
    local pending = pendingHitLight
    pendingHitLight = nil

    if not data.successful then return end
    startShake(1)
    if pending and now() - pending.at < PENDING_HIT_WINDOW then
        hitLight(pending.pos)
    end
end

-- Somebody landed a hit on us.
I.Combat.addOnHitHandler(function(attack)
    if not attack.successful then return end
    local factor = cameraSettings.ShakeTakenHitFactor or 0
    if factor > 0 then startShake(factor) end
end)

-- Impact Effects hooks ------------------------------------------------------
--
-- Impact Effects raycasts every swing, works out what was struck and plays the
-- spark meshes this mod replaces. Hooking it is how we learn where a spark just
-- happened, and what was hit, without doing any of that work again - and its
-- hit position is the contact point, not the victim's origin.

local function onImpact(o, var)
    local material = var.material
    local pos = var.hitPos
    if not material or not pos then return end

    local isActor = o ~= nil and types.Actor.objectIsInstance(o)

    local mediumArmour = material == "ParryArmorMedium" and effectSettings.SparksOnMediumArmor
    local sparks = DEFS.sparkMaterials[material] ~= nil
    local variety = effectSettings.SparkVariety

    -- Impact Effects reports a bare body part as "Unarmored" (see
    -- docs/impact-effects-unarmored.md). It has no sound of its own and would
    -- otherwise fall through to a dirt thud, so keep it quiet.
    if material == "Unarmored" then var.noSound = true end

    if sparks or mediumArmour then
        sparkLight(pos)
    elseif isActor then
        -- Flesh, cloth, light armour: the weaker, warmer flash, held back until
        -- the hit is confirmed. Struck scenery gets nothing, it is only enemies
        -- that should light up.
        pendingHitLight = { pos = pos, at = now() }
    end

    if sparks and variety then
        local takeover = SPARK_TAKEOVER[material]
        if takeover then
            -- Ours is the only effect this material plays, so replace it
            -- outright. The sound is already out by the time handlers run.
            var.noVfx = true
            spawnVfx(pick(SPARK_VARIANTS[takeover.family]), pos, takeover.scale)
        else
            -- Dust and sparks together: leave it be and throw a handful of
            -- hard-flung sparks over the top.
            spawnVfx(pick(SPARK_CLUSTERS), pos, 1)
        end
    end

    -- Impact Effects sparks off heavy armour, ice armour, shields and bare
    -- metal, but medium armour only gets a sound. Optionally fill that in.
    if mediumArmour then
        spawnVfx(variety and pick(SPARK_VARIANTS.parry) or SPARK_VARIANTS.parry[1], pos, 0.5)
    end
end

local function setUpImpactHooks()
    if impactHooksDone or not I.impactEffects then return end
    impactHooksDone = true
    I.impactEffects.addHitActorHandler(onImpact)
    -- Without this one, striking the world - a metal door, a statue, stone -
    -- never reaches us, which is why those impacts had no light.
    I.impactEffects.addHitObjectHandler(onImpact)
end

-- Engine handlers -----------------------------------------------------------

local function onUpdate(dt)
    if dt <= 0 then return end
    setUpImpactHooks()
end

local function onFrame()
    updateShake()
    updateFlash()
end

local function onLoad()
    fighters = {}
    encounterStartedAt = nil
    shake = nil
    flash = nil
    if flashShader then
        flashShader.u.uStrength = 0
        flashShader:disable()
    end
end

gutils.print("Cinematic Combat " .. VERSION .. " loaded", 1)

return {
    engineHandlers = {
        onUpdate = onUpdate,
        onFrame = onFrame,
        onLoad = onLoad,
    },
    eventHandlers = {
        [DEFS.e.AttackLanded] = onAttackLanded,
        [DEFS.e.ActorKilled] = onActorKilled,
        OMWMusicCombatTargetsChanged = onCombatTargetsChanged,
    },
    interfaceName = "CinematicCombat",
    interface = {
        version = 1.1,
        shaders = shaderUtils.instances,
        shake = startShake,
        flash = startFlash,
        slowdown = requestSlowdown,
    },
}

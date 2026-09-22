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
local flashShader
do
    local ok, wrapper = pcall(shaderUtils.ShaderWrapper.new, shaderUtils.ShaderWrapper,
        "cc_killflash", { uStrength = 0 })
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

-- Blown out in a couple of frames, held for a moment, then a long recovery -
-- an eye, or a camera, catching up with the light.
local function flashEnvelope(t)
    if t < 0.06 then return t / 0.06 end
    if t < 0.30 then return 1 end
    return (1 - (t - 0.30) / 0.70) ^ 1.8
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

local function requestSlowdown(scale, duration)
    -- One duration knob per slow motion; the shape of the dip is fixed at the
    -- proportions the old in/hold/out settings defaulted to.
    core.sendGlobalEvent(DEFS.e.Slowdown, {
        scale = scale,
        inTime = duration * 0.11,
        hold = duration * 0.22,
        outTime = duration * 0.67,
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

local lastSparkLightAt = -1000

-- A hit that threw no sparks gets the weaker, warmer light. With Impact Effects
-- installed the material decides; without it every hit takes this path.
local function hitLight(hitPos)
    if not effectSettings.HitLightEnabled or not hitPos then return end
    if now() - lastSparkLightAt < 0.1 then return end -- sparks already lit this one
    local color = effectSettings.HitLightColor
    core.sendGlobalEvent(DEFS.e.SpawnLight, {
        player = selfObject,
        pos = hitPos,
        radius = effectSettings.HitLightRadius or 90,
        duration = effectSettings.HitLightDuration or 0.06,
        r = color and color.r or 1.0,
        g = color and color.g or 0.86,
        b = color and color.b or 0.6,
    })
end

-- Sent by the actor we hit, from its own I.Combat hit handler.
local function onAttackLanded(data)
    if not data.successful then return end
    startShake(1)
    hitLight(data.hitPos)
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
-- happened, and what was hit, without doing any of that work again.

local impactHooksDone = false

local function setUpImpactHooks()
    if impactHooksDone or not I.impactEffects then return end
    impactHooksDone = true

    I.impactEffects.addHitActorHandler(function(o, var)
        local material = var.material
        if not material or not var.hitPos then return end

        if DEFS.sparkMaterials[material] then
            lastSparkLightAt = now()
            if effectSettings.SparkLightEnabled then
                local color = effectSettings.SparkLightColor
                core.sendGlobalEvent(DEFS.e.SpawnLight, {
                    player = selfObject,
                    pos = var.hitPos,
                    radius = effectSettings.SparkLightRadius or 160,
                    duration = effectSettings.SparkLightDuration or 0.09,
                    r = color and color.r or 0.62,
                    g = color and color.g or 0.78,
                    b = color and color.b or 1.0,
                })
            end
        end

        -- Impact Effects sparks off heavy armour, ice armour, shields and bare
        -- metal, but medium armour only gets a sound. Optionally fill that in.
        if material == "ParryArmorMedium" and effectSettings.SparksOnMediumArmor then
            lastSparkLightAt = now()
            core.sendGlobalEvent("SpawnVfx", {
                model = "meshes/e/impact/parrySpark.nif",
                position = var.hitPos,
                options = { mwMagicVfx = false, useAmbientLight = false, scale = 0.5 },
            })
        end
    end)
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

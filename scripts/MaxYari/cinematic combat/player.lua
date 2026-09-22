-- Cinematic Combat - hit stops, kill slow motion, camera shake and impact extras.
-- Mod version, published to Nexus by .github/workflows/nexus-release.yml
-- (the first `version = ...` in this file)
local VERSION = "1.0"

local mp = "scripts/MaxYari/cinematic combat/"

local omwself = require("openmw.self")
local core = require("openmw.core")
local camera = require("openmw.camera")
local types = require("openmw.types")
local animation = require("openmw.animation")
local storage = require("openmw.storage")
local async = require("openmw.async")
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

local hitstopSettings = SettingsHelper:new(DEFS.settings.hitstop)
local slowdownSettings = SettingsHelper:new(DEFS.settings.slowdown)
local cameraSettings = SettingsHelper:new(DEFS.settings.camera)
local effectSettings = SettingsHelper:new(DEFS.settings.effects)

local selfObject = omwself.object

local function now()
    return core.getRealTime()
end

-- Encounter tracking --------------------------------------------------------
--
-- OpenMW's combat music is driven by scripts/omw/music/actor.lua, which runs on
-- every NPC and creature, watches its own combat targets and sends every change
-- to the player as OMWMusicCombatTargetsChanged. That is the engine's own "a
-- fight is on / the fight is over" signal - the same one that starts and stops
-- the battle playlist - so listening to it here tells us when a kill was the
-- last enemy standing. It keeps working with combat music turned off.

local fighters = {} -- [actorId] = { actor = GameObject, targetsPlayer = boolean }
local lastSeenFightingUs = -1000

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
    if targetsPlayer then lastSeenFightingUs = now() end
end

-- Enemies that die before they ever draw a weapon are never reported as
-- fighting us, and one that runs away drops out of the table too. So a kill
-- counts as part of an encounter if the victim was fighting us, or if anything
-- was, recently enough.
local ENCOUNTER_MEMORY = 5.0

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

-- Kill vignette -------------------------------------------------------------

local killFlashShader = shaderUtils.ShaderWrapper:new("cc_killflash", { uStrength = 0 })
local killFlash = nil -- { startedAt, duration, strength }

local function startKillFlash()
    if not effectSettings.KillFlashEnabled then return end
    local duration = effectSettings.KillFlashDuration or 0
    if duration <= 0 then return end
    killFlash = { startedAt = now(), duration = duration, strength = effectSettings.KillFlashStrength or 1 }
    killFlashShader:enable()
end

local function updateKillFlash()
    if not killFlash then return end
    local t = (now() - killFlash.startedAt) / killFlash.duration
    if t >= 1 then
        killFlash = nil
        killFlashShader.u.uStrength = 0
        killFlashShader:disable()
        return
    end
    -- Snap in, ease out.
    local envelope = t < 0.18 and (t / 0.18) or (1 - (t - 0.18) / 0.82) ^ 1.6
    killFlashShader.u.uStrength = killFlash.strength * envelope
end

-- Hit stop ------------------------------------------------------------------

local freezeFramesLeft = 0

local function isHitKey(key)
    if key == "hit" then return true end
    return key:sub(-4) == " hit" and not key:find("min hit", 1, true)
end

-- The engine fires the hit key, applies the hit, and only the victim learns
-- whether it landed; its answer reaches us an update or two later. So the
-- attack animation is held here the instant the key fires, before anyone knows
-- the result, and the real hit stop takes over when the answer arrives.
I.AnimationController.addTextKeyHandler(nil, function(_, key)
    if not hitstopSettings.HitstopEnabled then return end
    if not isHitKey(key) then return end
    local frames = hitstopSettings.HitFreezeFrames or 0
    if frames <= 0 then return end
    freezeFramesLeft = frames
end)

local function triggerHitstop(successful, strengthMult)
    if not hitstopSettings.HitstopEnabled then return end
    if not successful and not hitstopSettings.HitstopOnMiss then return end
    local duration = hitstopSettings.HitstopDuration or 0
    if not successful then duration = duration * (hitstopSettings.HitstopMissFactor or 0.5) end
    if duration > 0 then
        core.sendGlobalEvent(DEFS.e.TimeEffect, {
            kind = "hitstop",
            scale = hitstopSettings.HitstopTimeScale or 0.1,
            duration = duration,
        })
    end
    if successful then startShake(strengthMult) end
end

-- Sent by the actor we hit, from its own I.Combat hit handler.
local function onAttackLanded(data)
    -- The answer is here, so the blind hold is done: either the hit stop takes
    -- over on the next update, or the attack missed and nothing should hold.
    freezeFramesLeft = 0
    triggerHitstop(data.successful, 1)
end

-- Somebody landed a hit on us.
I.Combat.addOnHitHandler(function(attack)
    if not hitstopSettings.HitstopOnPlayerHit then return end
    if not attack.successful then return end
    triggerHitstop(true, cameraSettings.ShakeTakenHitFactor or 1.5)
end)

-- Kills ---------------------------------------------------------------------

local function onActorKilled(data)
    local victim = data.victim
    local entry = victim and fighters[victim.id]
    local inEncounter = (entry ~= nil and entry.targetsPlayer)
        or (now() - lastSeenFightingUs < ENCOUNTER_MEMORY)
    if victim then fighters[victim.id] = nil end

    startKillFlash()

    if not slowdownSettings.SlowdownEnabled then return end
    local lastOne = inEncounter and enemiesLeft(victim) == 0
    local guaranteed = lastOne and slowdownSettings.SlowdownOnLastEnemy
    local rolled = math.random() < (slowdownSettings.SlowdownOnKillChance or 0)
    if not guaranteed and not rolled then return end

    core.sendGlobalEvent(DEFS.e.TimeEffect, {
        kind = "slowdown",
        scale = slowdownSettings.SlowdownTimeScale or 0.2,
        inTime = slowdownSettings.SlowdownInTime or 0.05,
        hold = slowdownSettings.SlowdownHoldTime or 0.1,
        outTime = slowdownSettings.SlowdownOutTime or 0.3,
    })
end

-- Impact Effects hooks ------------------------------------------------------
--
-- Impact Effects raycasts every swing, works out what was struck and plays the
-- spark meshes this mod replaces. Hooking it is how we learn where a spark just
-- happened without doing any of that work again.

local impactHooksDone = false

local function setUpImpactHooks()
    if impactHooksDone or not I.impactEffects then return end
    impactHooksDone = true

    local function onImpact(o, var)
        local material = var.material
        if not material then return end

        if DEFS.sparkMaterials[material] and effectSettings.SparkLightEnabled and var.hitPos then
            local color = effectSettings.SparkLightColor
            core.sendGlobalEvent(DEFS.e.SparkFlash, {
                player = selfObject,
                pos = var.hitPos,
                radius = effectSettings.SparkLightRadius or 160,
                duration = effectSettings.SparkLightDuration or 0.09,
                r = color and color.r or 0.62,
                g = color and color.g or 0.78,
                b = color and color.b or 1.0,
            })
        end

        -- Impact Effects sparks off heavy armour, ice armour, shields and bare
        -- metal, but medium armour only gets a sound. Optionally fill that in.
        if material == "ParryArmorMedium" and effectSettings.SparksOnMediumArmor and var.hitPos then
            core.sendGlobalEvent("SpawnVfx", {
                model = "meshes/e/impact/parrySpark.nif",
                position = var.hitPos,
                options = { mwMagicVfx = false, useAmbientLight = false, scale = 0.5 },
            })
        end
    end

    I.impactEffects.addHitActorHandler(onImpact)
    I.impactEffects.addHitObjectHandler(onImpact)
end

-- Settings that actor scripts need ------------------------------------------

local hitstopStore = storage.playerSection(DEFS.settings.hitstop)

local function syncShared()
    core.sendGlobalEvent(DEFS.e.SyncShared, {
        freezeNpcAttacks = hitstopStore:get("HitstopEnabled") and hitstopStore:get("FreezeNpcAttacks"),
        hitFreezeFrames = hitstopStore:get("HitFreezeFrames") or 0,
    })
end

hitstopStore:subscribe(async:callback(syncShared))

-- Engine handlers -----------------------------------------------------------

local function onUpdate(dt)
    if dt <= 0 then return end
    setUpImpactHooks()

    if freezeFramesLeft > 0 then
        freezeFramesLeft = freezeFramesLeft - 1
        animation.skipAnimationThisFrame(omwself)
    end
end

local function onFrame()
    updateShake()
    updateKillFlash()
end

local function onLoad()
    fighters = {}
    shake = nil
    killFlash = nil
    freezeFramesLeft = 0
    killFlashShader.u.uStrength = 0
    killFlashShader:disable()
    syncShared()
end

local function onInit()
    syncShared()
end

gutils.print("Cinematic Combat " .. VERSION .. " loaded", 1)

return {
    engineHandlers = {
        onUpdate = onUpdate,
        onFrame = onFrame,
        onLoad = onLoad,
        onInit = onInit,
    },
    eventHandlers = {
        [DEFS.e.AttackLanded] = onAttackLanded,
        [DEFS.e.ActorKilled] = onActorKilled,
        OMWMusicCombatTargetsChanged = onCombatTargetsChanged,
    },
    interfaceName = "CinematicCombat",
    interface = {
        version = 1.0,
        shaders = shaderUtils.instances,
        hitstop = function(scale, duration)
            core.sendGlobalEvent(DEFS.e.TimeEffect, { kind = "hitstop", scale = scale, duration = duration })
        end,
        shake = startShake,
    },
}

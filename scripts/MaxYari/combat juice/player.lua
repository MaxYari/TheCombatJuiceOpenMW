-- Combat Juice - kill slow motion, an exposure blow-out on the kill,
-- camera shake and impact lights.
-- Mod version, published to Nexus by .github/workflows/nexus-release.yml
-- (the first `version = ...` in this file)
local VERSION = "1.2"

local mp = "scripts/MaxYari/combat juice/"

local omwself = require("openmw.self")
local core = require("openmw.core")
local camera = require("openmw.camera")
local nearby = require("openmw.nearby")
local util = require("openmw.util")
local types = require("openmw.types")
local ui = require("openmw.ui")
local async = require("openmw.async")
local I = require("openmw.interfaces")

local DEFS = require(mp .. "defs")
local gutils = require(mp .. "gutils")
local SettingsHelper = require(mp .. "settings_helper")
local shaderUtils = require(mp .. "shader_utils")
local hitmarkers = require(mp .. "hitmarkers")
local soundFiles = require(mp .. "sounds")
local enchantLight = require(mp .. "enchant_light")
local magicColors = require(mp .. "magic_colors")
require(mp .. "settings")

-- Max Yari's Script Services (MSS) is a required dependency: checked once, when this script loads.
if not core.contentFiles.has("MaxYariScriptServices.omwscripts") then
    print("[Combat Juice] ERROR: critical dependency is missing: Max Yari's Script Services (MSS). Please install it.")
    ui.showMessage("Combat Juice: Critical dependency is missing, please install Max Yari's Script Services (MSS)")
end

local markerSettings = SettingsHelper:new(DEFS.settings.markers)
local markerSoundSettings = SettingsHelper:new(DEFS.settings.markerSounds)
local slowdownSettings = SettingsHelper:new(DEFS.settings.slowdown)
local cameraSettings = SettingsHelper:new(DEFS.settings.camera)
local flashSettings = SettingsHelper:new(DEFS.settings.flash)
local effectSettings = SettingsHelper:new(DEFS.settings.effects)
local enchantSettings = SettingsHelper:new(DEFS.settings.enchantLights)
local magicColorSettings = SettingsHelper:new(DEFS.settings.magicColors)

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

local function startShake(strengthMult, durationMult)
    if not cameraSettings.ShakeEnabled then return end
    local strength = (cameraSettings.ShakeStrength or 0) * (strengthMult or 1)
    local duration = (cameraSettings.ShakeDuration or 0) * (durationMult or 1)
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

-- One duration knob per slow motion; the shape of the dip is fixed. The split is
-- Dynamic Reticle's, measured rather than copied: its 0.05/0.1/0.3 were ticked
-- with simulation dt, which is the very thing being slowed, so at its 0.2 floor
-- they came to 0.07/0.45/1.00 in real seconds. These are those, as fractions.
local SLOWDOWN_SHAPE = { inTime = 0.04, hold = 0.30, outTime = 0.66 }

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
        "cj_flash", { uStrength = 0 })
    if ok then
        flashShader = wrapper
    else
        gutils.print("kill flash is off, its shader did not load: " .. tostring(wrapper), 1)
    end
end

local flash = nil -- { startedAt, duration, strength }

-- Enabling a shader is not free: it changes the post processing chain, and the
-- engine then rebuilds every technique in it - state sets, uniforms, textures,
-- passes, render targets. Doing that on each kill is a hitch at the exact
-- moment the effect is meant to land. So the shader stays in the chain and is
-- steered with uStrength, which both of its passes return on immediately when
-- it is 0. It is only taken out when the flash is switched off entirely.
local function updateFlashShaderEnabled()
    if not flashShader then return end
    local wanted = flashSettings.FlashOn ~= DEFS.FLASH_ON.Never
    if wanted ~= flashShader.enabled then
        if wanted then flashShader:enable() else flashShader:disable() end
    end
end

local function startFlash(duration)
    if not flashShader or not duration or duration <= 0 then return end
    flash = { startedAt = now(), duration = duration, strength = flashSettings.FlashStrength or 1 }
end

-- The flash runs the same shape as the slow motion it rides, phase for phase,
-- so the two move together: in on the same curve, held for the same stretch,
-- and released on the mirror of the slow motion's recovery. On its own tail the
-- flash used to be all but gone a third of the way through the slow motion,
-- while the world was still crawling.
local function flashEnvelope(t)
    local shape = SLOWDOWN_SHAPE
    if t < shape.inTime then
        local x = t / shape.inTime
        return 1 - (1 - x) ^ 3                      -- easeOutCubic, as the dip uses
    end
    local held = shape.inTime + shape.hold
    if t < held then return 1 end
    local x = math.min((t - held) / shape.outTime, 1)
    return 1 - x ^ 3                                -- the mirror of its easeInCubic recovery
end

local function updateFlash()
    updateFlashShaderEnabled()
    if not flash then return end
    local t = (now() - flash.startedAt) / flash.duration
    if t >= 1 then
        flash = nil
        flashShader.u.uStrength = 0
        return
    end
    flashShader.u.uStrength = flash.strength * flashEnvelope(t)
end

-- Kills ---------------------------------------------------------------------

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

    if not slowdownSettings.SlowdownEnabled then return end

    -- Both can qualify for the same kill. Work out which ones do, then take the
    -- longer of them.
    local best = nil
    local candidates = {
        {
            kind = DEFS.FLASH_ON.Short,
            trigger = slowdownSettings.SmallSlowdownTrigger,
            chance = slowdownSettings.SmallSlowdownChance,
            scale = slowdownSettings.SmallSlowdownScale or 0.45,
            duration = slowdownSettings.SmallSlowdownDuration or 0.45,
        },
        {
            kind = DEFS.FLASH_ON.Long,
            trigger = slowdownSettings.BigSlowdownTrigger,
            chance = slowdownSettings.BigSlowdownChance,
            scale = slowdownSettings.BigSlowdownScale or 0.2,
            duration = slowdownSettings.BigSlowdownDuration or 1.5,
        },
    }
    for _, c in ipairs(candidates) do
        if qualifies(kill, c.trigger) and math.random() < (c.chance or 0) then
            if not best or c.duration > best.duration then best = c end
        end
    end
    if not best then return end

    requestSlowdown(best.scale, best.duration)

    -- The flash rides along with one of them, for exactly as long as it lasts.
    local flashOn = flashSettings.FlashOn
    if flashOn == DEFS.FLASH_ON.Both or flashOn == best.kind then
        startFlash(best.duration)
    end
end

-- Hits ----------------------------------------------------------------------

local sparkDir = "meshes/MaxYari/combat juice/sparks/"

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

-- A Morrowind light has no brightness of its own: what it lights is the
-- magnitude of its colour, which the engine hands straight to the renderer as
-- the diffuse colour (sceneutil/lightutil.cpp). Radius is only how far that
-- reaches. So power scales the colour, and a colour picked darker does exactly
-- the same thing - power is there so the two can be set apart from each other.
--
-- A negative power gives a negative light: the engine negates the diffuse
-- colour for those, so it drinks light out of the room instead of adding any.
-- The global script owns the fade, because only it can hand a light over from
-- one record to the next without the two overlapping for a frame.
--
-- lift: for a light found on the body as it is drawn (see seenPoint), which
-- way is off the skin. Right on it, it lights a hot spot rather than the blow,
-- so it is lifted off by about 1 cm (a Morrowind unit is about 1.4 cm).
local SKIN_GAP = 0.7

local function spawnLight(pos, radius, duration, color, fallback, power, lift)
    if not pos or duration <= 0 or power == 0 then return end
    if lift then pos = pos + lift * SKIN_GAP end
    core.sendGlobalEvent(DEFS.e.SpawnLight, {
        player = selfObject,
        pos = pos,
        radius = radius,
        duration = duration,
        power = power or 1,
        r = color and color.r or fallback[1],
        g = color and color.g or fallback[2],
        b = color and color.b or fallback[3],
    })
end

local function sparkLight(pos)
    if not effectSettings.SparkLightEnabled then return end
    spawnLight(pos, effectSettings.SparkLightRadius or 160,
        effectSettings.SparkLightDuration or 0.09,
        effectSettings.SparkLightColor, { 0.62, 0.78, 1.0 },
        effectSettings.SparkLightPower or 1)
end

local function hitLight(pos, lift)
    if not effectSettings.HitLightEnabled then return end
    spawnLight(pos, effectSettings.HitLightRadius or 120,
        effectSettings.HitLightDuration or 0.06,
        effectSettings.HitLightColor, { 1.0, 0.78, 0.45 },
        effectSettings.HitLightPower or 0.33, lift)
end

-- For a blow that only took stamina: warmer, and dimmer than the hit light.
local function staminaLight(pos, lift)
    if not effectSettings.StaminaLightEnabled then return end
    spawnLight(pos, effectSettings.StaminaLightRadius or 120,
        effectSettings.StaminaLightDuration or 0.15,
        effectSettings.StaminaLightColor, { 1.0, 0.5, 0.15 },
        effectSettings.StaminaLightPower or 0.3, lift)
end

-- For a blow whose enchantment fired: its colour, at its own reach.
local function enchantedLight(pos, color, lift)
    spawnLight(pos, enchantSettings.EnchantLightRadius or 120,
        effectSettings.HitLightDuration or 0.2,
        color, { 1.0, 1.0, 1.0 },
        enchantSettings.EnchantLightPower or 0.6, lift)
end

local function weaponInHand()
    local ok, item = pcall(types.Actor.getEquipment, selfObject, types.Actor.EQUIPMENT_SLOT.CarriedRight)
    return ok and item or nil
end

local function magicColor(key) return magicColorSettings[key] end

-- Where a blow landed --------------------------------------------------------
--
-- Impact Effects answers this by casting a ray from the camera through the
-- middle of the screen, so it is only right when you are looking straight at
-- what you hit; swing at someone off to the side and its ray goes past them.
-- So work it out here instead.
--
-- By sight. A physics ray does not land on the body but on the box the engine
-- moves it about in, which stands upright whatever the body is doing: with the
-- victim knocked down, it put the light in the empty air above them. A
-- rendering ray lands on the body as it is drawn, so two of those are tried,
-- along the player's aim and then at the height they are looking on the
-- victim (see lookPoint). When neither finds them, the light goes where the
-- engine put the blood: a random spot on the front of their physics box, from
-- a fifth of their height up to the top, which at least matches the splatter.

local AIM_REACH = 320
local SPARK_WINDOW = 0.35

local lastSparkAt = -1000

-- Down the camera, through the middle of the screen. Only the player has one,
-- and it is where their attention is, so it wins when it lands on the victim.
-- reach: how far it has to go, if that is further than it would anyway.
local function aim(reach)
    local from = camera.getPosition()
    local dir = camera.viewportToWorldVector(util.vector2(0.5, 0.5))
    return from, from + dir * math.max(AIM_REACH + camera.getThirdPersonDistance(), reach or 0)
end

-- Where the player is looking on the victim, as if they had turned to face
-- them: the look's pitch carried out to the victim's distance gives the height,
-- and which way it points is ignored - a blow can land well off to one side of
-- the crosshair. That height is kept a tenth of their height clear of their top
-- and bottom, and the point goes somewhere in the middle half of their width as
-- the eye sees it. Height and
-- width come from the bounding box, which is drawn around the body however it
-- lies - but only its top can be trusted. Below the waist the drawn bounds run
-- wild: one Khajiit's went 70 units into the floor, which put the middle of
-- her box at her knees, and every flash aimed there lit her legs. So the bottom
-- is taken as no lower than their feet.
local EDGE_MARGIN = 0.1
local WIDTH_SPREAD = 0.5

local function lookPoint(victim, box, from, dir)
    local top = box.center.z + box.halfSize.z
    local bottom = math.min(top, math.max(box.center.z - box.halfSize.z, victim.position.z))
    local margin = (top - bottom) * EDGE_MARGIN

    local toX, toY = box.center.x - from.x, box.center.y - from.y
    local flat = math.sqrt(toX * toX + toY * toY)
    local lookFlat = math.sqrt(dir.x * dir.x + dir.y * dir.y)
    local z
    if lookFlat > 1e-6 then
        z = from.z + dir.z / lookFlat * flat
    else -- straight up or down: as far as it goes that way
        z = dir.z > 0 and math.huge or -math.huge
    end
    z = math.max(bottom + margin, math.min(top - margin, z))

    local point = util.vector3(box.center.x, box.center.y, z)
    if flat < 1e-3 then return point end
    local sideX, sideY = -toY / flat, toX / flat
    local halfWidth = math.abs(sideX) * box.halfSize.x + math.abs(sideY) * box.halfSize.y
    local offset = (math.random() * 2 - 1) * halfWidth * WIDTH_SPREAD
    return point + util.vector3(sideX * offset, sideY * offset, 0)
end

-- Where the blow is seen to have landed, handed to `found` along with which way
-- is off the skin - back toward the eye both rays came from - or nil. A hit
-- arrives as an event, and from there a rendering ray can only be asked for:
-- both are asked at once and answered by the next frame, and the one along
-- the aim is believed over the one at the height they are looking.
local function seenPoint(victim, found)
    -- Both go as far as the far side of the victim's bounding box. A weapon's
    -- reach is no measure of that: the engine takes it to the box the victim
    -- stands in, and the body can lie a good way beyond.
    local from = camera.getPosition()
    local farSide, pastLook = 0, nil
    local ok, box = pcall(victim.getBoundingBox, victim)
    if ok and box then
        local halfDiagonal = box.halfSize:length()
        farSide = (box.center - from):length() + halfDiagonal
        local toLook = lookPoint(victim, box, from, camera.viewportToWorldVector(util.vector2(0.5, 0.5))) - from
        local distance = toLook:length()
        if distance > 1e-3 then pastLook = from + toLook * ((distance + halfDiagonal) / distance) end
    end
    local _, aimedAt = aim(farSide)
    local targets = { aimedAt, pastLook }

    local hits, waiting = {}, #targets
    local function answered()
        waiting = waiting - 1
        if waiting > 0 then return end
        local hit = hits[1] or hits[2]
        found(hit, hit and (from - hit):normalize())
    end
    for i, to in ipairs(targets) do
        local asked = pcall(nearby.asyncCastRenderingRay, async:callback(function(res)
            if res.hit and res.hitObject == victim then hits[i] = res.hitPos end
            answered()
        end), from, to, { ignore = selfObject })
        if not asked then answered() end
    end
end

-- Hands `found` where the blow landed, which by sight is a frame later, and
-- when that is on the body as drawn, which way is off it. Failing sight, where
-- the engine put the blood.
-- ranged: a projectile's hit, whose engine position is where it struck.
local function impactPoint(attacker, victim, enginePos, ranged, found)
    if not victim or not victim:isValid() or not attacker or not attacker:isValid() then
        return found(enginePos)
    end
    if ranged and enginePos then return found(enginePos) end
    seenPoint(victim, function(seen, lift)
        if seen then return found(seen, lift) end
        found(enginePos)
    end)
end

-- Sparks light their own impact, so the warm one stays out of the way of a hit
-- that has just thrown some.
local function sparkedRecently()
    return now() - lastSparkAt < SPARK_WINDOW
end

-- A tap and a haymaker should not shake the same. The share of the victim's
-- health the blow took scales both how hard the camera moves and how long it
-- keeps moving, between half and half again what the settings ask for: half at
-- a tenth of their health or less, full at a quarter, half again at two fifths
-- or more.
local DAMAGE_SHAKE_FROM, DAMAGE_SHAKE_TO = 0.10, 0.40
local DAMAGE_SHAKE_MIN, DAMAGE_SHAKE_MAX = 0.5, 1.5

local function damageShakeScale(fraction)
    if not cameraSettings.ShakeScalesWithDamage then return 1 end
    local t = ((fraction or 0) - DAMAGE_SHAKE_FROM) / (DAMAGE_SHAKE_TO - DAMAGE_SHAKE_FROM)
    t = math.max(0, math.min(1, t))
    return DAMAGE_SHAKE_MIN + t * (DAMAGE_SHAKE_MAX - DAMAGE_SHAKE_MIN)
end

-- Hit markers ---------------------------------------------------------------

-- Which of the settings a hit falls under, by what dealt it: a melee or a
-- ranged blow, or magic - a spell, or anything else with no blow behind it.
local MARKER_SETTING = { melee = "MeleeMarkers", ranged = "RangedMarkers", magic = "MagicMarkers" }
local SOUND_SETTING = { melee = "MeleeSounds", ranged = "RangedSounds", magic = "MagicSounds" }

-- What a DEFS.MARKER_ON setting makes of a hit: "kill", "hit", or nil for
-- nothing. A kill where kills are off but hits are on shows as a hit.
local function shownAs(value, lethal)
    local hits = value == DEFS.MARKER_ON.Both or value == DEFS.MARKER_ON.Hit
    local kills = value == DEFS.MARKER_ON.Both or value == DEFS.MARKER_ON.Death
    if lethal and kills then return "kill" end
    if hits then return "hit" end
    return nil
end

-- Dynamic Reticle -----------------------------------------------------------
--
-- A kill marker drawn over the crosshair fades Dynamic Reticle's reticle out
-- from under it, and back in as the marker fades. setAlphaMultiplier arrived in
-- its interface 1.1: with an older one, or none at all, the reticle stays put.

local reticleAlpha = 1

local function updateReticle()
    local alpha = 1 - hitmarkers.reticleCover()
    if alpha == reticleAlpha then return end
    local reticle = I.DynamicReticle
    if not (reticle and type(reticle.setAlphaMultiplier) == "function") then return end
    if pcall(reticle.setAlphaMultiplier, DEFS.modId, alpha) then reticleAlpha = alpha end
end

-- Markers and their sounds come at most this often, whichever enemy they are
-- for - Dynamic Reticle's throttle. A kill always shows, and so does a blow
-- that came through I.Combat, starting the marker over - unless one showed
-- within SAME_MOMENT: a weapon's enchantment and the blow that carried it come
-- off a frame apart, and would otherwise be heard twice.
local MARKER_THROTTLE = 0.333
local SAME_MOMENT = 0.1
local lastMarkerAt = -1000

-- source: "melee", "ranged" or "magic", see MARKER_SETTING.
-- stamina: the blow took stamina and no health - the hit marker, in its own
-- colour. Anything that took health is an ordinary hit and wins.
-- blow: it came through I.Combat, and overrides the throttle.
-- tint: the colour of the magic that dealt it, for the hit marker.
local function playMarker(source, lethal, weak, stamina, blow, tint)
    if not lethal and now() - lastMarkerAt < (blow and SAME_MOMENT or MARKER_THROTTLE) then return end
    source = MARKER_SETTING[source] and source or "melee"

    local marker = shownAs(markerSettings[MARKER_SETTING[source]], lethal)
    if stamina and not markerSettings.StaminaMarkers then marker = nil end
    local opacity = markerSettings.MarkerOpacity or 1
    if weak and not lethal then opacity = markerSettings.WeakMarkerOpacity or 0 end
    if opacity <= 0 then marker = nil end
    -- A glancing blow is shown but not heard.
    local sound = not (weak and not lethal) and shownAs(markerSoundSettings[SOUND_SETTING[source]], lethal)
    if not marker and not sound then return end
    lastMarkerAt = now()

    if marker then
        local kill = marker == "kill"
        local id = kill and markerSettings.KillMarker or markerSettings.HitMarker
        local sizes = markerSettings.MarkerSizes
        hitmarkers.play(id, {
            -- Each marker's own size, set under its preview in the settings.
            scale = sizes and sizes[id] or 1,
            alpha = opacity,
            color = kill and markerSettings.KillMarkerColor
                or stamina and markerSettings.StaminaMarkerColor
                or tint
                or markerSettings.MarkerColor,
            overReticle = kill,
        })
        -- Now rather than on the next update, so the two never show together.
        updateReticle()
    end
    if not sound then return end

    local kill = sound == "kill"
    local minPitch = markerSoundSettings.MarkerSoundPitchMin or 1
    local maxPitch = markerSoundSettings.MarkerSoundPitchMax or 1
    local name = kill and markerSoundSettings.DeathMarkerSound or markerSoundSettings.HitMarkerSound
    local path = soundFiles.path(name)
    if not path then return end
    core.sound.playSoundFile3d(path, omwself, {
        volume = (kill and markerSoundSettings.DeathMarkerVolume
            or markerSoundSettings.HitMarkerVolume) or 1,
        pitch = minPitch + math.random() * math.max(maxPitch - minPitch, 0),
        loop = false,
    })
end

-- Sent by the actor we hit once the health has actually come off it, and by
-- one fighting us whatever hurt it. Only our own melee blows move the camera:
-- a shot, a spell, a summon's blow or a burn is only marked.
local function onDamageDealt(data)
    if data.own and data.source == "melee" then
        local scale = damageShakeScale(data.fraction)
        startShake(scale, scale)
    end
    local tint = markerSettings.SpellMarkerColors and data.effect
        and magicColors.effectColor(data.effect, magicColor) or nil
    playMarker(data.source, data.lethal, data.weak, false, data.hit, tint)
end

-- Sent by the actor we hit, from its own I.Combat hit handler. The shake and
-- the marker wait for the damage event, which knows how hard the blow landed;
-- this only has to light it. A blow that took no health never gets a damage
-- event, so a stamina-only one is marked here as well.
local function onAttackLanded(data)
    if not data.successful then return end
    if data.staminaOnly then playMarker(data.ranged and "ranged" or "melee", false, false, true, true) end
    -- An enchantment that fired lights in its own colour, sparks or not: the
    -- discharge is a thing of its own.
    local enchanted = enchantSettings.EnchantLightEnabled
        and enchantLight.hitColor(data, weaponInHand(), now(), magicColor)
    -- A blow that did nothing lights nothing - but an enchantment that fired
    -- did something, shield or no shield, and still lights in its colour.
    if not enchanted and data.noEffect and not effectSettings.LightNoEffectHits then return end
    if not enchanted and sparkedRecently() then return end
    local light = enchanted and function(pos, lift) enchantedLight(pos, enchanted, lift) end
        or data.staminaOnly and staminaLight or hitLight
    impactPoint(selfObject, data.victim, data.hitPos, data.ranged, light)
end

-- Somebody landed a hit on us. Only the camera reacts: a light on the player
-- lands in their own face, and there is nothing to look at there.
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

-- Impact Effects plays nothing for a swing that is not a blade, a blunt, an
-- axe or a spear - fists above all - but tells its handlers about it all the
-- same. Those do not spark here either: a punch on stone is not a sword on it.
local SPARKING_TYPES = {}
for _, name in ipairs({ "ShortBladeOneHand", "LongBladeOneHand", "LongBladeTwoHand", "BluntOneHand",
    "BluntTwoClose", "BluntTwoWide", "SpearTwoWide", "AxeOneHand", "AxeTwoHand" }) do
    local weaponType = types.Weapon.TYPE[name]
    if weaponType then SPARKING_TYPES[weaponType] = true end
end

local function swingSparks()
    local item = weaponInHand()
    if not item or not types.Weapon.objectIsInstance(item) then return false end
    local ok, record = pcall(types.Weapon.record, item)
    return ok and record ~= nil and SPARKING_TYPES[record.type] == true
end

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

    if not swingSparks() then return end

    if sparks or mediumArmour then
        lastSparkAt = now()
        sparkLight(pos)
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
    hitmarkers.setVisible(I.UI.isHudVisible())
    hitmarkers.update(dt)
    if enchantSettings.EnchantLightEnabled then enchantLight.sample(weaponInHand(), now()) end
    updateReticle()
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
    if flashShader then flashShader.u.uStrength = 0 end
end

gutils.print("Combat Juice " .. VERSION .. " loaded", 1)

return {
    engineHandlers = {
        onUpdate = onUpdate,
        onFrame = onFrame,
        onLoad = onLoad,
    },
    eventHandlers = {
        [DEFS.e.AttackLanded] = onAttackLanded,
        [DEFS.e.DamageDealt] = onDamageDealt,
        [DEFS.e.ActorKilled] = onActorKilled,
        [DEFS.e.ShowMessage] = function(text) ui.showMessage(text) end,
        OMWMusicCombatTargetsChanged = onCombatTargetsChanged,
    },
    interfaceName = "CombatJuice",
    interface = {
        version = 1.1,
        shaders = shaderUtils.instances,
        shake = startShake,
        flash = startFlash,
        slowdown = requestSlowdown,
    },
}

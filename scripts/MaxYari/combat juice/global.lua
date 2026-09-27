-- Global half of Combat Juice. Owns the simulation time scale (the kill slow
-- motion) and the pools of lights used for the impact flashes, handles the
-- sparks Impact Effects throws, and throws the gear that comes loose off the
-- dead. The player script
-- decides *when* things happen, this one carries them out, because only global
-- scripts can change the time scale or create objects.

local mp = "scripts/MaxYari/combat juice/"

local world = require("openmw.world")
local core = require("openmw.core")
local util = require("openmw.util")
local types = require("openmw.types")
local I = require("openmw.interfaces")

local DEFS = require(mp .. "defs")
local gutils = require(mp .. "gutils")
local Tweener = require(mp .. "tweener")
local looseGear = require(mp .. "loose_gear")
require(mp .. "settings_global")

-- Everything here runs on real time, not simulation time: simulation time is the
-- very thing being slowed down, so a dip measured in it would never end.
local function now()
    return core.getRealTime()
end

-- Slow motion ---------------------------------------------------------------

local tweener = nil
local currentScale = 1
local appliedScale = 1

local function applyScale()
    if math.abs(currentScale - appliedScale) > 1e-4 then
        appliedScale = currentScale
        world.setSimulationTimeScale(currentScale)
    end
end

local function onSlowdown(data)
    local minScale = data.scale or 0.2
    local inTime = math.max(data.inTime or 0.05, 1e-4)
    local hold = math.max(data.hold or 0.1, 1e-4)
    local outTime = math.max(data.outTime or 0.3, 1e-4)

    -- A new one replaces whatever was running; the last kill wins.
    if tweener then tweener:finish() end
    currentScale = 1
    tweener = Tweener:new()
    tweener
        :add(inTime, Tweener.easings.easeOutCubic, function(t)
            currentScale = gutils.lerp(1, minScale, t)
        end)
        :add(hold, Tweener.easings.linear, function()
            currentScale = minScale
        end)
        :add(outTime, Tweener.easings.easeInCubic, function(t)
            currentScale = gutils.lerp(minScale, 1, t)
        end)
    applyScale()
end

-- Impact lights -------------------------------------------------------------
--
-- A few light objects per colour and radius, parked disabled and teleported
-- into place for a few frames at a time. Creating and removing an object per
-- hit would churn the save file; these are made once and live in it.
--
-- A light already in the world cannot be dimmed: its colour belongs to the
-- record, and a record cannot be edited once it exists. Fading one out means
-- handing it over to a darker record, so each light is quantised into
-- FADE_LEVELS of power and moves down them as it dies. The handover happens
-- here rather than in the player script so that the new light is placed and the
-- old one switched off in the same update, which is what keeps two of them from
-- ever being lit on the same frame - that would read as a flicker, and doubling
-- the light for a frame is exactly what a fade must not do.

local POOL_SIZE = 3
local FADE_LEVELS = 10
local FADE_FROM = 0.5 -- the light holds full power until halfway through its life

local lightSets = {} -- [key] = { recordId, pool = {}, busy = {} }
local activeLights = {}

local function lightKey(radius, r, g, b, negative)
    return string.format("%d:%d:%d:%d:%s", math.floor(radius), math.floor(r * 255),
        math.floor(g * 255), math.floor(b * 255), negative and "n" or "p")
end

local function lightSet(radius, r, g, b, negative)
    local key = lightKey(radius, r, g, b, negative)
    local set = lightSets[key]
    if set and set.recordId then return set, key end

    local ok, record = pcall(function()
        return world.createRecord(types.Light.createRecordDraft {
            name = "",
            model = "meshes\\MaxYari\\combat juice\\lightsource.nif",
            icon = "",
            weight = 0,
            value = 0,
            duration = -1,
            radius = radius,
            color = util.color.rgb(r, g, b),
            isCarriable = false,
            isDynamic = true,
            isFire = false,
            isFlicker = false,
            isFlickerSlow = false,
            isNegative = negative and true or false,
            isOffByDefault = false,
            isPulse = false,
            isPulseSlow = false,
        })
    end)
    if not ok or not record then
        gutils.print("could not create an impact light record, flashes are off:", tostring(record))
        return nil
    end

    set = set or { pool = {}, busy = {} }
    set.recordId = record.id
    lightSets[key] = set
    return set, key
end

local function takeLight(set)
    for _, obj in ipairs(set.pool) do
        if obj:isValid() and not set.busy[obj.id] then return obj end
    end
    if #set.pool >= POOL_SIZE then return nil end
    local ok, obj = pcall(world.createObject, set.recordId, 1)
    if not ok or not obj then
        gutils.print("could not create an impact light object:", tostring(obj))
        set.recordId = nil -- a stale record id from another save, rebuild next time
        return nil
    end
    table.insert(set.pool, obj)
    return obj
end

local function releaseLight(light)
    if not light.obj then return end
    if light.obj:isValid() then light.obj.enabled = false end
    local set = lightSets[light.key]
    if set then set.busy[light.obj.id] = nil end
    light.obj = nil
end

-- Place the light at `level`, and put out whatever was lit before it. Both
-- happen in this one update, so exactly one of them is lit on any frame.
local function setLevel(light, level)
    local fraction = level / FADE_LEVELS
    local set, key = lightSet(light.radius, light.r * fraction, light.g * fraction,
        light.b * fraction, light.negative)
    if not set then return false end

    local obj = takeLight(set)
    if not obj then return false end -- keep the light we have rather than going dark

    local previous = { obj = light.obj, key = light.key }
    obj:teleport(light.player.cell, light.pos) -- teleport also enables it
    set.busy[obj.id] = true
    light.obj, light.key, light.level = obj, key, level
    releaseLight(previous)
    return true
end

local function onSpawnLight(data)
    if not data.player or not data.player:isValid() or not data.pos then return end
    local power = data.power or 1
    if power == 0 then return end

    local light = {
        player = data.player,
        pos = data.pos,
        radius = data.radius or 120,
        duration = data.duration or 0.08,
        negative = power < 0,
        r = data.r * math.abs(power),
        g = data.g * math.abs(power),
        b = data.b * math.abs(power),
        startedAt = now(),
        level = 0,
    }
    if setLevel(light, FADE_LEVELS) then table.insert(activeLights, light) end
end

local function updateLights()
    local t = now()
    for i = #activeLights, 1, -1 do
        local light = activeLights[i]
        local age = (t - light.startedAt) / light.duration
        if age >= 1 then
            releaseLight(light)
            table.remove(activeLights, i)
        else
            local wanted = FADE_LEVELS
            if age > FADE_FROM then
                wanted = math.ceil(FADE_LEVELS * (1 - age) / (1 - FADE_FROM))
            end
            wanted = math.max(1, math.min(FADE_LEVELS, wanted))
            if wanted ~= light.level then setLevel(light, wanted) end
        end
    end
end

-- Sparks --------------------------------------------------------------------
--
-- Impact Effects spawns every one of its effects in its global script, and
-- shows each one to its effect handlers first: what it is for, where, and which
-- meshes it is about to spawn. Its spark meshes are this mod's already
-- (meshes/e/impact loads over its own), so with variety off its effects are
-- left to it. With variety on, each of its sparks is cancelled and one of
-- several bursts thrown here in its place, while the rest of the effect - dust,
-- frost, blood - is still Impact Effects' to spawn. Medium armour, which it
-- gives no effect at all, sparks here too, and every burst gets a light. The
-- settings are the player's, sent over by the player script.

local sparkDir = "meshes/MaxYari/combat juice/sparks/"

-- Variant 1 of each family is the mesh Impact Effects plays; the rest are ours.
local SPARK_VARIANTS = {
    metal = { "meshes/e/impact/metalSpark.nif", sparkDir .. "metal_2.nif",
              sparkDir .. "metal_3.nif", sparkDir .. "metal_4.nif" },
    parry = { "meshes/e/impact/parrySpark.nif", sparkDir .. "parry_2.nif",
              sparkDir .. "parry_3.nif", sparkDir .. "parry_4.nif" },
}

-- Impact Effects' spark meshes, and the family of bursts each is swapped for.
local SPARK_FAMILY = {
    ["meshes/e/impact/metalSpark.nif"] = "metal",
    ["meshes/e/impact/parrySpark.nif"] = "parry",
}

local sparkSettings = nil  -- the player's, see onSparkSettings
local impactHooked = false

local function pick(list)
    return list[math.random(#list)]
end

local function spawnBurst(model, pos, scale)
    world.vfx.spawn(model, pos, { mwMagicVfx = false, useAmbientLight = false, scale = scale or 1 })
end

local function onImpactEffect(e)
    -- A block's sparks have no position: they are attached to the shield. And
    -- an effect another mod has cancelled whole is not ours to add to.
    if not sparkSettings or not e.hitPos or e.noVfx == true then return end

    -- Cancelled entries are marked in a list, one flag per planned mesh; one
    -- another handler started is added to rather than replaced.
    local cancelled = e.noVfx or {}
    local sparked = false
    for i, v in ipairs(e.vfx) do
        if v.kind == "spark" and not cancelled[i] then
            sparked = true
            local family = sparkSettings.variety and SPARK_FAMILY[v.mesh]
            if family then
                cancelled[i] = true
                spawnBurst(pick(SPARK_VARIANTS[family]), e.hitPos, v.scale)
            end
        end
    end
    if next(cancelled) then e.noVfx = cancelled end

    -- Impact Effects gives medium armour a sound but no effect at all. Heavy
    -- armour's burst fills that in, at the half size it has there.
    if #e.vfx == 0 and e.material == "ParryArmorMedium" and sparkSettings.mediumArmour then
        sparked = true
        spawnBurst(sparkSettings.variety and pick(SPARK_VARIANTS.parry) or SPARK_VARIANTS.parry[1], e.hitPos, 0.5)
    end
    if not sparked then return end

    local light = sparkSettings.light
    if light and light.duration > 0 then
        onSpawnLight({ player = sparkSettings.player, pos = e.hitPos, radius = light.radius,
            duration = light.duration, power = light.power, r = light.r, g = light.g, b = light.b })
    end
end

-- Sent by the player script when it starts and whenever the settings change.
-- An Impact Effects too old for effect handlers is left alone; the player
-- script tells the player to update it.
local function onSparkSettings(data)
    sparkSettings = data
    if impactHooked then return end
    local ie = I.impactEffects
    if not ie or (ie.version or 0) < DEFS.IMPACT_EFFECTS_VERSION then return end
    impactHooked = true
    ie.addEffectHandler(onImpactEffect)
end

-- Engine handlers -----------------------------------------------------------

local function onUpdate()
    if tweener then
        -- Tweener wants elapsed real time, and dt here is already slowed down.
        local t = now()
        local dt = t - (tweener.lastTick or t)
        tweener.lastTick = t
        tweener:tick(dt)
        if #tweener.animations == 0 then
            tweener = nil
            currentScale = 1
        end
        applyScale()
    end
    if #activeLights > 0 then updateLights() end
end

local function resetTime()
    tweener = nil
    currentScale = 1
    appliedScale = 1
    world.setSimulationTimeScale(1)
end

local function onSave()
    local saved = {}
    for key, set in pairs(lightSets) do
        saved[key] = { recordId = set.recordId, pool = set.pool }
    end
    return { lightSets = saved }
end

local function onLoad(state)
    resetTime()
    activeLights = {}
    lightSets = {}
    if state and state.lightSets then
        for key, set in pairs(state.lightSets) do
            lightSets[key] = { recordId = set.recordId, pool = set.pool or {}, busy = {} }
            for _, obj in ipairs(lightSets[key].pool) do
                if obj and obj:isValid() then obj.enabled = false end
            end
        end
    end
end

return {
    engineHandlers = {
        onUpdate = onUpdate,
        onLoad = onLoad,
        onSave = onSave,
        onInit = resetTime,
    },
    eventHandlers = {
        [DEFS.e.Slowdown] = onSlowdown,
        [DEFS.e.SpawnLight] = onSpawnLight,
        [DEFS.e.SparkSettings] = onSparkSettings,
        [DEFS.e.ThrowGear] = looseGear.throw,
    },
}

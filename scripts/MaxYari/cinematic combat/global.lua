-- Global half of Cinematic Combat. Owns the simulation time scale (hit stops and
-- kill slow motion) and the pool of lights used for the spark flash. The player
-- script decides *when* things happen, this one carries them out, because only
-- global scripts can change the time scale or create objects.

local mp = "scripts/MaxYari/cinematic combat/"

local world = require("openmw.world")
local core = require("openmw.core")
local util = require("openmw.util")
local types = require("openmw.types")
local storage = require("openmw.storage")

local DEFS = require(mp .. "defs")
local gutils = require(mp .. "gutils")
local Tweener = require(mp .. "tweener")

-- Everything here runs on real time, not simulation time: simulation time is the
-- very thing being slowed down, so a 0.1s hit stop measured in it would last a
-- real second.
local function now()
    return core.getRealTime()
end

-- Time scale ---------------------------------------------------------------

local hitstop = nil        -- { scale = number, endsAt = realtime }
local slowdownTweener = nil
local slowdownScale = 1
local appliedScale = 1

local function applyScale()
    local target = 1
    if hitstop then target = math.min(target, hitstop.scale) end
    if slowdownTweener then target = math.min(target, slowdownScale) end
    if math.abs(target - appliedScale) > 1e-4 then
        appliedScale = target
        world.setSimulationTimeScale(target)
    end
end

local function startHitstop(data)
    local duration = data.duration or 0.1
    if duration <= 0 then return end
    local endsAt = now() + duration
    -- Overlapping hits extend the stop rather than restarting it, and the
    -- deepest requested scale wins.
    if hitstop then
        hitstop.scale = math.min(hitstop.scale, data.scale or 0.1)
        hitstop.endsAt = math.max(hitstop.endsAt, endsAt)
    else
        hitstop = { scale = data.scale or 0.1, endsAt = endsAt }
    end
    applyScale()
end

local function startSlowdown(data)
    local minScale = data.scale or 0.2
    local inTime = data.inTime or 0.05
    local hold = data.hold or 0.1
    local outTime = data.outTime or 0.3

    if slowdownTweener then slowdownTweener:finish() end
    slowdownScale = 1
    slowdownTweener = Tweener:new()
    slowdownTweener
        :add(math.max(inTime, 1e-4), Tweener.easings.easeOutCubic, function(t)
            slowdownScale = gutils.lerp(1, minScale, t)
        end)
        :add(math.max(hold, 1e-4), Tweener.easings.linear, function()
            slowdownScale = minScale
        end)
        :add(math.max(outTime, 1e-4), Tweener.easings.easeInCubic, function(t)
            slowdownScale = gutils.lerp(minScale, 1, t)
        end)
    applyScale()
end

local function onTimeEffect(data)
    if data.kind == "hitstop" then
        startHitstop(data)
    elseif data.kind == "slowdown" then
        startSlowdown(data)
    elseif data.kind == "cancel" then
        hitstop = nil
        if slowdownTweener then slowdownTweener:finish() end
        slowdownTweener = nil
        slowdownScale = 1
        applyScale()
    end
end

-- Spark light --------------------------------------------------------------
--
-- A pool of a few light objects, parked disabled and teleported into place for
-- a few frames at a time. Creating and removing an object per spark would churn
-- the save file; these are made once and live in it.

local POOL_SIZE = 3
local lights = { recordId = nil, key = nil, pool = {}, busy = {} }

local function lightKey(radius, r, g, b)
    return string.format("%d:%d:%d:%d", math.floor(radius), math.floor(r * 255),
        math.floor(g * 255), math.floor(b * 255))
end

local function ensureRecord(data)
    local key = lightKey(data.radius, data.r, data.g, data.b)
    if lights.recordId and lights.key == key then return true end

    -- Radius or colour changed (or this is a fresh game): new record, new pool.
    for _, obj in ipairs(lights.pool) do
        if obj and obj:isValid() then obj:remove() end
    end
    lights.pool, lights.busy = {}, {}

    local ok, record = pcall(function()
        return world.createRecord(types.Light.createRecordDraft {
            name = "",
            model = "meshes\\MaxYari\\cinematic combat\\lightsource.nif",
            icon = "",
            weight = 0,
            value = 0,
            duration = -1,
            radius = data.radius,
            color = util.color.rgb(data.r, data.g, data.b),
            isCarriable = false,
            isDynamic = true,
            isFire = false,
            isFlicker = false,
            isFlickerSlow = false,
            isNegative = false,
            isOffByDefault = false,
            isPulse = false,
            isPulseSlow = false,
        })
    end)
    if not ok or not record then
        gutils.print("could not create the spark light record, flashes are off:", tostring(record))
        return false
    end
    lights.recordId = record.id
    lights.key = key
    return true
end

local function takeLight()
    for _, obj in ipairs(lights.pool) do
        if obj:isValid() and not lights.busy[obj.id] then return obj end
    end
    if #lights.pool >= POOL_SIZE then return nil end
    local ok, obj = pcall(world.createObject, lights.recordId, 1)
    if not ok or not obj then
        gutils.print("could not create a spark light object:", tostring(obj))
        lights.recordId = nil -- a stale record id from another save, rebuild next time
        return nil
    end
    table.insert(lights.pool, obj)
    return obj
end

local function onSparkFlash(data)
    if not data.player or not data.player:isValid() or not data.pos then return end
    if not ensureRecord(data) then return end
    local obj = takeLight()
    if not obj then return end
    obj:teleport(data.player.cell, data.pos) -- also enables it
    lights.busy[obj.id] = { obj = obj, until_ = now() + (data.duration or 0.09) }
end

local function updateLights()
    local t = now()
    for id, entry in pairs(lights.busy) do
        if t >= entry.until_ then
            if entry.obj:isValid() then entry.obj:setEnabled(false) end
            lights.busy[id] = nil
        end
    end
end

-- Settings actors need ------------------------------------------------------
-- Player storage can only be read by player and menu scripts, so the two values
-- actor scripts care about are mirrored into a global section here.

local sharedSection = storage.globalSection(DEFS.sharedStorage)

local function onSyncShared(data)
    sharedSection:set("freezeNpcAttacks", data.freezeNpcAttacks and true or false)
    sharedSection:set("hitFreezeFrames", data.hitFreezeFrames or 0)
end

-- Engine handlers -----------------------------------------------------------

local function onUpdate()
    if hitstop and now() >= hitstop.endsAt then
        hitstop = nil
        applyScale()
    end
    if slowdownTweener then
        -- Tweener wants elapsed real time, and dt here is already slowed down.
        local t = now()
        local dt = t - (slowdownTweener.lastTick or t)
        slowdownTweener.lastTick = t
        slowdownTweener:tick(dt)
        if #slowdownTweener.animations == 0 then
            slowdownTweener = nil
            slowdownScale = 1
        end
        applyScale()
    end
    if next(lights.busy) ~= nil then updateLights() end
end

local function resetTime()
    hitstop = nil
    slowdownTweener = nil
    slowdownScale = 1
    appliedScale = 1
    world.setSimulationTimeScale(1)
end

local function onSave()
    return { lightRecordId = lights.recordId, lightKey = lights.key, lightPool = lights.pool }
end

local function onLoad(state)
    resetTime()
    lights.busy = {}
    if state then
        lights.recordId = state.lightRecordId
        lights.key = state.lightKey
        lights.pool = state.lightPool or {}
        for _, obj in ipairs(lights.pool) do
            if obj and obj:isValid() then obj:setEnabled(false) end
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
        [DEFS.e.TimeEffect] = onTimeEffect,
        [DEFS.e.SparkFlash] = onSparkFlash,
        [DEFS.e.SyncShared] = onSyncShared,
    },
}

-- Global half of Cinematic Combat. Owns the simulation time scale (the kill slow
-- motion) and the pools of lights used for the impact flashes. The player script
-- decides *when* things happen, this one carries them out, because only global
-- scripts can change the time scale or create objects.

local mp = "scripts/MaxYari/cinematic combat/"

local world = require("openmw.world")
local core = require("openmw.core")
local util = require("openmw.util")
local types = require("openmw.types")

local DEFS = require(mp .. "defs")
local gutils = require(mp .. "gutils")
local Tweener = require(mp .. "tweener")

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
-- A few light objects per colour and radius, parked disabled and teleported into
-- place for a few frames at a time. Creating and removing an object per hit would
-- churn the save file; these are made once and live in it.

local POOL_SIZE = 3
local lightSets = {} -- [key] = { recordId, pool = {}, busy = {} }

local function lightKey(radius, r, g, b)
    return string.format("%d:%d:%d:%d", math.floor(radius), math.floor(r * 255),
        math.floor(g * 255), math.floor(b * 255))
end

local function lightSet(data)
    local key = lightKey(data.radius, data.r, data.g, data.b)
    local set = lightSets[key]
    if set and set.recordId then return set end

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
        gutils.print("could not create an impact light record, flashes are off:", tostring(record))
        return nil
    end

    set = set or { pool = {}, busy = {} }
    set.recordId = record.id
    lightSets[key] = set
    return set
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

local function onSpawnLight(data)
    if not data.player or not data.player:isValid() or not data.pos then return end
    local set = lightSet(data)
    if not set then return end
    local obj = takeLight(set)
    if not obj then return end
    obj:teleport(data.player.cell, data.pos) -- also enables it
    set.busy[obj.id] = { obj = obj, until_ = now() + (data.duration or 0.08) }
end

local function updateLights()
    local t = now()
    for _, set in pairs(lightSets) do
        for id, entry in pairs(set.busy) do
            if t >= entry.until_ then
                if entry.obj:isValid() then entry.obj.enabled = false end
                set.busy[id] = nil
            end
        end
    end
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
    for _, set in pairs(lightSets) do
        if next(set.busy) ~= nil then
            updateLights()
            break
        end
    end
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
    },
}

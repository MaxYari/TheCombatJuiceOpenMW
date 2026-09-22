-- Minimal fake of the OpenMW Lua API, enough to load and drive the mod scripts.
local M = {}

local log = {}
M.log = log
local function note(fmt, ...) log[#log+1] = string.format(fmt, ...) end
M.note = note

M.realTime = 100.0
M.settingsStore = {}     -- [section][key] = value
M.globalStore = {}       -- [section][key] = value
M.sentGlobalEvents = {}
M.sentObjectEvents = {}
M.timeScale = 1
M.skipAnimCalls = 0
M.cameraExtras = { pitch = 0, yaw = 0, roll = 0 }

M.subscribers = {}

-- Storage sections notify their subscribers on a write, the way the engine's do:
-- that is how the mod's settings cache learns a setting changed.
local function makeSection(tbl, name)
    tbl[name] = tbl[name] or {}
    M.subscribers[name] = M.subscribers[name] or {}
    local section = {}
    function section:get(key) return tbl[name][key] end
    function section:set(key, value)
        tbl[name][key] = value
        for _, cb in ipairs(M.subscribers[name]) do cb(name, key) end
    end
    function section:subscribe(cb) table.insert(M.subscribers[name], cb) end
    function section:asTable() return tbl[name] end
    function section:setLifeTime() end
    return section
end

-- Change a setting the way the options menu would.
function M.setSetting(section, key, value)
    M.settingsStore[section] = M.settingsStore[section] or {}
    M.settingsStore[section][key] = value
    for _, cb in ipairs(M.subscribers[section] or {}) do cb(section, key) end
end

local objectCounter = 0
function M.newObject(kind, opts)
    objectCounter = objectCounter + 1
    opts = opts or {}
    local o = {
        id = opts.id or ("obj" .. objectCounter),
        recordId = opts.recordId or "test_actor",
        kind = kind,
        cell = opts.cell or { name = "TestCell" },
        position = opts.position or { x = 0, y = 0, z = 0 },
        dead = false,
        enabled = true,
        valid = true,
    }
    function o:isValid() return self.valid end
    function o:sendEvent(name, data)
        table.insert(M.sentObjectEvents, { target = self, name = name, data = data })
    end
    function o:teleport(cell, pos) self.cell = cell; self.pos = pos; self.enabled = true end
    function o:remove() self.valid = false end
    return o
end

local player = M.newObject("player", { id = "player" })
M.player = player

local packages = {}
M.packages = packages

packages["openmw.core"] = {
    getRealTime = function() return M.realTime end,
    getSimulationTime = function() return M.realTime end,
    getGMST = function() return 1 end,
    contentFiles = { has = function() return true end },
    sendGlobalEvent = function(name, data)
        table.insert(M.sentGlobalEvents, { name = name, data = data })
    end,
    sound = { playSoundFile3d = function() end, isEnabled = function() return true end },
}
packages["openmw.util"] = {
    color = {
        rgb = function(r, g, b) return { r = r, g = g, b = b } end,
        hex = function() return { r = 1, g = 1, b = 1 } end,
    },
    clamp = function(v, a, b) return math.max(a, math.min(b, v)) end,
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
}
packages["openmw.storage"] = {
    playerSection = function(name) return makeSection(M.settingsStore, name) end,
    globalSection = function(name) return makeSection(M.globalStore, name) end,
    LIFE_TIME = { Persistent = 0, GameSession = 1, Temporary = 2 },
}
packages["openmw.async"] = setmetatable({}, { __index = function(_, k)
    if k == "callback" then return function(_, fn) return fn end end
end })
packages["openmw.ui"] = { showMessage = function(m) note("ui.showMessage: %s", m) end,
    isHudVisible = function() return true end }
packages["openmw.camera"] = {
    getExtraPitch = function() return M.cameraExtras.pitch end,
    getExtraYaw = function() return M.cameraExtras.yaw end,
    getExtraRoll = function() return M.cameraExtras.roll end,
    setExtraPitch = function(v) M.cameraExtras.pitch = v end,
    setExtraYaw = function(v) M.cameraExtras.yaw = v end,
    setExtraRoll = function(v) M.cameraExtras.roll = v end,
}
packages["openmw.animation"] = {
    skipAnimationThisFrame = function() M.skipAnimCalls = M.skipAnimCalls + 1 end,
    getCurrentTime = function() return 0 end,
    getTextKeyTime = function() return 0 end,
    BONE_GROUP = { LowerBody = 1, Torso = 2, LeftArm = 3, RightArm = 4 },
}
packages["openmw.types"] = {
    Player = { objectIsInstance = function(o) return o ~= nil and o.kind == "player" end },
    Actor = {
        objectIsInstance = function(o)
            return o ~= nil and (o.kind == "npc" or o.kind == "creature" or o.kind == "player")
        end,
        isDead = function(o) return o.dead end,
        isDeathFinished = function(o) return o.dead end,
        getStance = function() return 0 end,
        STANCE = { Nothing = 0 },
    },
    NPC = { objectIsInstance = function(o) return o ~= nil and o.kind == "npc" end },
    Creature = { objectIsInstance = function(o) return o ~= nil and o.kind == "creature" end },
    Light = {
        createRecordDraft = function(t) return t end,
    },
}
packages["openmw.world"] = {
    setSimulationTimeScale = function(s) M.timeScale = s; note("timeScale=%.3f", s) end,
    getSimulationTimeScale = function() return M.timeScale end,
    createRecord = function(draft) draft.id = "cc_light_1"; return draft end,
    createObject = function(recordId) return M.newObject("light", { id = "light" .. objectCounter }) end,
}
packages["openmw.nearby"] = { players = { player }, actors = {} }
packages["openmw.vfs"] = { pathsWithPrefix = function() return function() return nil end end,
    fileExists = function() return true end }
packages["openmw.postprocessing"] = {
    load = function(name)
        return {
            enable = function() note("shader %s enabled", name) end,
            disable = function() note("shader %s disabled", name) end,
            setFloat = function(_, k, v) M.shaderUniform = v end,
            setVector2 = function() end, setVector3 = function() end, setVector3Array = function() end,
        }
    end,
}
packages["openmw.debug"] = { isAIEnabled = function() return true end }

M.textKeyHandlers = {}
M.hitHandlers = {}
M.damageListeners = {}
M.settingsPages = {}
M.settingsGroups = {}

packages["openmw.interfaces"] = {
    Settings = {
        registerPage = function(p) table.insert(M.settingsPages, p) end,
        registerGroup = function(g)
            table.insert(M.settingsGroups, g)
            -- defaults land in the fake player storage, like the real framework
            local section = makeSection(M.settingsStore, g.key)
            for _, s in ipairs(g.settings) do section:set(s.key, s.default) end
        end,
    },
    AnimationController = {
        addTextKeyHandler = function(_, fn) table.insert(M.textKeyHandlers, fn) end,
        playBlendedAnimation = function() end,
    },
    Combat = { addOnHitHandler = function(fn) table.insert(M.hitHandlers, fn) end },
    MSS = {
        version = 1,
        addDamageListener = function(fn) table.insert(M.damageListeners, fn) end,
        getCombatTargets = function() return M.mssTargets end,
    },
    impactEffects = nil, -- set by M.enableImpactEffects()
}

M.impactActorHandlers = {}
M.impactObjectHandlers = {}

function M.enableImpactEffects()
    M.impactActorHandlers, M.impactObjectHandlers = {}, {}
    packages["openmw.interfaces"].impactEffects = {
        version = 107,
        addHitActorHandler = function(fn) table.insert(M.impactActorHandlers, fn) end,
        addHitObjectHandler = function(fn) table.insert(M.impactObjectHandlers, fn) end,
    }
end

function M.selfFor(object)
    return setmetatable({ object = object, recordId = object.recordId, cell = object.cell },
        { __index = function(_, k) return object[k] end })
end

function M.install(selfObject)
    packages["openmw.self"] = M.selfFor(selfObject)
    local realRequire = require
    _G.require = function(name)
        if packages[name] then return packages[name] end
        if name:match("^openmw") then error("stub is missing " .. name) end
        return realRequire(name)
    end
end

return M

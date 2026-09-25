-- Minimal fake of the OpenMW Lua API, enough to load and drive the mod scripts.
local M = {}

local log = {}
M.log = log
local function note(fmt, ...) log[#log+1] = string.format(fmt, ...) end
M.note = note

M.realTime = 100.0
M.allObjects = {}
M.sentSounds = {}
M.lastLightRecord = nil
M.settingsStore = {}     -- [section][key] = value
M.globalStore = {}       -- [section][key] = value
M.sentGlobalEvents = {}
M.sentObjectEvents = {}
M.timeScale = 1
M.skipAnimCalls = 0
M.cameraExtras = { pitch = 0, yaw = 0, roll = 0 }

M.subscribers = {}
M.contentFiles = {} -- [name] = false to leave one out

-- Storage sections notify their subscribers on a write, the way the engine's do:
-- that is how the mod's settings cache learns a setting changed.
local function vec2(x, y)
    local v = { x = x, y = y }
    setmetatable(v, { __add = function(a, b) return vec2(a.x + b.x, a.y + b.y) end,
                      __sub = function(a, b) return vec2(a.x - b.x, a.y - b.y) end,
                      __mul = function(a, k)
                          if type(k) == "table" then return vec2(a.x * k.x, a.y * k.y) end
                          return vec2(a.x * k, a.y * k)
                      end })
    return v
end

local vec3Methods = {}
local function vec3(x, y, z)
    local v = { x = x, y = y, z = z }
    setmetatable(v, { __add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end,
                      __sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end,
                      __mul = function(a, k)
                          if type(k) == "table" then return a.x * k.x + a.y * k.y + a.z * k.z end
                          return vec3(a.x * k, a.y * k, a.z * k)
                      end,
                      __index = vec3Methods })
    return v
end
function vec3Methods:length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function vec3Methods:normalize()
    local l = self:length()
    return vec3(self.x / l, self.y / l, self.z / l)
end

-- Rotations are only ever composed and applied to "forward" here, so identity
-- is enough.
local transform = setmetatable({}, { __mul = function(a) return a end })
transform.apply = function(_, v) return v end

local function makeSection(tbl, name)
    tbl[name] = tbl[name] or {}
    M.subscribers[name] = M.subscribers[name] or {}
    local section = {}
    function section:get(key) return tbl[name][key] end
    function section:getCopy(key)
        local value = tbl[name][key]
        if type(value) ~= "table" then return value end
        local copy = {}
        for k, v in pairs(value) do copy[k] = v end
        return copy
    end
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
        position = opts.position or vec3(0, 0, 0),
        rotation = transform,
        scale = opts.scale or 1,
        dead = false,
        enabled = true,
        valid = true,
    }
    function o:isValid() return self.valid end
    function o:sendEvent(name, data)
        table.insert(M.sentObjectEvents, { target = self, name = name, data = data })
    end
    function o:teleport(cell, pos) self.cell = cell; self.pos = pos; self.enabled = true; self.teleported = true end
    table.insert(M.allObjects, o)
    function o:remove() self.valid = false end
    return o
end

local player = M.newObject("player", { id = "player" })
M.player = player

M.vec3 = vec3
M.vec2 = vec2

local packages = {}
M.packages = packages

packages["openmw.core"] = {
    getRealTime = function() return M.realTime end,
    getSimulationTime = function() return M.realTime end,
    getGMST = function() return 1 end,
    contentFiles = { has = function(name) return M.contentFiles[name] ~= false end },
    sendGlobalEvent = function(name, data)
        table.insert(M.sentGlobalEvents, { name = name, data = data })
    end,
    sound = {
        playSoundFile3d = function(path, obj, opts)
            table.insert(M.sentSounds, { path = path, options = opts })
        end,
        isEnabled = function() return true end,
    },
}
packages["openmw.util"] = {
    vector2 = vec2,
    color = {
        rgb = function(r, g, b) return { r = r, g = g, b = b } end,
        hex = function() return { r = 1, g = 1, b = 1 } end,
    },
    clamp = function(v, a, b) return math.max(a, math.min(b, v)) end,
    vector3 = vec3,
    transform = {
        rotateX = function() return transform end,
        rotateY = function() return transform end,
        rotateZ = function() return transform end,
    },
}
packages["openmw.storage"] = {
    playerSection = function(name) return makeSection(M.settingsStore, name) end,
    globalSection = function(name) return makeSection(M.globalStore, name) end,
    LIFE_TIME = { Persistent = 0, GameSession = 1, Temporary = 2 },
}
packages["openmw.async"] = setmetatable({}, { __index = function(_, k)
    if k == "callback" then return function(_, fn) return fn end end
end })
local function uiElement(layout)
    local el = { layout = layout, updates = 0 }
    function el:update() self.updates = self.updates + 1 end
    function el:destroy() end
    return el
end

packages["openmw.ui"] = {
    TYPE = setmetatable({}, { __index = function(_, k) return k end }),
    ALIGNMENT = setmetatable({}, { __index = function(_, k) return k end }),
    texture = function(t) return t end,
    content = function(list)
        local items, byName = {}, {}
        local content = {}
        function content:add(child)
            table.insert(items, child)
            if child.name then byName[child.name] = child end
        end
        for _, child in ipairs(list or {}) do content:add(child) end
        return setmetatable(content, {
            __index = function(_, k)
                if type(k) == "number" then return items[k] end
                return byName[k]
            end,
            __len = function() return #items end,
        })
    end,
    create = function(layout)
        M.lastUi = uiElement(layout)
        if layout.layer == "HUD" then M.hud = M.lastUi end
        return M.lastUi
    end,
    showMessage = function(m) note("ui.showMessage: %s", m) end,
    isHudVisible = function() return true end }
packages["openmw.camera"] = {
    getPosition = function() return vec3(0, -100, 100) end,
    viewportToWorldVector = function() return vec3(0, 1, 0) end,
    getThirdPersonDistance = function() return 0 end,
    MODE = { FirstPerson = 0, ThirdPerson = 1 },
    getMode = function() return 1 end,
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
    Weapon = {
        objectIsInstance = function(o) return o ~= nil and o.kind == "weapon" end,
        record = function(o) return { type = o and o.weaponType or 0 } end,
        TYPE = { ShortBladeOneHand = 0, LongBladeOneHand = 1, MarksmanBow = 9,
                 MarksmanCrossbow = 10, MarksmanThrown = 11 },
    },
    Actor = {
        STANCE = { Nothing = 0, Weapon = 1, Spell = 2 },
        EQUIPMENT_SLOT = { CarriedRight = 1, Helmet = 2, Cuirass = 3, Greaves = 4, CarriedLeft = 5,
                           Boots = 6, Shirt = 7, Robe = 8, LeftPauldron = 9, RightPauldron = 10,
                           LeftGauntlet = 11, RightGauntlet = 12, Pants = 13, Skirt = 14,
                           Belt = 15, Amulet = 16, LeftRing = 17, RightRing = 18, Ammunition = 19 },
        getStance = function(o) return M.stance or 1 end,
        -- With a slot: what the player is holding, for the marker sounds. Without
        -- one: an actor's whole kit, for the gear that comes loose on death.
        getEquipment = function(o, slot)
            if slot == nil then return o.equipment or {} end
            return M.equipped
        end,
        setEquipment = function(o, equipment) (o.object or o).equipment = equipment end,
        inventory = function(o)
            return { getAll = function() return o.carried or {} end }
        end,
        objectIsInstance = function(o)
            return o ~= nil and (o.kind == "npc" or o.kind == "creature" or o.kind == "player")
        end,
        isDead = function(o) return o.dead end,
        isDeathFinished = function(o) return o.dead end,

    },
    NPC = {
        objectIsInstance = function(o) return o ~= nil and o.kind == "npc" end,
        record = function(o) return { race = "dark elf", isMale = true } end,
        races = { record = function() return { height = { male = 1.0, female = 0.95 } } end },
    },
    Creature = { objectIsInstance = function(o) return o ~= nil and o.kind == "creature" end },
    Light = {
        createRecordDraft = function(t) return t end,
    },
    Armor = { objectIsInstance = function(o) return o ~= nil and o.kind == "armor" end },
    Clothing = { objectIsInstance = function(o) return o ~= nil and o.kind == "clothing" end },
}
packages["openmw.world"] = {
    setSimulationTimeScale = function(s) M.timeScale = s; note("timeScale=%.3f", s) end,
    getSimulationTimeScale = function() return M.timeScale end,
    createRecord = function(draft)
        M.recordCount = (M.recordCount or 0) + 1
        draft.id = "cc_light_" .. M.recordCount
        M.lastLightRecord = draft
        M.records = M.records or {}
        M.records[draft.id] = draft
        return draft
    end,
    createObject = function(recordId)
        local obj = M.newObject("light", { id = "light" .. objectCounter })
        obj.enabled = false
        local rec = M.records and M.records[recordId]
        obj.recordColor = rec and rec.color and (rec.color.r .. "," .. rec.color.g)
        return obj
    end,
}
M.rayResult = { hit = false }
packages["openmw.nearby"] = {
    players = { player },
    actors = {},
    castRay = function(from, to, opts)
        M.lastRay = { from = from, to = to, options = opts }
        return M.rayResult
    end,
    COLLISION_TYPE = { World = 1, Door = 2, Actor = 4, HeightMap = 8, Default = 15 },
}
-- The VFS is the mod folder itself, so definition files and sounds are the real ones.
M.modRoot = "."
packages["openmw.vfs"] = {
    pathsWithPrefix = function(prefix)
        local out = {}
        local cmd = string.format('find "%s/%s" -type f 2>/dev/null', M.modRoot, prefix)
        local pipe = io.popen(cmd)
        if pipe then
            for line in pipe:lines() do
                table.insert(out, (line:gsub("^%./", ""):gsub("^" .. M.modRoot .. "/", "")))
            end
            pipe:close()
        end
        local i = 0
        return function() i = i + 1 return out[i] end
    end,
    fileExists = function() return true end,
}

-- Enough YAML for the definition files: scalars, [a, b] lists and "- " items.
local function parseYaml(path)
    local root, list, item = {}, nil, nil
    local function scalar(v)
        v = v:match("^%s*(.-)%s*$")
        if v == "" then return nil end
        if v == "true" then return true end
        if v == "false" then return false end
        if v:match("^%[.*%]$") then
            local out = {}
            for piece in v:sub(2, -2):gmatch("[^,]+") do
                table.insert(out, tonumber(piece) or piece:match("^%s*(.-)%s*$"))
            end
            return out
        end
        return tonumber(v) or v
    end
    for line in io.lines(path) do
        if not line:match("^%s*#") and line:match("%S") then
            local indent = #(line:match("^%s*"))
            local dash, rest = line:match("^%s*(%-)%s*(.*)$")
            if dash then
                item = {}
                table.insert(list, item)
                line = rest
                indent = 999
            end
            local key, value = line:match("^%s*([%w_]+)%s*:%s*(.*)$")
            if key then
                local parsed = scalar(value)
                if parsed == nil then
                    list = {}
                    root[key] = list
                elseif indent > 0 and item then
                    item[key] = parsed
                else
                    root[key] = parsed
                    if indent == 0 then item = nil end
                end
            end
        end
    end
    return root
end

packages["openmw.markup"] = {
    loadYaml = function(path) return parseYaml(M.modRoot .. "/" .. path) end,
    decodeYaml = function() return {} end,
}
M.shaderEnables, M.shaderDisables = 0, 0

packages["openmw.postprocessing"] = {
    load = function(name)
        return {
            enable = function() M.shaderEnables = M.shaderEnables + 1 end,
            disable = function() M.shaderDisables = M.shaderDisables + 1 end,
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

M.renderers = {}

packages["openmw.ambient"] = { playSoundFile = function() end }
packages["openmw.interfaces"] = {
    MWUI = { templates = { box = { type = "Container" } } },
    Settings = {
        registerRenderer = function(name, fn) M.renderers[name] = fn end,
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
    UI = { isHudVisible = function() return true end },
    Combat = { addOnHitHandler = function(fn) table.insert(M.hitHandlers, fn) end },
    MSS = {
        version = 1,
        addDamageListener = function(fn) table.insert(M.damageListeners, fn) end,
        getCombatTargets = function() return M.mssTargets end,
        getInteractionTarget = function() return M.interactionTarget or { hit = false } end,
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

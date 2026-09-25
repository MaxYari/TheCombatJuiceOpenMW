-- Gear knocked loose on death: the weapon out of a dying character's hands, the
-- helmet off their head, the boots off their feet - each on its own chance - and,
-- if asked for, the rest of what they wear and carry, all thrown clear.
--
-- Split across two scripts because the engine splits it: setEquipment works only
-- in a local script and only on self, while putting an item into the world needs
-- teleport, which is global-only. So the dying actor's script decides what goes
-- and unequips it (strip), and the global script places and throws it (throw).
--
-- LuaPhysics is optional. The throw is its impulse event, so without it nothing
-- is taken at all: items taken off a corpse only to lie where it stood would be
-- worse than leaving them on.
--
-- It started out in Brutal Staggers, and moved here whole.

local mp = "scripts/MaxYari/combat juice/"

local core = require("openmw.core")
local storage = require("openmw.storage")
local types = require("openmw.types")
local util = require("openmw.util")

local DEFS = require(mp .. "defs")

local M = {}

M.PHYSICS_CONTENT_FILE = "LuaPhysicsEngine.omwscripts"

function M.physicsAvailable()
    local ok, has = pcall(function() return core.contentFiles.has(M.PHYSICS_CONTENT_FILE) end)
    return ok and has or false
end

-- Settings ------------------------------------------------------------------
--
-- A global group, unlike the rest of Combat Juice's: the actor scripts that do
-- the stripping can read global storage but not the player's.

M.DEFAULTS = {
    LooseGearEnabled = true,
    WeaponLooseChance = 1.0,
    HelmetLooseChance = 0.5,
    BootsLooseChance = 0.2,
    WornLooseChance = 0.0,
    SpillInventory = false,
}

local section = storage.globalSection(DEFS.settings.looseGear)

-- Falls back to the default while the group is not registered yet, which
-- happens on the first frames of a new game.
local function setting(key)
    local value = section:get(key)
    if value == nil then return M.DEFAULTS[key] end
    return value
end

-- The dying actor's half -----------------------------------------------------

local SLOT = types.Actor.EQUIPMENT_SLOT

-- Where an item leaves the body from. side is across the shoulders, +1 their
-- right; height is in Morrowind units up from the character's own origin.
-- Estimates, because there is no way to ask for a bone's position from Lua -
-- Bip01 sits at z 76.4 on a human, and the rest is measured off that.
local CARRY_HEIGHT = 72
local LAUNCH = {
    [SLOT.CarriedRight] = { side = 1, height = CARRY_HEIGHT },
    [SLOT.CarriedLeft] = { side = -1, height = CARRY_HEIGHT },
    [SLOT.Helmet] = { side = 0, height = 118 },
    [SLOT.Cuirass] = { side = 0, height = 95 },
    [SLOT.Shirt] = { side = 0, height = 95 },
    [SLOT.Robe] = { side = 0, height = 90 },
    [SLOT.LeftPauldron] = { side = -1, height = 105 },
    [SLOT.RightPauldron] = { side = 1, height = 105 },
    [SLOT.LeftGauntlet] = { side = -1, height = CARRY_HEIGHT },
    [SLOT.RightGauntlet] = { side = 1, height = CARRY_HEIGHT },
    [SLOT.Greaves] = { side = 0, height = 55 },
    [SLOT.Pants] = { side = 0, height = 55 },
    [SLOT.Skirt] = { side = 0, height = 55 },
    [SLOT.Belt] = { side = 0, height = 65 },
    [SLOT.Boots] = { side = 0, height = 14 },
    [SLOT.Amulet] = { side = 0, height = 100 },
    [SLOT.LeftRing] = { side = -1, height = CARRY_HEIGHT },
    [SLOT.RightRing] = { side = 1, height = CARRY_HEIGHT },
    [SLOT.Ammunition] = { side = 1, height = 85 },
}
local DEFAULT_LAUNCH = { side = 0, height = 70 }

-- The slots with a chance of their own, in the order they are rolled. The right
-- hand goes first so that the weapon is the one that reads as thrown, rather
-- than the shield. The weapon's chance is rolled for each hand.
local OWN_CHANCE = {
    { slot = SLOT.CarriedRight, key = "WeaponLooseChance" },
    { slot = SLOT.CarriedLeft, key = "WeaponLooseChance" },
    { slot = SLOT.Helmet, key = "HelmetLooseChance" },
    { slot = SLOT.Boots, key = "BootsLooseChance" },
}

-- A whole inventory can be a lot of objects, and each one is a teleport plus a
-- physics body. Past this they stay in the corpse - a setting should not be
-- able to turn a death into a frame-rate problem.
local MAX_THROWN = 50

--- Worn kit that can be knocked off: armour and clothing both.
--- Clothing matters more than it sounds - most of Morrowind is not in armour,
--- so an armour-only check leaves the majority of corpses fully dressed.
local function isWorn(item)
    local ok, worn = pcall(function()
        return types.Armor.objectIsInstance(item) or types.Clothing.objectIsInstance(item)
    end)
    return ok and worn == true
end

local function roll(chance)
    return math.random() < (chance or 0)
end

-- Straight away from whoever landed the blow, flat. nil throws them forwards.
local function awayFrom(actor, attacker)
    if attacker == nil then return nil end
    local ok, offset = pcall(function() return actor.position - attacker.position end)
    if not ok or offset == nil then return nil end
    local flat = util.vector3(offset.x, offset.y, 0)
    if flat:length() < 1e-4 then return nil end
    return flat:normalize()
end

--- Take what comes loose off `actor` (openmw.self, which setEquipment needs) and
--- hand it to the global script to throw. `attacker` may be nil.
function M.strip(actor, attacker)
    if not setting("LooseGearEnabled") or not M.physicsAvailable() then return end

    local ok, equipment = pcall(function() return types.Actor.getEquipment(actor) end)
    if not ok or equipment == nil then return end

    local keep, thrown = {}, {}
    for slot, item in pairs(equipment) do keep[slot] = item end

    local function take(slot)
        local item = keep[slot]
        if item == nil then return end
        keep[slot] = nil
        local launch = LAUNCH[slot] or DEFAULT_LAUNCH
        thrown[#thrown + 1] = { item = item, side = launch.side, height = launch.height }
    end

    -- Each rolled once, here, and never again below: a shield that stayed in
    -- the hand is not also a piece of worn armour to roll for.
    local ownChance = {}
    for _, entry in ipairs(OWN_CHANCE) do
        ownChance[entry.slot] = true
        if keep[entry.slot] ~= nil and roll(setting(entry.key)) then take(entry.slot) end
    end

    -- Every other piece rolled on its own, so a death can strip one item, or
    -- several, or none. Asked as a type rather than by slot, so a piece in a
    -- slot this does not know about still counts.
    local wornChance = setting("WornLooseChance")
    if wornChance > 0 then
        for slot, item in pairs(equipment) do
            if not ownChance[slot] and keep[slot] ~= nil and isWorn(item) and roll(wornChance) then
                take(slot)
            end
        end
    end

    if setting("SpillInventory") then
        -- getAll returns what is worn as well as what is carried, and what is
        -- worn belongs to the chances above - otherwise this would quietly strip
        -- a corpse bare as a side effect. Built from the ORIGINAL equipment, not
        -- from keep, so nothing taken above is picked up again and thrown twice.
        local worn = {}
        for _, item in pairs(equipment) do worn[item.id] = true end
        local okInv, carried = pcall(function() return types.Actor.inventory(actor):getAll() end)
        if okInv and carried ~= nil then
            for i = 1, #carried do
                local item = carried[i]
                if not worn[item.id] then
                    thrown[#thrown + 1] = { item = item, side = 0, height = DEFAULT_LAUNCH.height }
                end
            end
        end
    end

    if #thrown == 0 then return end
    while #thrown > MAX_THROWN do table.remove(thrown) end

    -- Only worth a setEquipment call if something worn actually left.
    local stripped = false
    for slot, item in pairs(equipment) do
        if keep[slot] ~= item then
            stripped = true
            break
        end
    end
    if stripped and not pcall(function() types.Actor.setEquipment(actor, keep) end) then
        return
    end

    core.sendGlobalEvent(DEFS.e.ThrowGear, {
        actor = actor.object,
        items = thrown,
        away = awayFrom(actor, attacker),
    })
end

-- The global half -----------------------------------------------------------

-- Roughly where an item leaves the body when it did not say; see LAUNCH.
local HAND_HEIGHT = 72
local HAND_SIDE = 22
local HAND_FORWARD = 8

-- The player's own throw in LuaPhysics uses 500, and applyImpulse divides by
-- mass, so a heavy weapon travels less far than a dagger. That is the point.
local IMPULSE = 350
local UPWARD = 0.75
local RANDOM_SPREAD = 0.35

-- How far from upright an item starts, in degrees, on each of the two tilt
-- axes. Facing is fully random on top of this. Laid flat, a sword reads as
-- dropped rather than flung; upright with a lean looks thrown, and LuaPhysics
-- tumbles it from there anyway, so this only has to be right for the first
-- instant.
local UPRIGHT_TILT = 30

local APPLY_IMPULSE = "LuaPhysics_ApplyImpulse"

local function randomDirection()
    -- Uniform enough on a sphere for a bit of scatter.
    local z = math.random() * 2 - 1
    local angle = math.random() * 2 * math.pi
    local r = math.sqrt(math.max(0, 1 - z * z))
    return util.vector3(r * math.cos(angle), r * math.sin(angle), z)
end

local function throwOne(actor, item, side, height, away)
    local ok, forward = pcall(function() return actor.rotation:apply(util.vector3(0, 1, 0)) end)
    if not ok then return false end
    local right = util.vector3(forward.y, -forward.x, 0)

    local position = actor.position
        + util.vector3(0, 0, height or HAND_HEIGHT)
        + right * (HAND_SIDE * side)
        + forward * HAND_FORWARD

    local function lean()
        return math.rad((math.random() * 2 - 1) * UPRIGHT_TILT)
    end
    local rotation = util.transform.rotateZ(math.random() * 2 * math.pi)
        * util.transform.rotateX(lean())
        * util.transform.rotateY(lean())

    local moved = pcall(function()
        item:teleport(actor.cell, position, { rotation = rotation })
    end)
    if not moved then return false end

    local direction = (away or forward) * (1 - UPWARD)
        + util.vector3(0, 0, 1) * UPWARD
        + randomDirection() * RANDOM_SPREAD
    if direction:length() < 1e-4 then direction = util.vector3(0, 0, 1) end

    item:sendEvent(APPLY_IMPULSE, {
        impulse = direction:normalize() * IMPULSE,
        -- No culprit: nobody should be reported to the guards for a corpse
        -- letting go of its sword.
        culprit = nil,
    })
    return true
end

--- Put the items in the world and throw them. They arrive already unequipped,
--- sitting loose in the dead actor's inventory.
function M.throw(data)
    -- The actor's script checks this before unequipping, so reaching here
    -- without LuaPhysics should not happen; if it somehow does, dropping the
    -- items on the spot with no throw is not what was asked for.
    if not M.physicsAvailable() then return end

    local actor = data and data.actor
    if actor == nil or not actor:isValid() or data.items == nil then return end

    for _, entry in ipairs(data.items) do
        if entry.item ~= nil and entry.item:isValid() then
            throwOne(actor, entry.item, entry.side or 0, entry.height, data.away)
        end
    end
end

return M

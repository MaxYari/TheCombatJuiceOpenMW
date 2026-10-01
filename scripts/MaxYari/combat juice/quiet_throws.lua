-- Every time the next dart or star of a stack comes into the hand after a
-- throw, the engine plays the weapon's equip sound, as if a new weapon were
-- being drawn. It does that on the throw animation's "shoot follow attach" key
-- (WeaponAnimation::attachArrow), nowhere else. Lua hears the key in the same
-- frame, and stopSound3d acts at once, so the sound is cut before it is heard.
-- Drawing the stack for real still sounds as it always did.
--
-- The setting lives in global storage, since NPCs throw too and their scripts
-- cannot read the player's.

local core = require("openmw.core")
local storage = require("openmw.storage")
local I = require("openmw.interfaces")

local mp = "scripts/MaxYari/combat juice/"
local DEFS = require(mp .. "defs")

local M = {}

M.DEFAULTS = {
    MuteThrownReequip = true,
}

-- The engine picks equip sounds by weapon type, and every thrown weapon gets
-- the blunt one.
local THROWN_UP_SOUND = "Item Weapon Blunt Up"

local section = storage.globalSection(DEFS.settings.soundTweaks)

-- Asked on every throw, so a change in the settings counts at once. Falls back
-- to the default while the group is not registered yet, which happens on the
-- first frames of a new game.
local function muted()
    local value = section:get("MuteThrownReequip")
    if value == nil then return M.DEFAULTS.MuteThrownReequip end
    return value
end

--- Keep `actor` (openmw.self) quiet as it takes up the next of its stack.
function M.install(actor)
    if not I.AnimationController then return end
    I.AnimationController.addTextKeyHandler("throwweapon", function(_, key)
        if key == "shoot follow attach" and muted() then core.sound.stopSound3d(THROWN_UP_SOUND, actor) end
    end)
end

return M

-- The one settings group that lives in global storage: gear knocked loose on
-- death is decided by the dying actor's own script, which can read global
-- storage but not the player's. It still shows on the Combat Juice page.

local I = require('openmw.interfaces')

local mp = "scripts/MaxYari/combat juice/"
local DEFS = require(mp .. "defs")
local looseGear = require(mp .. "loose_gear")

local defaults = looseGear.DEFAULTS

-- Checked once, at load, and written into the description so the answer is
-- where someone reading the setting will look.
local physicsNote = looseGear.physicsAvailable()
    and ("LuaPhysics (" .. looseGear.PHYSICS_CONTENT_FILE .. ") is installed, so this works.")
    or ("LuaPhysics (" .. looseGear.PHYSICS_CONTENT_FILE .. ") was NOT found, so this does " ..
        "nothing: there is no way to throw the items, and rather than leave them underfoot " ..
        "everything stays on the corpse.")

local function chance(key, name, description)
    return {
        key = key,
        renderer = "number",
        default = defaults[key],
        argument = { min = 0, max = 1 },
        name = name,
        description = description,
    }
end

local function checkbox(key, name, description)
    return { key = key, renderer = "checkbox", default = defaults[key], name = name, description = description }
end

I.Settings.registerGroup {
    key = DEFS.settings.looseGear,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Gear Knocked Loose On Death',
    order = 6,
    permanentStorage = true,
    settings = {
        checkbox('LooseGearEnabled', 'Knock Gear Loose On Death',
            "A killed character's things fly off them and land in the world, thrown away from " ..
            "whoever killed them. This moves loot out of the corpse and onto the floor. " .. physicsNote),
        chance('WeaponLooseChance', 'Weapon Chance', "Rolled for each hand, so a shield can go too."),
        chance('HelmetLooseChance', 'Helmet Chance'),
        chance('BootsLooseChance', 'Boots Chance'),
        chance('WornLooseChance', 'Chance For Each Other Worn Piece',
            "Armour and clothing both, every piece rolled on its own, so a death might strip one, " ..
            "several or none. 0 leaves them on."),
        checkbox('SpillInventory', 'Spill The Inventory',
            "Everything carried but not worn bursts out and scatters - coin, potions, keys. " ..
            "At most 50 items fly per death."),
    },
}

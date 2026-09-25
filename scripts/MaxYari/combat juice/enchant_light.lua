-- Hit lights in the colour of the enchantment a blow carried, when it fired.
--
-- The colour comes from the enchantment's effects, in the order it lists them:
-- the first that is one of the main combat elements (fire, frost, shock,
-- poison) takes that element's colour from the settings; the first that a mod
-- made itself - any effect id the game does not have - brings the colour on its
-- own record, which is how a mod's custom venom glows violet without telling
-- this one anything. Failing both, the first effect's school decides.
--
-- Whether it fired: the engine casts an on-strike enchantment, and spends its
-- charge, before any Lua hit handler hears of the blow, so an enchantment on
-- the weapon says nothing about whether this blow had the charge to use it.
-- What does is the charge dropping, so the weapon in hand is watched - the
-- player's own, nobody else's. Arrows, bolts and thrown weapons each carry their
-- own charge and always fire; the engine tries the ammo first, then the bow.

local core = require("openmw.core")
local types = require("openmw.types")

local M = {}

-- Effect id -> the setting that colours it.
M.ELEMENTS = {
    firedamage = "EnchantFireColor",
    frostdamage = "EnchantFrostColor",
    shockdamage = "EnchantShockColor",
    poison = "EnchantPoisonColor",
}

-- School (a skill id) -> the setting that colours it.
M.SCHOOLS = {
    alteration = "EnchantAlterationColor",
    conjuration = "EnchantConjurationColor",
    destruction = "EnchantDestructionColor",
    illusion = "EnchantIllusionColor",
    mysticism = "EnchantMysticismColor",
    restoration = "EnchantRestorationColor",
}

-- The game's own effects. Anything else was made by a mod.
local vanilla = {}
for _, id in pairs(core.magic.EFFECT_TYPE) do vanilla[tostring(id):lower()] = true end

local function weaponRecord(recordId)
    if not recordId then return nil end
    local ok, record = pcall(types.Weapon.record, recordId)
    return ok and record or nil
end

--- The light colour for an enchantment, or nil if it does not fire on strike.
--- setting(key) reads a colour from the settings.
function M.color(enchantId, setting)
    if not enchantId or enchantId == "" then return nil end
    local ok, record = pcall(function() return core.magic.enchantments.records[enchantId] end)
    if not ok or not record or record.type ~= core.magic.ENCHANTMENT_TYPE.CastOnStrike then return nil end
    local schoolKey
    for _, params in ipairs(record.effects) do
        local id = tostring(params.id):lower()
        if M.ELEMENTS[id] then return setting(M.ELEMENTS[id]) end
        local effect = params.effect
        if effect and not vanilla[id] and effect.color then return effect.color end
        schoolKey = schoolKey or (effect and M.SCHOOLS[tostring(effect.school):lower()])
    end
    return schoolKey and setting(schoolKey) or nil
end

-- The weapon in hand -------------------------------------------------------------

local watched = { item = nil, charge = nil }
local fired = { at = -1000, enchant = nil }

--- Read the charge of the weapon in hand. A drop since the last read means it
--- just fired its enchantment. Call once an update, and again as a hit is
--- reported, so the drop is seen whichever of the two comes first.
function M.sample(item, now)
    local charge = nil
    if item then
        local ok, data = pcall(types.Item.itemData, item)
        charge = ok and data and data.enchantmentCharge or nil
    end
    if item and item == watched.item and charge and watched.charge and charge < watched.charge - 1e-3 then
        local record = weaponRecord(item.recordId)
        fired.at, fired.enchant = now, record and record.enchant
    end
    watched.item, watched.charge = item, charge
end

-- How long after the charge drops a reported hit still counts as the one that
-- spent it: the hit's report arrives a frame or so behind the blow.
local FIRED_WINDOW = 0.3

--- The colour the blow's enchantment gives its light, or nil. hit carries the
--- weapon and ammo record ids the victim reported; inHand is the weapon the
--- player holds now, read again here.
function M.hitColor(hit, inHand, now, setting)
    local ammo = weaponRecord(hit.ammo)
    local color = ammo and M.color(ammo.enchant, setting)
    if color then return color end

    local weapon = weaponRecord(hit.weapon)
    if weapon and weapon.type == types.Weapon.TYPE.MarksmanThrown then
        return M.color(weapon.enchant, setting)
    end

    M.sample(inHand, now)
    if now - fired.at > FIRED_WINDOW then return nil end
    -- One firing, one hit: a quick second blow without the charge for it is plain.
    fired.at = -1000
    return M.color(fired.enchant, setting)
end

return M

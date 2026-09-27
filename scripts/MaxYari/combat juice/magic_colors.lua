-- The colours of magic, from the Magic Colours settings group: the main combat
-- elements (fire, frost, shock, poison) have their own, anything else takes its
-- school's. An effect a mod made itself - any effect id the game does not have -
-- brings the colour on its own record, which is how a mod's custom venom glows
-- violet without telling this one anything.
--
-- Enchanted hit lights and the hit markers of spell damage both use them.

local core = require("openmw.core")

local M = {}

-- Effect id -> the setting that colours it.
M.ELEMENTS = {
    firedamage = "FireColor",
    frostdamage = "FrostColor",
    shockdamage = "ShockColor",
    poison = "PoisonColor",
}

-- School (a skill id) -> the setting that colours it.
M.SCHOOLS = {
    alteration = "AlterationColor",
    conjuration = "ConjurationColor",
    destruction = "DestructionColor",
    illusion = "IllusionColor",
    mysticism = "MysticismColor",
    restoration = "RestorationColor",
}

-- The game's own effects. Anything else was made by a mod.
local vanilla = {}
for _, id in pairs(core.magic.EFFECT_TYPE) do vanilla[tostring(id):lower()] = true end

function M.isVanilla(id)
    return vanilla[tostring(id):lower()] == true
end

--- The colour of one magic effect, or nil. setting(key) reads a colour from the
--- settings.
function M.effectColor(id, setting)
    if id == nil then return nil end
    id = tostring(id):lower()
    if M.ELEMENTS[id] then return setting(M.ELEMENTS[id]) end
    local ok, effect = pcall(function() return core.magic.effects.records[id] end)
    if not ok or not effect then return nil end
    if not vanilla[id] and effect.color then return effect.color end
    local school = M.SCHOOLS[tostring(effect.school):lower()]
    return school and setting(school) or nil
end

return M

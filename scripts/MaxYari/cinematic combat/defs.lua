local prefix = "CC_"

-- When an effect is allowed to play. A single kill can satisfy several of these
-- at once - the last enemy of a long fight is also an encounter end and also
-- just a kill - so each effect names the *loosest* case it accepts, and a kill
-- qualifies if it is that case or a stricter one.
local TRIGGER = {
    Never = "Never",
    EveryKill = "Every kill",
    EncounterEnd = "Encounter end",
    LongEncounterEnd = "Long encounter end",
}

-- How strict each one is; higher is stricter.
local TRIGGER_RANK = {
    [TRIGGER.EveryKill] = 1,
    [TRIGGER.EncounterEnd] = 2,
    [TRIGGER.LongEncounterEnd] = 3,
}

return {
    modName = "Cinematic Combat",
    modId = "CinematicCombat", -- identifies this mod to Dynamic Camera's extra angle API

    TRIGGER = TRIGGER,
    TRIGGER_RANK = TRIGGER_RANK,
    TRIGGER_ITEMS = { TRIGGER.Never, TRIGGER.EveryKill, TRIGGER.EncounterEnd, TRIGGER.LongEncounterEnd },

    -- Events. Actor -> player, player -> global.
    e = {
        AttackLanded = prefix .. "AttackLanded", -- victim actor -> attacking player
        ActorKilled = prefix .. "ActorKilled",   -- victim actor -> the player who killed it
        Slowdown = prefix .. "Slowdown",         -- player -> global, asks for a time scale dip
        SpawnLight = prefix .. "SpawnLight",     -- player -> global, asks for a light flash
    },

    -- Settings groups, also the names of their storage sections.
    settings = {
        slowdown = "SettingsCinematicCombatSlowdown",
        camera = "SettingsCinematicCombatCamera",
        flash = "SettingsCinematicCombatFlash",
        effects = "SettingsCinematicCombatEffects",
    },

    -- Impact Effects materials that throw sparks. Everything else on an actor
    -- gets the weaker, warmer light instead.
    sparkMaterials = {
        Metal = true,
        MetalHeavy = true,
        ParryArmorHeavy = true,
        ParryArmorIce = true,
        DmgDwemer = true,
        Stone = true,
    },
}

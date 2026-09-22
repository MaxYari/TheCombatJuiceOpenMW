local prefix = "CC_"

return {
    modName = "Cinematic Combat",
    modId = "CinematicCombat", -- identifies this mod to Dynamic Camera's extra angle API

    -- Events. Actor -> player, player -> global.
    e = {
        AttackLanded = prefix .. "AttackLanded", -- victim actor -> attacking player
        ActorKilled = prefix .. "ActorKilled",   -- victim actor -> the player who killed it
        TimeEffect = prefix .. "TimeEffect",     -- player -> global, asks for a time scale effect
        SparkFlash = prefix .. "SparkFlash",     -- player -> global, asks for a light flash
        SyncShared = prefix .. "SyncShared",     -- player -> global, mirrors settings actors can read
    },

    -- Settings groups, also the names of their storage sections.
    settings = {
        hitstop = "SettingsCinematicCombatHitstop",
        slowdown = "SettingsCinematicCombatSlowdown",
        camera = "SettingsCinematicCombatCamera",
        effects = "SettingsCinematicCombatEffects",
    },

    -- Written by the global script, read by actor scripts. Player storage is off
    -- limits to them, so the few values they need come through here.
    sharedStorage = "CinematicCombatShared",

    -- Impact Effects materials that spark. Anything in here gets a light flash.
    sparkMaterials = {
        Metal = true,
        MetalHeavy = true,
        ParryArmorHeavy = true,
        ParryArmorIce = true,
        DmgDwemer = true,
        Stone = true,
    },
}

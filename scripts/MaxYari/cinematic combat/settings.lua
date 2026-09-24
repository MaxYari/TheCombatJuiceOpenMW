local I = require('openmw.interfaces')
local util = require("openmw.util")

local mp = "scripts/MaxYari/cinematic combat/"
local DEFS = require(mp .. "defs")

local function number(key, name, default, min, max, description)
    return {
        key = key,
        renderer = "number",
        default = default,
        argument = { min = min, max = max },
        name = name,
        description = description,
    }
end

local function checkbox(key, name, default, description)
    return { key = key, renderer = "checkbox", default = default, name = name, description = description }
end

-- When does an effect play? Every trigger this mod has offers the same choices,
-- and a kill can satisfy several of them at once (see defs.TRIGGERS).
local function select(key, name, default, items, description)
    return {
        key = key,
        renderer = "select",
        default = default,
        argument = { l10n = 'CinematicCombat', items = items },
        name = name,
        description = description,
    }
end

local function trigger(key, name, default, description)
    return select(key, name, default, DEFS.TRIGGER_ITEMS, description)
end

I.Settings.registerPage {
    key = 'CinematicCombatPage',
    l10n = 'CinematicCombat',
    name = 'Cinematic Combat',
    description = "~~ Kill slow motion, an exposure blow-out on the kill, camera shake and better " ..
        "sparks. The spark meshes are a mesh replacer and are always on - to turn them off, " ..
        "remove the meshes/e/impact folder from this mod.",
}

I.Settings.registerGroup {
    key = DEFS.settings.slowdown,
    page = 'CinematicCombatPage',
    l10n = 'CinematicCombat',
    name = 'Slow Motion',
    order = 1,
    permanentStorage = true,
    settings = {
        checkbox('SlowdownEnabled', 'Enable Slow Motion', true,
            "Slow motion on a kill. There are two of them, a short dip and a long one; " ..
            "when a kill qualifies for both, the longer one plays."),

        trigger('SmallSlowdownTrigger', 'Short Slow Motion On', DEFS.TRIGGER.EveryKill,
            "Which kills get the short dip."),
        number('SmallSlowdownChance', 'Short Slow Motion Chance', 1, 0, 1,
            "Chance it plays on a kill that qualifies. 1 is always."),
        number('SmallSlowdownScale', 'Short Slow Motion Time Scale', 0.45, 0.01, 1,
            "How slow the world gets at the deepest point."),
        number('SmallSlowdownDuration', 'Short Slow Motion Duration', 0.45, 0.05, nil,
            "Seconds of real time for the whole dip, easing in and out included."),

        trigger('BigSlowdownTrigger', 'Long Slow Motion On', DEFS.TRIGGER.LongEncounterEnd,
            "Which kills get the long one. It beats the short one whenever both qualify."),
        number('BigSlowdownChance', 'Long Slow Motion Chance', 1, 0, 1,
            "Chance it plays on a kill that qualifies. 1 is always."),
        number('BigSlowdownScale', 'Long Slow Motion Time Scale', 0.2, 0.01, 1,
            "How slow the world gets at the deepest point."),
        number('BigSlowdownDuration', 'Long Slow Motion Duration', 1.5, 0.05, nil,
            "Seconds of real time for the whole thing, easing in and out included. 1.5 is what " ..
            "Dynamic Reticle's kill slowdown actually came to: its settings read 0.05/0.1/0.3, " ..
            "but it counted them in simulation time, which stretches while the world is slowed."),

        number('LongEncounterSeconds', 'A Long Fight Is This Many Seconds', 20, 0, nil,
            "A fight counts as long once this much time has passed since it started."),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.camera,
    page = 'CinematicCombatPage',
    l10n = 'CinematicCombat',
    name = 'Camera Shake',
    order = 2,
    permanentStorage = true,
    settings = {
        checkbox('ShakeEnabled', 'Enable Camera Shake', true,
            "Shakes the camera when a hit lands. Goes through Dynamic Camera's extra angle API " ..
            "when that mod is installed, so the two don't fight over the camera."),
        number('ShakeStrength', 'Shake Strength', 1.0, 0, nil,
            "Peak shake angle in degrees."),
        number('ShakeDuration', 'Shake Duration', 0.3, 0, nil,
            "Seconds of real time the shake decays over."),
        number('ShakeFrequency', 'Shake Frequency', 38, 1, nil,
            "How fast the camera rattles, in wobbles per second."),
        number('ShakeTakenHitFactor', 'Strength When You Are Hit', 0, 0, nil,
            "Multiplies the shake when the hit lands on you rather than on your target. " ..
            "0 means your own hits shake the camera and theirs do not."),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.flash,
    page = 'CinematicCombatPage',
    l10n = 'CinematicCombat',
    name = 'Kill Flash',
    order = 3,
    permanentStorage = true,
    settings = {
        select('FlashOn', 'Kill Flash On', DEFS.FLASH_ON.Short, DEFS.FLASH_ON_ITEMS,
            "Which slow motion the flash rides along with. It runs for exactly as long as that " ..
            "slow motion does, so the two always end together and there is no separate duration " ..
            "to keep in step.\n\nThe image smears out from the middle of the screen, the " ..
            "highlights bloom cold and the light in the room turns blue for a moment. Every part " ..
            "of it can be tuned live in the post processing HUD (F2 by default)."),
        number('FlashStrength', 'Kill Flash Strength', 1.0, 0, nil,
            "Multiplies the whole effect."),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.effects,
    page = 'CinematicCombatPage',
    l10n = 'CinematicCombat',
    name = 'Impact Lights',
    order = 4,
    permanentStorage = true,
    settings = {
        checkbox('SparkLightEnabled', 'Light Flash On Sparks', true,
            "Spawns a very short lived light where sparks appear. Needs OpenMW Impact Effects, " ..
            "which is what decides where sparks happen."),
        number('SparkLightRadius', 'Spark Light Radius', 160, 20, nil,
            "Radius of that light in game units."),
        number('SparkLightDuration', 'Spark Light Duration', 0.09, 0.01, nil,
            "Seconds of real time the light stays on."),
        {
            key = 'SparkLightColor',
            renderer = 'color',
            default = util.color.rgb(0.62, 0.78, 1.0),
            name = 'Spark Light Colour',
            description = "Changing this makes a new light record the first time it is used.",
        },

        checkbox('HitLightEnabled', 'Light Flash On Other Hits', true,
            "A weaker, warmer version of the same flash for hits that throw no sparks - flesh, " ..
            "cloth, light armour. Meant to be barely noticed."),
        number('HitLightRadius', 'Other Hit Light Radius', 30, 5, nil,
            "Radius of that light in game units."),
        number('HitLightDuration', 'Other Hit Light Duration', 0.06, 0.01, nil,
            "Seconds of real time the light stays on."),
        {
            key = 'HitLightColor',
            renderer = 'color',
            default = util.color.rgb(1.0, 0.78, 0.45),
            name = 'Other Hit Light Colour',
            description = "Changing this makes a new light record the first time it is used.",
        },

        checkbox('SparkVariety', 'Vary The Spark Bursts', true,
            "Several bursts are baked for each kind of impact, some of them with a cluster of " ..
            "sparks thrown much harder than the rest, and one is picked at random every time. " ..
            "Off means the same burst every hit."),

        checkbox('SparksOnMediumArmor', 'Sparks On Medium Armour', true,
            "Impact Effects already sparks off heavy armour, shields and metal, but medium " ..
            "armour only gets a sound. This sparks off medium armour as well."),
    },
}

return DEFS.settings

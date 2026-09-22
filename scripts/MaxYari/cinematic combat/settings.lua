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

I.Settings.registerPage {
    key = 'CinematicCombatPage',
    l10n = 'CinematicCombat',
    name = 'Cinematic Combat',
    description = "~~ Hit stops, kill slow motion, camera shake and better sparks. " ..
        "The spark meshes are a mesh replacer and are always on - to turn them off, remove " ..
        "the meshes/e/impact folder from this mod.",
}

I.Settings.registerGroup {
    key = DEFS.settings.hitstop,
    page = 'CinematicCombatPage',
    l10n = 'CinematicCombat',
    name = 'Hit Stop',
    order = 1,
    permanentStorage = true,
    settings = {
        checkbox('HitstopEnabled', 'Enable Hit Stops', true,
            "Briefly slows the whole world down the moment a hit lands."),
        number('HitstopTimeScale', 'Hit Stop Time Scale', 0.1, 0.01, 1,
            "How slow the world gets during a hit stop. 0.1 is a tenth of normal speed. " ..
            "Applied and released abruptly, no easing."),
        number('HitstopDuration', 'Hit Stop Duration', 0.1, 0, 1,
            "Seconds of real time the hit stop lasts."),
        checkbox('HitstopOnPlayerHit', 'Hit Stop When You Get Hit', true,
            "Also do a hit stop when an enemy lands a hit on you."),
        checkbox('HitstopOnMiss', 'Hit Stop On Misses', false,
            "Do a shorter hit stop when your attack is dodged or blocked by the dice roll."),
        number('HitstopMissFactor', 'Miss Hit Stop Length', 0.5, 0, 1,
            "Miss hit stop duration, as a fraction of the normal one."),
        number('HitFreezeFrames', 'Frames Held At The Hit Key', 2, 0, 5,
            "The attack animation is paused for this many frames the instant its hit key fires, " ..
            "before anyone knows whether the attack landed. Without it the weapon swings a frame " ..
            "or two past the contact pose while the hit result travels between scripts. " ..
            "2 is usually right; drop to 0 if you dislike the hold on misses."),
        checkbox('FreezeNpcAttacks', 'Hold Enemy Attacks Too', true,
            "Applies the same hit key hold to enemies attacking you."),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.slowdown,
    page = 'CinematicCombatPage',
    l10n = 'CinematicCombat',
    name = 'Kill Slow Motion',
    order = 2,
    permanentStorage = true,
    settings = {
        checkbox('SlowdownEnabled', 'Enable Kill Slow Motion', true,
            "Slow motion when you kill somebody. Moved here out of Dynamic Reticle."),
        checkbox('SlowdownOnLastEnemy', 'Always On The Last Enemy', true,
            "Guarantees the slow motion on the kill that ends a fight - the same 'nobody is " ..
            "fighting any more' signal the engine uses to stop the combat music."),
        number('SlowdownOnKillChance', 'Chance On Any Other Kill', 0, 0, 1,
            "Chance of slow motion on a kill that does not end the fight. 0 means only the " ..
            "last enemy of an encounter triggers it."),
        number('SlowdownTimeScale', 'Slow Motion Time Scale', 0.2, 0.01, 1,
            "How slow the world gets at the deepest point."),
        number('SlowdownInTime', 'Ease In Time', 0.05, 0, 2, "Seconds of real time to slow down over."),
        number('SlowdownHoldTime', 'Hold Time', 0.1, 0, 5, "Seconds of real time to stay slow."),
        number('SlowdownOutTime', 'Ease Out Time', 0.3, 0, 5, "Seconds of real time to speed back up over."),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.camera,
    page = 'CinematicCombatPage',
    l10n = 'CinematicCombat',
    name = 'Camera Shake',
    order = 3,
    permanentStorage = true,
    settings = {
        checkbox('ShakeEnabled', 'Enable Camera Shake', true,
            "Shakes the camera along with the hit stop. Goes through Dynamic Camera's extra " ..
            "angle API when that mod is installed, so the two don't fight over the camera."),
        number('ShakeStrength', 'Shake Strength', 1.2, 0, 15,
            "Peak shake angle in degrees."),
        number('ShakeDuration', 'Shake Duration', 0.18, 0, 2,
            "Seconds of real time the shake decays over."),
        number('ShakeFrequency', 'Shake Frequency', 38, 1, 120,
            "How fast the camera rattles, in wobbles per second."),
        number('ShakeTakenHitFactor', 'Strength When You Are Hit', 1.5, 0, 5,
            "Multiplies the shake when the hit lands on you rather than on your target."),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.effects,
    page = 'CinematicCombatPage',
    l10n = 'CinematicCombat',
    name = 'Impact Effects',
    order = 4,
    permanentStorage = true,
    settings = {
        checkbox('KillFlashEnabled', 'Kill Vignette', true,
            "A quick post processing pulse on a kill: the screen edges drop into shadow while " ..
            "the middle lifts. It is a gamma bend rather than a colour wash, so the image " ..
            "keeps its own colours."),
        number('KillFlashStrength', 'Kill Vignette Strength', 1.0, 0, 2,
            "Multiplies both the darkening and the brightening."),
        number('KillFlashDuration', 'Kill Vignette Duration', 0.45, 0.05, 3,
            "Seconds of real time for the whole pulse."),
        checkbox('SparkLightEnabled', 'Light Flash On Sparks', true,
            "Spawns a very short lived light where sparks appear. Needs OpenMW Impact Effects, " ..
            "which is what decides where sparks happen."),
        number('SparkLightRadius', 'Spark Light Radius', 160, 20, 600,
            "Radius of that light in game units."),
        number('SparkLightDuration', 'Spark Light Duration', 0.09, 0.01, 1,
            "Seconds of real time the light stays on."),
        {
            key = 'SparkLightColor',
            renderer = 'color',
            default = util.color.rgb(0.62, 0.78, 1.0),
            name = 'Spark Light Colour',
            description = "Changing this makes a new light record the first time it is used.",
        },
        checkbox('SparksOnMediumArmor', 'Sparks On Medium Armour', false,
            "Impact Effects already sparks off heavy armour, shields and metal, but medium " ..
            "armour only gets a sound. Turn this on to spark off medium armour as well."),
    },
}

return {
    hitstop = DEFS.settings.hitstop,
    slowdown = DEFS.settings.slowdown,
    camera = DEFS.settings.camera,
    effects = DEFS.settings.effects,
}

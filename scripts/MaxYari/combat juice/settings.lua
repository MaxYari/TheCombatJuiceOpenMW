local I = require('openmw.interfaces')
local util = require("openmw.util")

local mp = "scripts/MaxYari/combat juice/"
local DEFS = require(mp .. "defs")
local hitmarkers = require(mp .. "hitmarkers")
local sounds = require(mp .. "sounds")

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

local function select(key, name, default, items, description)
    return {
        key = key,
        renderer = "select",
        default = default,
        argument = { l10n = 'CombatJuice', items = items },
        name = name,
        description = description,
    }
end

-- Which kills an effect takes. A kill can satisfy several at once; each effect
-- names the loosest it accepts.
local function trigger(key, name, default, description)
    return select(key, name, default, DEFS.TRIGGER_ITEMS, description)
end

I.Settings.registerPage {
    key = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Combat Juice',
    description = "~~ Kill slow motion, a flash on the kill, camera shake, hit markers and better sparks.",
}

I.Settings.registerGroup {
    key = DEFS.settings.slowdown,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Slow Motion',
    order = 1,
    permanentStorage = true,
    settings = {
        checkbox('SlowdownEnabled', 'Enable Slow Motion', true),

        trigger('SmallSlowdownTrigger', 'Short Slow Motion On', DEFS.TRIGGER.EveryKill),
        number('SmallSlowdownChance', 'Short Slow Motion Chance', 1, 0, 1),
        number('SmallSlowdownScale', 'Short Slow Motion Time Scale', 0.45, 0.01, 1),
        number('SmallSlowdownDuration', 'Short Slow Motion Duration', 1.0, 0.05, nil,
            "Seconds of real time, easing included."),

        trigger('BigSlowdownTrigger', 'Long Slow Motion On', DEFS.TRIGGER.LongEncounterEnd),
        number('BigSlowdownChance', 'Long Slow Motion Chance', 1, 0, 1),
        number('BigSlowdownScale', 'Long Slow Motion Time Scale', 0.2, 0.01, 1),
        number('BigSlowdownDuration', 'Long Slow Motion Duration', 1.5, 0.05, nil,
            "Seconds of real time. When a kill qualifies for both, the longer one plays."),

        number('LongEncounterSeconds', 'A Long Fight Is This Many Seconds', 20, 0, nil),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.camera,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Camera Shake',
    order = 2,
    permanentStorage = true,
    settings = {
        checkbox('ShakeEnabled', 'Enable Camera Shake', true),
        number('ShakeStrength', 'Shake Strength', 1.0, 0, nil, "Peak angle in degrees."),
        number('ShakeDuration', 'Shake Duration', 0.3, 0, nil, "Seconds of real time."),
        number('ShakeFrequency', 'Shake Frequency', 38, 1, nil, "Wobbles per second."),
        checkbox('ShakeScalesWithDamage', 'Scale Shake With Damage Dealt', true,
            "Strength and duration run from half to half again, by the share of the victim's " ..
            "health the blow took: half at a tenth or less, half again at two fifths or more."),
        number('ShakeTakenHitFactor', 'Strength When You Are Hit', 0, 0, nil,
            "0 means only your own hits shake the camera."),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.flash,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Kill Flash',
    order = 3,
    permanentStorage = true,
    settings = {
        select('FlashOn', 'Kill Flash On', DEFS.FLASH_ON.Short, DEFS.FLASH_ON_ITEMS,
            "Which slow motion it rides. It runs for as long as that slow motion does."),
        number('FlashStrength', 'Kill Flash Strength', 1.0, 0, nil,
            "The look itself is tuned in the post processing HUD (F2)."),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.effects,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Impact Lights',
    order = 4,
    permanentStorage = true,
    settings = {
        checkbox('SparkLightEnabled', 'Light Flash On Sparks', true, "Needs OpenMW Impact Effects."),
        number('SparkLightRadius', 'Spark Light Radius', 160, 20, nil),
        number('SparkLightDuration', 'Spark Light Duration', 0.09, 0.01, nil),
        number('SparkLightPower', 'Spark Light Power', 1.0, nil, nil,
            "Brightness, apart from reach. Negative gives a negative light."),
        {
            key = 'SparkLightColor',
            renderer = 'color',
            default = util.color.rgb(0.62, 0.78, 1.0),
            name = 'Spark Light Colour',
        },

        checkbox('HitLightEnabled', 'Light Flash On Other Hits', true,
            "For hits that throw no sparks. Only on what you hit."),
        number('HitLightRadius', 'Other Hit Light Radius', 90, 5, nil),
        number('HitLightDuration', 'Other Hit Light Duration', 0.2, 0.01, nil),
        number('HitLightPower', 'Other Hit Light Power', 0.75, nil, nil),
        {
            key = 'HitLightColor',
            renderer = 'color',
            default = util.color.rgb(0.533, 0.031, 0.031),
            name = 'Other Hit Light Colour',
        },

        checkbox('SparkVariety', 'Vary The Spark Bursts', true,
            "Picks one of several baked bursts per hit instead of the same one."),
        checkbox('SparksOnMediumArmor', 'Sparks On Medium Armour', true,
            "Impact Effects gives medium armour a sound but no sparks; this fills that in."),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.markers,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Hit Markers',
    order = 5,
    permanentStorage = true,
    settings = {
        checkbox('MarkersEnabled', 'Show Hit Markers', true),
        select('HitMarker', 'Hit Marker', 'faded_triangles', hitmarkers.ids,
            "Every definition in hitmarkers/ is listed here, from this mod or any other."),
        select('KillMarker', 'Kill Marker', 'cross', hitmarkers.ids),
        number('MarkerScale', 'Marker Size', 0.75, 0.05, nil),
        number('MarkerOpacity', 'Marker Opacity', 1.0, 0, 1),
        number('WeakMarkerOpacity', 'Glancing Hit Opacity', 0.0, 0, 1,
            "For glancing hits, if a mod reports them. 0 hides them."),
        {
            key = 'MarkerColor',
            renderer = 'color',
            default = util.color.rgb(0.929, 0.8, 0.624),
            name = 'Hit Marker Colour',
            description = "Markers whose definition says recolour: false keep their own colours.",
        },
        {
            key = 'KillMarkerColor',
            renderer = 'color',
            default = util.color.rgb(0.91, 0.145, 0.196),
            name = 'Kill Marker Colour',
        },
    },
}

local function soundSelect(key, name, default, description)
    return {
        key = key,
        renderer = 'cjSoundSelect',
        default = default,
        argument = { items = sounds.names, paths = sounds.paths },
        name = name,
        description = description,
    }
end

I.Settings.registerGroup {
    key = DEFS.settings.markerSounds,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Hit Marker Sounds',
    order = 6,
    permanentStorage = true,
    settings = {
        soundSelect('HitMarkerSound', 'Hit Sound', 'fps_meaty_hit', "Press play to hear it."),
        number('HitMarkerVolume', 'Hit Volume', 2.0, 0, nil),
        soundSelect('DeathMarkerSound', 'Kill Sound', 'bass_stab'),
        number('DeathMarkerVolume', 'Kill Volume', 2.0, 0, nil),
        number('MarkerSoundPitchMin', 'Pitch Minimum', 0.8, 0.1, nil),
        number('MarkerSoundPitchMax', 'Pitch Maximum', 1.2, 0.1, nil),
        checkbox('MeleeSound', 'Play With Melee', false),
        checkbox('MarksmanSound', 'Play With Marksman', true),
        checkbox('SpellcasterSound', 'Play With Spells', true),
    },
}

return DEFS.settings

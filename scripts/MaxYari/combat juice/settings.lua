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

-- A hit marker picker with a preview of the marker, drawn in `colorKey`'s
-- colour. The renderer lives in menu.lua.
local function markerSelect(key, name, default, colorKey, description)
    return {
        key = key,
        renderer = 'cjMarkerSelect',
        default = default,
        argument = { items = hitmarkers.ids, colorKey = colorKey },
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
        number('SmallSlowdownChance', 'Short Slow Motion Chance', 0.25, 0, 1),
        number('SmallSlowdownScale', 'Short Slow Motion Time Scale', 0.3, 0.01, 1),
        number('SmallSlowdownDuration', 'Short Slow Motion Duration', 1.0, 0.05, nil,
            "Seconds of real time, easing included."),

        trigger('BigSlowdownTrigger', 'Long Slow Motion On', DEFS.TRIGGER.LongEncounterEnd),
        number('BigSlowdownChance', 'Long Slow Motion Chance', 1, 0, 1),
        number('BigSlowdownScale', 'Long Slow Motion Time Scale', 0.2, 0.01, 1),
        number('BigSlowdownDuration', 'Long Slow Motion Duration', 2.0, 0.05, nil,
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
        select('FlashOn', 'Kill Flash On', DEFS.FLASH_ON.Long, DEFS.FLASH_ON_ITEMS,
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

        checkbox('StaminaLightEnabled', 'Light Flash On Stamina Hits', true,
            "For blows that take only stamina - fists, mostly. A blow that takes health gets the one above."),
        number('StaminaLightRadius', 'Stamina Hit Light Radius', 70, 5, nil),
        number('StaminaLightDuration', 'Stamina Hit Light Duration', 0.15, 0.01, nil),
        number('StaminaLightPower', 'Stamina Hit Light Power', 0.3, nil, nil),
        {
            key = 'StaminaLightColor',
            renderer = 'color',
            default = util.color.rgb(1.0, 0.5, 0.15),
            name = 'Stamina Hit Light Colour',
        },

        checkbox('SparkVariety', 'Vary The Spark Bursts', true,
            "Picks one of several baked bursts per hit instead of the same one."),
        checkbox('SparksOnMediumArmor', 'Sparks On Medium Armour', true,
            "Impact Effects gives medium armour a sound but no sparks; this fills that in."),
    },
}

local function color(key, name, r, g, b, description)
    return { key = key, renderer = 'color', default = util.color.rgb(r, g, b), name = name, description = description }
end

-- Colours for blows whose cast-on-strike enchantment fired. The elements take
-- their own; everything else its school's. Poison is the median colour of the
-- effect burning on the victim (its hit visual), fire halfway between that
-- visual's red glow and its orange flames, since the glow alone is the plain hit
-- light's red. Frost and shock are picked to read as ice and lightning: the
-- game's own would make shock the paler of the two. The school colours are the
-- game's too:
-- the median colour of the particles on the caster's hand while a spell of that
-- school is cast (each school's magic_cast_*.nif, its textures under the tints
-- its materials give them), brightened until its strongest channel is full, so
-- that the power setting alone decides how bright a light is.
I.Settings.registerGroup {
    key = DEFS.settings.enchantLights,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Enchanted Hit Lights',
    order = 4.5,
    permanentStorage = true,
    settings = {
        checkbox('EnchantLightEnabled', 'Colour Hit Lights By Enchantment', true,
            "When a blow's cast-on-strike enchantment actually fires - it has the charge - the hit " ..
            "light takes its colour, sparks or not. The main elements have their own below, anything " ..
            "else its school's, and a mod's own magic effect brings its own. Radius and duration are " ..
            "the hit light's."),
        number('EnchantLightPower', 'Enchanted Hit Light Power', 0.6, nil, nil),
        color('EnchantFireColor', 'Fire', 1.0, 0.28, 0.15,
            "Halfway between the red glow and the orange flames of fire burning on a body."),
        color('EnchantFrostColor', 'Frost', 0.72, 0.85, 1.0),
        color('EnchantShockColor', 'Shock', 0.35, 0.55, 1.0),
        color('EnchantPoisonColor', 'Poison', 0.69, 1.0, 0.2),
        color('EnchantAlterationColor', 'Alteration', 0.97, 0.66, 1),
        color('EnchantConjurationColor', 'Conjuration', 1, 0.87, 0.59),
        color('EnchantDestructionColor', 'Destruction', 1, 0.46, 0.1,
            "For destruction effects other than the four elements above."),
        color('EnchantIllusionColor', 'Illusion', 0.24, 1, 0.19),
        color('EnchantMysticismColor', 'Mysticism', 0.81, 0.68, 1),
        color('EnchantRestorationColor', 'Restoration', 0.55, 0.62, 1),
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
        markerSelect('HitMarker', 'Hit Marker', 'faded_triangles', 'MarkerColor',
            "Every definition in hitmarkers/ is listed here, from this mod or any other."),
        markerSelect('KillMarker', 'Kill Marker', 'cross', 'KillMarkerColor'),
        {
            key = 'MarkerSizes',
            renderer = 'cjMarkerSizes',
            default = {},
            name = 'Marker Sizes',
            description = "Every marker keeps its own size, set with - and + under its preview.",
        },
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
        checkbox('StaminaMarkers', 'Show Markers On Stamina Hits', true,
            "The hit marker, in its own colour, for blows that take only stamina - fists, mostly. " ..
            "A blow that takes health as well shows the ordinary one."),
        {
            key = 'StaminaMarkerColor',
            renderer = 'color',
            default = util.color.rgb(0.09, 0.64, 0.26),
            name = 'Stamina Hit Marker Colour',
            description = "Morrowind's fatigue-bar green, a touch brighter.",
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
        soundSelect('HitMarkerSound', 'Hit Sound', 'bass_stab', "Press play to hear it."),
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

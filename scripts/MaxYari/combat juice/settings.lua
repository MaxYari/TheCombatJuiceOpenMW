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
    description = "Just that combat sauce! Does not change gameplay mechanics, purely an visual and auditory feast.",
}

-- The logo at the top of the page, as a group of one setting whose renderer
-- (cjLogo, in menu.lua) draws it; the same trick as They Bleed's.
I.Settings.registerGroup {
    key = DEFS.settings.logo,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = '',
    order = 0,
    permanentStorage = false,
    settings = {
        { key = 'Logo', renderer = 'cjLogo', default = '', name = '' },
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.slowdown,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Slow Motion',
    description = "Short slow motion on kill and on combat end. You are the ONE!",
    order = 4,
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
    description = "Fairly subtle by default, adds an oompf to a landed hit.",
    order = 3,
    permanentStorage = true,
    settings = {
        checkbox('ShakeEnabled', 'Enable Camera Shake', true),
        number('ShakeStrength', 'Shake Strength', 1.0, 0, nil, "Peak angle in degrees."),
        number('ShakeDuration', 'Shake Duration', 0.3, 0, nil, "Seconds of real time."),
        number('ShakeFrequency', 'Shake Frequency', 38, 1, nil, "Wobbles per second."),
        checkbox('ShakeScalesWithDamage', 'Scale Shake With Damage Dealt', true, "Should harder hits shake harder, based on a percentage of total HP that enemy lost on this hit, not on absolute weapon damage."),
        number('ShakeTakenHitFactor', 'Strength When You Are Hit', 0, 0, nil,
            "if above 0 - hits that land on you will shake the camera."),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.flash,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Kill Flash Shader',
    description = "A blown explosure shader effect that can play alongside the on-kill slowmotion.",
    order = 5,
    permanentStorage = true,
    settings = {
        select('FlashOn', 'Kill Flash On', DEFS.FLASH_ON.Long, DEFS.FLASH_ON_ITEMS,
            "~I heard you sang a good song, I heard you had a style."),
        number('FlashStrength', 'Kill Flash Strength', 1.0, 0, nil,
            "Can be tuned more in the post processing HUD (F2)."),
    },
}

I.Settings.registerGroup {
    key = DEFS.settings.effects,
    page = 'CombatJuicePage',
    l10n = 'CombatJuice',
    name = 'Impact Lights',
    description = "A flash of light on hit, subtle-ish by default, but I can certainly see how some will want to turn it down.",
    order = 7,
    permanentStorage = true,
    settings = {
        checkbox('SparkLightEnabled', 'Light Flash On Sparks', true, "Add light flashes to spark particle effects? Needs OpenMW Impact Effects as that's what actually places the sparks on armor and environment hits."),
        number('SparkLightRadius', 'Spark Light Radius', 160, 20, nil),
        number('SparkLightDuration', 'Spark Light Duration', 0.09, 0.01, nil),
        number('SparkLightPower', 'Spark Light Power', 1.0, nil, nil,
            "Brightness. Negative gives a negative light. Although I dont think that negative light works with PBR shaders."),
        {
            key = 'SparkLightColor',
            renderer = 'color',
            default = util.color.rgb(0.62, 0.78, 1.0),
            name = 'Spark Light Colour',
        },

        checkbox('HitLightEnabled', 'Light Flash On Hits', true,
            "Generic flash for every damagin hit."),
        number('HitLightRadius', 'Hit Light Radius', 90, 5, nil),
        number('HitLightDuration', 'Hit Light Duration', 0.2, 0.01, nil),
        number('HitLightPower', 'Hit Light Power', 0.75, nil, nil),
        {
            key = 'HitLightColor',
            renderer = 'color',
            default = util.color.rgb(0.533, 0.031, 0.031),
            name = 'Hit Light Colour',
        },

        checkbox('LightNoEffectHits', 'Add light to misses', false,
           "Should hits that connected but dealt no damage still flash a light (blocked hits, weapon-has-no-effect hits)"),

        checkbox('StaminaLightEnabled', 'Light Flash On Stamina Hits', true,
            "Stamina hit light flash. I.e for hand-to-hand attacks."),
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
            "Picks one of several baked bursts per hit instead of the same one. Honestly I have no idea why this option is here, what in the world would be a reason not to have this turned ON? AI brain slopped it here so I'll just leave it for lols."),
        checkbox('SparksOnMediumArmor', 'Sparks On Medium Armour', true,
            "Impact Effects gives medium armour a sound but no sparks; this adds sparks on medium armor as well. Sparks look cool, so more sparks is better."),
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
    description = "Enchanted weapons have their own on-hit flashes of light based on ecnhantment spell color or a school of magic. It makes enchanted weapons surprisingly more badass.",
    order = 8,
    permanentStorage = true,
    settings = {
        checkbox('EnchantLightEnabled', 'Colour Hit Lights By Enchantment', true,
            "So, should enchanted hits be colored with the enchantment color? If false they use the normal hit color (red by default). Destruction school specific elements (Fire, Lightning, Poison e.t.c) have their own colors."),
        number('EnchantLightPower', 'Enchanted Hit Light Power', 0.6, nil, nil),
        color('EnchantFireColor', 'Fire', 1.0, 0.28, 0.15, nil),
        color('EnchantFrostColor', 'Frost', 0.72, 0.85, 1.0),
        color('EnchantShockColor', 'Shock', 0.35, 0.55, 1.0),
        color('EnchantPoisonColor', 'Poison', 0.69, 1.0, 0.2),
        color('EnchantAlterationColor', 'Alteration', 0.97, 0.66, 1),
        color('EnchantConjurationColor', 'Conjuration', 1, 0.87, 0.59),
        color('EnchantDestructionColor', 'Destruction', 1, 0.46, 0.1,nil),
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
    order = 1,
    description = "A visual marker around the reticle that appears on a succesfull hit. Enhances an impact feel, especially for ranged.",
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
            "For glancing hits, if a mod reports them. 0 hides them. This is a compatibility settings, I dont think any mods curerntly use this, so just ignore it."),
        {
            key = 'MarkerColor',
            renderer = 'color',
            default = util.color.rgb(0.929, 0.8, 0.624),
            name = 'Hit Marker Colour'            
        },
        {
            key = 'KillMarkerColor',
            renderer = 'color',
            default = util.color.rgb(0.91, 0.145, 0.196),
            name = 'Kill Marker Colour',
        },
        checkbox('StaminaMarkers', 'Show Markers On Stamina Hits', true,
            "For hits that damage stamina"),
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
    order = 2,
    description = "Sounds that acoompany hit markers, again enhances impact feel, especially for ranged. I personally a bit on a fence about using it for spellcasing, but left it ON for spells by default.",
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

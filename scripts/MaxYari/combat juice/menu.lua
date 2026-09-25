-- Menu-side half of the settings: a sound picker you can listen to, and a hit
-- marker picker you can see.
--
-- Custom setting renderers may only be registered from a menu script, which is
-- also a context where openmw.ambient works - so the picker can play the sound
-- it is pointing at without involving the game world at all.

local ui = require("openmw.ui")
local util = require("openmw.util")
local async = require("openmw.async")
local ambient = require("openmw.ambient")
local storage = require("openmw.storage")
local I = require("openmw.interfaces")

local mp = "scripts/MaxYari/combat juice/"
local DEFS = require(mp .. "defs")
local hitmarkers = require(mp .. "hitmarkers")

local function label(text, size)
    return {
        type = ui.TYPE.Text,
        props = {
            text = text,
            textSize = size or 15,
            textColor = util.color.rgb(0.87, 0.816, 0.702),
        },
    }
end

local function button(text, onClick)
    return {
        type = ui.TYPE.Container,
        content = ui.content {
            {
                type = ui.TYPE.Text,
                props = {
                    text = text,
                    textSize = 15,
                    textColor = util.color.rgb(0.792, 0.651, 0.463),
                },
                events = { mouseClick = async:callback(onClick) },
            },
        },
    }
end

local function prettify(name)
    return (name:gsub("_", " "))
end

-- "< name >": steps through `items`, wrapping round at either end.
local function stepper(items, value, text, set)
    local index = 1
    for i, item in ipairs(items) do
        if item == value then index = i end
    end

    local function step(by)
        if #items == 0 then return end
        set(items[(index - 1 + by) % #items + 1])
    end

    return {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            button(" < ", function() step(-1) end),
            {
                type = ui.TYPE.Widget,
                props = { size = util.vector2(150, 20) },
                content = ui.content { label(text) },
            },
            button(" > ", function() step(1) end),
        },
    }
end

I.Settings.registerRenderer('cjSoundSelect', function(value, set, argument)
    local items = argument and argument.items or {}
    local paths = argument and argument.paths or {}

    return {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            stepper(items, value, prettify(tostring(value)), set),
            { props = { size = util.vector2(10, 0) }, type = ui.TYPE.Widget },
            button("[ play ]", function()
                local path = paths[value]
                if path then ambient.playSoundFile(path, { volume = 1 }) end
            end),
        },
    }
end)

-- Hit markers -----------------------------------------------------------------
--
-- The marker is drawn the way the HUD draws it, by the same layout function,
-- at rest: parts slid all the way out, in the colour, size and opacity set
-- below it. The backdrop is a dark, blurred still, so it is judged against
-- something like the game rather than against the menu.

local PREVIEW_SIZE = util.vector2(168, 170) -- the backdrop's own size, drawn 1:1
local backdrop = ui.texture { path = "textures/MaxYari/combat juice/marker_preview.png" }
local markerSettings = storage.playerSection(DEFS.settings.markers)

local function previewLayout(def, colorKey)
    return {
        template = I.MWUI.templates.box,
        content = ui.content {
            {
                type = ui.TYPE.Widget,
                props = { size = PREVIEW_SIZE },
                content = ui.content {
                    {
                        type = ui.TYPE.Image,
                        props = { relativeSize = util.vector2(1, 1), resource = backdrop },
                    },
                    hitmarkers.layout(def, {
                        scale = markerSettings:get('MarkerScale') or 1,
                        alpha = util.clamp((markerSettings:get('MarkerOpacity') or 1) * def.alpha, 0, 1),
                        color = markerSettings:get(colorKey),
                        t = 1,
                    }),
                },
            },
        },
    }
end

-- The previews on screen, by the colour they are drawn in, which tells the hit
-- marker's apart from the kill marker's. The settings page only redraws the
-- setting that changed, so the colour, size and opacity have to be followed
-- here. A preview the page has since thrown away ignores the update.
local previews = {}
local PREVIEW_INPUTS = { MarkerScale = true, MarkerOpacity = true }

markerSettings:subscribe(async:callback(function(_, key)
    for colorKey, preview in pairs(previews) do
        if key == nil or key == colorKey or PREVIEW_INPUTS[key] then
            preview.element.layout = previewLayout(preview.def, colorKey)
            preview.element:update()
        end
    end
end))

I.Settings.registerRenderer('cjMarkerSelect', function(value, set, argument)
    local items = argument and argument.items or {}
    local colorKey = argument and argument.colorKey
    local def = hitmarkers.get(value)

    local preview = def and ui.create(previewLayout(def, colorKey))
    if preview then previews[colorKey] = { element = preview, def = def } end

    return {
        type = ui.TYPE.Flex,
        props = { arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            stepper(items, value, def and def.name or tostring(value), set),
            { props = { size = util.vector2(0, 6) }, type = ui.TYPE.Widget },
            preview or {},
        },
    }
end)

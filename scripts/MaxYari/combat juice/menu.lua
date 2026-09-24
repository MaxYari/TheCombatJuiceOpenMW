-- Menu-side half of the settings: a sound picker you can listen to.
--
-- Custom setting renderers may only be registered from a menu script, which is
-- also a context where openmw.ambient works - so the picker can play the sound
-- it is pointing at without involving the game world at all.

local ui = require("openmw.ui")
local util = require("openmw.util")
local async = require("openmw.async")
local ambient = require("openmw.ambient")
local I = require("openmw.interfaces")

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

I.Settings.registerRenderer('cjSoundSelect', function(value, set, argument)
    local items = argument and argument.items or {}
    local paths = argument and argument.paths or {}

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
                content = ui.content { label(prettify(tostring(value))) },
            },
            button(" > ", function() step(1) end),
            { props = { size = util.vector2(10, 0) }, type = ui.TYPE.Widget },
            button("[ play ]", function()
                local path = paths[value]
                if path then ambient.playSoundFile(path, { volume = 1 }) end
            end),
        },
    }
end)

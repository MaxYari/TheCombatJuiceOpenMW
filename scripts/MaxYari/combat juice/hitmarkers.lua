-- Hit markers, from definition files rather than hardcoded art.
--
-- This mod inherited two different markers: Dynamic Reticle's, four white
-- triangles that spring apart from the centre and fade, and Stupid-Metal
-- Hitmarkers', a single coloured image that appears whole and fades out. Rather
-- than pick one, both behaviours live here and a YAML file in hitmarkers/ says
-- which a marker uses, what it is made of, and whether it takes the colour from
-- the settings. Any mod can add one.

local mp = "scripts/MaxYari/combat juice/"

local ui = require("openmw.ui")
local util = require("openmw.util")
local vfs = require("openmw.vfs")
local markup = require("openmw.markup")

local gutils = require(mp .. "gutils")
local Tweener = require(mp .. "tweener")

local DEFS_PREFIX = "hitmarkers/"

local module = {}

-- Definitions ---------------------------------------------------------------

local defs = {}   -- [id] = definition
local defIds = {} -- sorted, for the settings list

local function vector2(value, fallback)
    if type(value) == "table" and #value >= 2 then
        return util.vector2(value[1], value[2])
    end
    return fallback
end

local function loadDefs()
    for path in vfs.pathsWithPrefix(DEFS_PREFIX) do
        if path:lower():match("%.yaml$") then
            local ok, def = pcall(markup.loadYaml, path)
            if not ok or type(def) ~= "table" or type(def.parts) ~= "table" then
                gutils.print("skipping hit marker definition " .. path .. ": " .. tostring(def), 1)
            else
                local id = path:sub(#DEFS_PREFIX + 1):gsub("%.[yY][aA][mM]?[lL]$", "")
                def.id = id
                def.name = def.name or id
                def.style = def.style == "fade" and "fade" or "slide"
                def.size = vector2(def.size, util.vector2(16, 16))
                def.alpha = def.alpha or 1
                def.spread = def.spread or 0.0625
                def.slideTime = def.slideTime or 0.2
                def.fadeTime = def.fadeTime or 0.6
                def.decay = def.decay or 8
                def.recolour = def.recolour ~= false
                defs[id] = def
                table.insert(defIds, id)
            end
        end
    end
    table.sort(defIds)
end

loadDefs()

module.defs = defs
module.ids = defIds

function module.get(id)
    return defs[id] or defs[defIds[1]]
end

-- Elements ------------------------------------------------------------------
--
-- Every marker gets its parts built once, sitting at zero alpha until it is
-- asked for. There are a handful of them and they cost nothing while hidden.

local parentElement = ui.create({
    layer = 'HUD',
    type = ui.TYPE.Widget,
    props = {
        size = util.vector2(200, 200),
        relativePosition = util.vector2(0.5, 0.5),
        anchor = util.vector2(0.5, 0.5),
    },
    content = ui.content {},
})

local built = {} -- [id] = { parts = { { el, direction } }, tweeners = {} }

local function build(def)
    if built[def.id] then return built[def.id] end

    local content = {}
    local parts = {}
    for i, part in ipairs(def.parts) do
        local direction = vector2(part.direction, util.vector2(0, 0))
        -- A piece anchors to the corner it slides towards, so the set closes up
        -- into one shape at the centre.
        local anchor = util.vector2(direction.x > 0 and 0 or (direction.x < 0 and 1 or 0.5),
            direction.y > 0 and 0 or (direction.y < 0 and 1 or 0.5))
        local name = def.id .. "_" .. i
        table.insert(content, {
            name = name,
            type = ui.TYPE.Image,
            props = {
                alpha = 0,
                size = def.size,
                relativePosition = util.vector2(0.5, 0.5),
                anchor = anchor,
                resource = ui.texture { path = part.texture },
            },
        })
        table.insert(parts, { name = name, direction = direction })
    end

    local wrapper = {
        name = def.id,
        type = ui.TYPE.Widget,
        props = { relativeSize = util.vector2(1, 1) },
        content = ui.content(content),
    }
    parentElement.layout.content:add(wrapper)
    built[def.id] = { parts = parts, def = def }
    return built[def.id]
end

-- Playing -------------------------------------------------------------------

local active = {} -- markers currently animating

local function partElement(entry, part)
    return parentElement.layout.content[entry.def.id].content[part.name]
end

-- Dynamic Reticle's: the pieces spring out from the middle, then fade.
local function playSlide(entry, opts)
    for _, part in ipairs(entry.parts) do
        local el = partElement(entry, part)
        el.props.color = opts.color
        el.props.size = entry.def.size * opts.scale

        local tweener = Tweener:new()
        tweener:add(entry.def.slideTime, Tweener.easings.springOutStrong, function(t)
            local offset = part.direction * gutils.lerp(0, entry.def.spread * opts.scale, t)
            el.props.relativePosition = util.vector2(0.5, 0.5) + offset
            el.props.alpha = util.clamp(opts.alpha * t * 2, 0, 1)
        end):add(entry.def.fadeTime, Tweener.easings.easeOutCubic, function(t)
            el.props.alpha = util.clamp(opts.alpha * (1 - t), 0, 1)
        end)
        table.insert(active, { entry = entry, part = part, tweener = tweener })
    end
end

-- Stupid-Metal's: the whole marker appears, then decays away.
local function playFade(entry, opts)
    for _, part in ipairs(entry.parts) do
        local el = partElement(entry, part)
        el.props.color = opts.color
        el.props.size = entry.def.size * opts.scale
        el.props.relativePosition = util.vector2(0.5, 0.5)
        el.props.alpha = util.clamp(opts.alpha, 0, 1)
        table.insert(active, { entry = entry, part = part, decay = entry.def.decay })
    end
end

-- opts: { scale, alpha, color }
function module.play(id, opts)
    local def = module.get(id)
    if not def then return end
    local entry = build(def)
    opts = opts or {}
    opts.scale = opts.scale or 1
    opts.alpha = (opts.alpha or 1) * def.alpha
    if not def.recolour then opts.color = nil end

    if def.style == "fade" then playFade(entry, opts) else playSlide(entry, opts) end
    parentElement:update()
end

function module.update(dt)
    if #active == 0 then return end
    for i = #active, 1, -1 do
        local item = active[i]
        local el = partElement(item.entry, item.part)
        if item.tweener then
            item.tweener:tick(dt)
            if #item.tweener.animations == 0 then
                el.props.alpha = 0
                table.remove(active, i)
            end
        else
            el.props.alpha = gutils.lerp(el.props.alpha, 0, math.min(dt * item.decay, 1))
            if el.props.alpha < 0.01 then
                el.props.alpha = 0
                table.remove(active, i)
            end
        end
    end
    parentElement:update()
end

function module.setVisible(visible)
    parentElement.layout.props.alpha = visible and 1 or 0
    parentElement:update()
end

return module

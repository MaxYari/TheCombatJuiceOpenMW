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

-- A piece anchors to the corner it slides towards, so the set closes up into
-- one shape at the centre.
local function normaliseParts(parts)
    local out = {}
    for i, part in ipairs(parts) do
        local direction = vector2(part.direction, util.vector2(0, 0))
        out[i] = {
            texture = part.texture,
            direction = direction,
            anchor = util.vector2(direction.x > 0 and 0 or (direction.x < 0 and 1 or 0.5),
                direction.y > 0 and 0 or (direction.y < 0 and 1 or 0.5)),
        }
    end
    return out
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
                -- a fading marker never moves, so its parts stay closed up at the centre
                if def.style == "fade" then def.spread = 0 end
                def.parts = normaliseParts(def.parts)
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

-- Layout --------------------------------------------------------------------
--
-- A marker is drawn on a square canvas centred on the crosshair; how far its
-- parts spread is a share of that square. The HUD builds every marker from
-- this once and animates the props, the settings preview draws one at rest.

local CANVAS = util.vector2(200, 200)
local CENTRE = util.vector2(0.5, 0.5)

-- Where a part sits once it has slid `t` of the way out.
local function partPosition(def, part, scale, t)
    return CENTRE + part.direction * (def.spread * scale * t)
end

-- opts: { scale, alpha, color, t } - t is how far the parts have slid, 1 is
-- where they come to rest.
function module.layout(def, opts)
    local content = {}
    for i, part in ipairs(def.parts) do
        content[i] = {
            name = tostring(i),
            type = ui.TYPE.Image,
            props = {
                alpha = opts.alpha,
                color = def.recolour and opts.color or nil,
                size = def.size * opts.scale,
                relativePosition = partPosition(def, part, opts.scale, opts.t),
                anchor = part.anchor,
                resource = ui.texture { path = part.texture },
            },
        }
    end
    return {
        name = def.id,
        type = ui.TYPE.Widget,
        props = { size = CANVAS, relativePosition = CENTRE, anchor = CENTRE },
        content = ui.content(content),
    }
end

-- The HUD ---------------------------------------------------------------------
--
-- Every marker gets its parts built once, sitting at zero alpha until it is
-- asked for. There are a handful of them and they cost nothing while hidden.
-- The element itself waits for the first marker, so the menu script can use
-- this module without putting anything on the HUD.

local hud

local function hudElement()
    if not hud then
        hud = ui.create({
            layer = 'HUD',
            type = ui.TYPE.Widget,
            props = { size = CANVAS, relativePosition = CENTRE, anchor = CENTRE },
            content = ui.content {},
        })
    end
    return hud
end

local built = {} -- [id] = true

local function build(def)
    if built[def.id] then return end
    hudElement().layout.content:add(module.layout(def, { scale = 1, alpha = 0, t = 0 }))
    built[def.id] = true
end

-- Playing -------------------------------------------------------------------

local active = {} -- markers currently animating

local function partElement(def, i)
    return hud.layout.content[def.id].content[i]
end

-- Dynamic Reticle's: the pieces spring out from the middle, then fade.
local function playSlide(def, opts)
    for i, part in ipairs(def.parts) do
        local el = partElement(def, i)
        el.props.color = opts.color
        el.props.size = def.size * opts.scale

        local tweener = Tweener:new()
        tweener:add(def.slideTime, Tweener.easings.springOutStrong, function(t)
            el.props.relativePosition = partPosition(def, part, opts.scale, t)
            el.props.alpha = util.clamp(opts.alpha * t * 2, 0, 1)
        end):add(def.fadeTime, Tweener.easings.easeOutCubic, function(t)
            el.props.alpha = util.clamp(opts.alpha * (1 - t), 0, 1)
        end)
        table.insert(active, { el = el, tweener = tweener })
    end
end

-- Stupid-Metal's: the whole marker appears, then decays away.
local function playFade(def, opts)
    for i, part in ipairs(def.parts) do
        local el = partElement(def, i)
        el.props.color = opts.color
        el.props.size = def.size * opts.scale
        el.props.relativePosition = partPosition(def, part, opts.scale, 1)
        el.props.alpha = util.clamp(opts.alpha, 0, 1)
        table.insert(active, { el = el, decay = def.decay })
    end
end

-- opts: { scale, alpha, color }
function module.play(id, opts)
    local def = module.get(id)
    if not def then return end
    build(def)
    opts = opts or {}
    opts.scale = opts.scale or 1
    opts.alpha = (opts.alpha or 1) * def.alpha
    if not def.recolour then opts.color = nil end

    if def.style == "fade" then playFade(def, opts) else playSlide(def, opts) end
    hud:update()
end

function module.update(dt)
    if #active == 0 then return end
    for i = #active, 1, -1 do
        local item = active[i]
        local el = item.el
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
    hud:update()
end

function module.setVisible(visible)
    hudElement().layout.props.alpha = visible and 1 or 0
    hud:update()
end

return module

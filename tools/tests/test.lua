-- Runs the mod scripts against a stubbed OpenMW API, so the wiring can be
-- checked without starting the game:
--
--     lua tools/tests/test.lua "scripts/MaxYari/combat juice"
--
package.path = package.path .. ";" .. arg[1] .. "/?.lua;" .. arg[0]:gsub("[^/]*$", "") .. "?.lua"
local MOD = arg[1]

local stub = require("stub")
-- The VFS root is the mod folder: the scripts live under it.
stub.modRoot = arg[1]:gsub("scripts/MaxYari/combat juice$", ""):gsub("/$", "")
if stub.modRoot == "" then stub.modRoot = "." end
local failures, checks = 0, 0
local function check(cond, what)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("  FAIL: " .. what)
    else
        print("  ok:   " .. what)
    end
end

local loaded = {}
local function makeLoader()
    local real = _G.require
    return function(name)
        if stub.packages[name] then return stub.packages[name] end
        if name:match("combat juice") then
            if loaded[name] then return loaded[name] end
            local file = MOD .. "/" .. name:gsub("scripts/MaxYari/combat juice/", "") .. ".lua"
            loaded[name] = assert(loadfile(file))()
            return loaded[name]
        end
        return real(name)
    end
end

local function loadScript(file)
    loaded = {}
    _G.require = makeLoader()
    return assert(loadfile(MOD .. "/" .. file))()
end

local function setting(group, key, value)
    stub.setSetting("SettingsCombatJuice" .. group, key, value)
end

local function sentSlowdown()
    for _, e in ipairs(stub.sentGlobalEvents) do
        if e.name == "CJ_Slowdown" then return e.data end
    end
end

local function sentLights()
    local out = {}
    for _, e in ipairs(stub.sentGlobalEvents) do
        if e.name == "CJ_SpawnLight" then table.insert(out, e.data) end
    end
    return out
end

print("== loading global.lua ==")
stub.install(stub.player)
_G.require = makeLoader()
local global = loadScript("global.lua")
check(type(global.engineHandlers.onUpdate) == "function", "global exposes onUpdate")
check(global.eventHandlers.CJ_Slowdown ~= nil, "global takes slow motion requests")

print("\n== loading player.lua ==")
stub.enableImpactEffects()
local player = loadScript("player.lua")
check(#stub.settingsPages == 1, "one settings page registered")
check(#stub.settingsGroups == 9, "eight settings groups from the player - one only the logo - and one from global.lua")

local slow = stub.settingsStore["SettingsCombatJuiceSlowdown"]
check(slow.SmallSlowdownTrigger == "Every kill", "the short slow motion defaults to every kill")
check(slow.SmallSlowdownChance == 0.25, "on a quarter of them by default")
setting("Slowdown", "SmallSlowdownChance", 1) -- every kill, so the runs below are certain
check(slow.BigSlowdownTrigger == "Long encounter end", "the long one defaults to long fights only")
check(slow.BigSlowdownChance == 1, "at 100% by default")
check(slow.LongEncounterSeconds == 20, "a long fight is 20 seconds by default")
local cam = stub.settingsStore["SettingsCombatJuiceCamera"]
check(cam.ShakeStrength == 1.0 and cam.ShakeDuration == 0.3 and cam.ShakeFrequency == 38,
      "camera shake defaults match the tuned in-game settings")
check(cam.ShakeTakenHitFactor == 0, "and taking a hit does not shake by default")
check(stub.settingsStore["SettingsCombatJuiceFlash"].FlashOn == "Long slow motion",
      "the kill flash rides the long slow motion by default")

local function frame(dt)
    stub.realTime = stub.realTime + (dt or 0.016)
    stub.cameraExtras = { pitch = 0, yaw = 0, roll = 0 }
    player.engineHandlers.onFrame()
end

print("\n== a plain kill ==")
player.engineHandlers.onUpdate(0.016)
local a = stub.newObject("npc", { id = "bandit_a" })
local b = stub.newObject("npc", { id = "bandit_b" })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = a, targets = { stub.player } })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = b, targets = { stub.player } })

stub.sentGlobalEvents = {}
a.dead = true
player.eventHandlers.CJ_ActorKilled({ victim = a })
local s = sentSlowdown()
check(s ~= nil, "a kill mid fight still slows time")
check(s and math.abs((s.inTime + s.hold + s.outTime) - 1.0) < 1e-6,
      "with the short slow motion's duration")

print("\n== the last enemy of a short fight ==")
stub.sentGlobalEvents = {}
stub.realTime = stub.realTime + 3
b.dead = true
player.eventHandlers.CJ_ActorKilled({ victim = b })
s = sentSlowdown()
check(s ~= nil and math.abs((s.inTime + s.hold + s.outTime) - 1.0) < 1e-6,
      "gets the short one too: the long one is set to long fights only")

print("\n== the last enemy of a long fight ==")
local c = stub.newObject("npc", { id = "bandit_c" })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = c, targets = { stub.player } })
stub.realTime = stub.realTime + 25 -- a long fight
stub.sentGlobalEvents = {}
c.dead = true
player.eventHandlers.CJ_ActorKilled({ victim = c })
s = sentSlowdown()
check(s ~= nil, "slows time")
check(s and math.abs((s.inTime + s.hold + s.outTime) - 2.0) < 1e-6,
      "and the long slow motion wins, since both qualified")

print("\n== triggers and chance ==")
setting("Slowdown", "SmallSlowdownTrigger", "Encounter end")
local d = stub.newObject("npc", { id = "bandit_d" })
local e = stub.newObject("npc", { id = "bandit_e" })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = d, targets = { stub.player } })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = e, targets = { stub.player } })
stub.sentGlobalEvents = {}
d.dead = true
player.eventHandlers.CJ_ActorKilled({ victim = d })
check(sentSlowdown() == nil, "'encounter end' skips a kill in the middle of a fight")
stub.sentGlobalEvents = {}
e.dead = true
player.eventHandlers.CJ_ActorKilled({ victim = e })
check(sentSlowdown() ~= nil, "and takes the one that ends it")

setting("Slowdown", "SmallSlowdownTrigger", "Every kill")
setting("Slowdown", "SmallSlowdownChance", 0)
stub.sentGlobalEvents = {}
player.eventHandlers.CJ_ActorKilled({ victim = stub.newObject("npc") })
check(sentSlowdown() == nil, "a chance of 0 never plays")
setting("Slowdown", "SmallSlowdownChance", 1)

setting("Slowdown", "SlowdownEnabled", false)
stub.sentGlobalEvents = {}
player.eventHandlers.CJ_ActorKilled({ victim = stub.newObject("npc") })
check(sentSlowdown() == nil, "and the group can be switched off entirely")
setting("Slowdown", "SlowdownEnabled", true)

print("\n== the kill flash ==")
stub.shaderUniform = nil
player.eventHandlers.CJ_ActorKilled({ victim = stub.newObject("npc") })
stub.realTime = stub.realTime + 0.1
player.engineHandlers.onFrame()
check(stub.shaderUniform ~= nil and stub.shaderUniform > 0, "fires on a plain kill by default")
stub.realTime = stub.realTime + 2
player.engineHandlers.onFrame()
check(stub.shaderUniform == 0, "and fades out")

-- Enabling a shader makes the engine rebuild the whole post processing chain,
-- so it must not happen per kill: that is a hitch exactly on the kill.
stub.shaderEnables, stub.shaderDisables = 0, 0
for _ = 1, 5 do
    player.eventHandlers.CJ_ActorKilled({ victim = stub.newObject("npc") })
    for _ = 1, 40 do frame(0.03) end
end
check(stub.shaderEnables == 0 and stub.shaderDisables == 0,
      "five kills do not touch the post processing chain")

setting("Flash", "FlashOn", "Never")
frame()
check(stub.shaderDisables == 1, "turning the flash off takes the shader out of the chain")
setting("Flash", "FlashOn", "Short slow motion")
frame()
check(stub.shaderEnables == 1, "and turning it back on puts it in, once")

setting("Flash", "FlashTrigger", "Long encounter end")
stub.shaderUniform = nil
player.eventHandlers.CJ_ActorKilled({ victim = stub.newObject("npc") })
player.engineHandlers.onFrame()
check(stub.shaderUniform == nil, "set to long fights only, a plain kill does not fire it")
setting("Flash", "FlashOn", "Short slow motion")

print("\n== camera shake and impact lights ==")
local victim = stub.newObject("npc", { id = "unarmoured", position = stub.vec3(0, 100, 0) })
local enginePos = stub.vec3(0, 0, 5)      -- the engine's guess, down by the feet
local aimPos = stub.vec3(1, 90, 80)       -- where our camera ray lands on them
local sidePos = stub.vec3(2, 88, 78)      -- where a ray straight at them lands

-- Looking right at them: the camera ray wins, because that is where the
-- player's attention is.
stub.rayResult = { hit = true, hitObject = victim, hitPos = aimPos }
stub.sentGlobalEvents = {}
player.eventHandlers.CJ_AttackLanded({ victim = victim, successful = true, hitPos = enginePos })
player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.25 })
frame()
local moved = math.abs(stub.cameraExtras.pitch) + math.abs(stub.cameraExtras.yaw)
    + math.abs(stub.cameraExtras.roll)
check(moved > 0 and moved < math.rad(15), "a landed hit shakes the camera")
local lights = sentLights()
check(#lights == 1 and lights[1].pos == aimPos, "and lights it where the camera was pointed")
check(lights[1] and lights[1].r > lights[1].b, "with the warm light")
-- Power scales the colour, because that is what a Morrowind light's brightness
-- is; the radius is only its reach.
check(lights[1] and lights[1].power < 1 and lights[1].radius == 90,
      "dimmed by power rather than by shrinking its reach")

-- Swinging at someone off to the side: the camera ray misses them, so the point
-- comes from a ray straight at them instead. This is the case Impact Effects
-- cannot answer at all.
local calls = 0
stub.packages["openmw.nearby"].castRay = function(from, to, opts)
    calls = calls + 1
    stub.lastRay = { from = from, to = to }
    if calls == 1 then return { hit = true, hitObject = stub.newObject("static") } end
    return { hit = true, hitObject = victim, hitPos = sidePos }
end
stub.sentGlobalEvents = {}
player.eventHandlers.CJ_AttackLanded({ victim = victim, successful = true, hitPos = enginePos })
lights = sentLights()
check(#lights == 1 and lights[1].pos == sidePos,
      "a hit away from the crosshair is lit from a ray straight at the victim")
check(stub.lastRay and math.abs(stub.lastRay.from.z - stub.lastRay.to.z) < 1e-9,
      "and that ray is level, at chest height rather than at their feet")
check(stub.lastRay and stub.lastRay.from.z > victim.position.z + 40,
      "which is well above the ground")

local arrowPos = stub.vec3(3, 97, 71)
stub.sentGlobalEvents = {}
player.eventHandlers.CJ_AttackLanded({ victim = victim, successful = true, hitPos = arrowPos, ranged = true })
lights = sentLights()
check(#lights == 1 and lights[1].pos == arrowPos, "an arrow's hit is lit where the arrow struck")

stub.rayResult = { hit = false }
local castRayBefore = stub.packages["openmw.nearby"].castRay
stub.packages["openmw.nearby"].castRay = function() return { hit = false } end
local far = true
for _ = 1, 20 do
    stub.realTime = stub.realTime + 1
    stub.sentGlobalEvents = {}
    player.eventHandlers.CJ_AttackLanded({ victim = victim, successful = true, hitPos = enginePos })
    local p = sentLights()[1].pos
    local dx, dy = p.x - victim.position.x, p.y - victim.position.y
    -- the player stands at the origin, the victim 100 units along y
    far = far and dy < 0 and math.sqrt(dx * dx + dy * dy) < 25 and p.z > victim.position.z + 40
end
check(far, "with no ray landing on them, it goes on the side of their torso facing the attacker")
stub.packages["openmw.nearby"].castRay = castRayBefore

-- Being hit lights nothing: it would be lighting the player's own face.
calls = 1
stub.sentGlobalEvents = {}
stub.hitHandlers[1]({ attacker = victim, successful = true, hitPos = enginePos })
check(#sentLights() == 0, "being hit ourselves lights nothing")

stub.packages["openmw.nearby"].castRay = function(from, to, opts)
    stub.lastRay = { from = from, to = to }
    return stub.rayResult
end
stub.rayResult = { hit = true, hitObject = victim, hitPos = aimPos }

stub.sentGlobalEvents = {}
player.eventHandlers.CJ_AttackLanded({ victim = victim, successful = false })
check(#sentLights() == 0, "a miss lights nothing")

-- Sparks light their own impact, so the warm one keeps out of the way.
local hitPos = stub.vec3(10, 20, 30)
stub.equipped = { kind = "weapon", weaponType = 1 } -- a sword: only a swung weapon sparks
stub.sentGlobalEvents = {}
stub.impactActorHandlers[1](stub.newObject("npc"), { material = "ParryArmorHeavy", hitPos = hitPos })
lights = sentLights()
check(#lights == 1 and lights[1].b > lights[1].r, "a spark material lights it cold")
player.eventHandlers.CJ_AttackLanded({ victim = victim, successful = true, hitPos = enginePos })
check(#sentLights() == 1, "and the warm light does not pile on top of it")

-- A bare body part reaches the hook only because of the one-line patch in
-- Impact Effects (docs/impact-effects-unarmored.md), and must stay silent.
local bare = { material = "Unarmored", hitPos = hitPos }
stub.impactActorHandlers[1](stub.newObject("npc"), bare)
check(bare.noSound, "an unarmoured hit is kept silent, that material has no sound of its own")

-- Striking the world still goes through the object handler.
check(#stub.impactObjectHandlers == 1, "the object handler is registered")
stub.realTime = stub.realTime + 1
stub.sentGlobalEvents = {}
stub.impactObjectHandlers[1](stub.newObject("static"), { material = "Metal", hitPos = hitPos })
lights = sentLights()
check(#lights == 1 and lights[1].b > lights[1].r, "hitting metal scenery lights it cold")

stub.sentGlobalEvents = {}
stub.impactObjectHandlers[1](stub.newObject("static"), { material = "Wood", hitPos = hitPos })
check(#sentLights() == 0, "but hitting a crate lights nothing")

print("\n== shake scaled by how hard the blow landed ==")
-- The camera's wobble is random frame to frame, but how long it wobbles for is
-- not, and the same multiplier drives both. So measure the length.
local function shakeFrames(fraction)
    player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = fraction })
    local frames = 0
    for _ = 1, 500 do
        stub.realTime = stub.realTime + 0.005
        stub.cameraExtras = { pitch = 0, yaw = 0, roll = 0 }
        player.engineHandlers.onFrame()
        local moved = math.abs(stub.cameraExtras.pitch) + math.abs(stub.cameraExtras.yaw)
            + math.abs(stub.cameraExtras.roll)
        if moved == 0 then break end
        frames = frames + 1
    end
    return frames
end

local scratch = shakeFrames(0.05)   -- a tenth of their health or less: half
local solid = shakeFrames(0.25)     -- a quarter: exactly what the settings say
local heavy = shakeFrames(0.50)     -- two fifths or more: half again
check(scratch > 0 and heavy > solid and solid > scratch,
      "a harder blow shakes for longer, and a scratch for less")
check(math.abs(heavy / scratch - 3) < 0.25,
      string.format("across the stated half to half again, a threefold range (%.2fx)", heavy / scratch))
check(math.abs(solid / scratch - 2) < 0.25,
      "with a quarter of their health landing on the settings' own figure")

setting("Camera", "ShakeScalesWithDamage", false)
check(shakeFrames(0.05) == shakeFrames(0.50), "with the setting off, every blow shakes the same")
setting("Camera", "ShakeScalesWithDamage", true)

print("\n== hit markers ==")
local hm = loadScript("hitmarkers.lua")
check(#hm.ids >= 4, "every definition file in hitmarkers/ is found (" .. #hm.ids .. ")")
local byStyle = { slide = 0, fade = 0 }
for _, id in ipairs(hm.ids) do
    local def = hm.get(id)
    byStyle[def.style] = (byStyle[def.style] or 0) + 1
end
check(byStyle.slide >= 1 and byStyle.fade >= 1,
      "both animation styles are represented, Dynamic Reticle's and Stupid-Metal's")
check(hm.get("sm_skull").recolour == false, "the skull is marked as keeping its own colours")
check(hm.get("faded_triangles").recolour == true, "and the white art takes the colour setting")
check(#hm.get("faded_triangles").parts == 4 and #hm.get("sm_skull").parts == 1,
      "a marker can be four pieces or one")

print("\n== hit marker previews in the settings ==")
local menu = loadScript("menu.lua")
local renderMarker = stub.renderers.cjMarkerSelect
check(renderMarker ~= nil, "the menu script registers the marker picker")
local logo = stub.renderers.cjLogo and stub.renderers.cjLogo()
check(logo and logo.content[1].props.resource.path == "textures/MaxYari/combat juice/logo.dds",
      "and the logo at the top of the page")
local killColor = stub.settingsStore.SettingsCombatJuiceMarkers.KillMarkerColor
local picker = renderMarker("faded_triangles", function() end,
    { items = hm.ids, colorKey = "KillMarkerColor" })
local preview = picker.content[3]
-- preview > box > backdrop and marker; preview > size row > [-] label [+]
local function previewMarker(p)
    return (p or preview).layout.content[1].content[1].content[2]
end
local function sizeRow(p)
    return (p or preview).layout.content[3]
end
check(preview.layout ~= nil, "it shows a preview under the name")
local drawn = previewMarker()
check(drawn.name == "faded_triangles" and drawn.content[4] ~= nil and drawn.content[5] == nil,
      "drawn from the marker's own parts")
local part = drawn.content[2] -- top right
check(part.props.alpha == 1 and part.props.color == killColor,
      "at rest, fully visible, in the colour it was pointed at")
check(part.props.relativePosition.x > 0.5 and part.props.relativePosition.y < 0.5,
      "with the pieces slid out, the way the HUD leaves them")
check(math.abs(part.props.size.x - 10.5) < 1e-6, "at the size its definition gives it")
check(sizeRow().content[2].content[1].props.text == "Size 100%", "which reads as 100% under it")
local skull = renderMarker("sm_skull", function() end, { items = hm.ids, colorKey = "MarkerColor" })
local skullPreview = skull.content[3]
check(previewMarker(skullPreview).content[1].props.color == nil,
      "a marker that keeps its own colours is not tinted in the preview either")

local red = { r = 1, g = 0, b = 0 }
setting("Markers", "KillMarkerColor", red)
check(previewMarker().content[2].props.color == red and preview.updates > 0,
      "changing the colour redraws the preview, which the settings page would not")

print("\n== each marker keeps its own size ==")
local function click(button) button.content[1].events.mouseClick() end
click(sizeRow().content[3]) -- +
click(sizeRow().content[3]) -- +
local sizes = stub.settingsStore.SettingsCombatJuiceMarkers.MarkerSizes
check(sizes.faded_triangles == 1.1, "+ grows the marker on show, in steps of 5%")
check(math.abs(previewMarker().content[2].props.size.x - 10.5 * 1.1) < 1e-6
      and sizeRow().content[2].content[1].props.text == "Size 110%",
      "and its preview is redrawn at the new size")
check(sizes.sm_skull == nil and math.abs(previewMarker(skullPreview).content[1].props.size.x - 63) < 1e-6,
      "without leaking into any other marker")
for _ = 1, 40 do click(sizeRow(skullPreview).content[1]) end -- - past the bottom
check(stub.settingsStore.SettingsCombatJuiceMarkers.MarkerSizes.sm_skull == 0.05,
      "- stops at 5% rather than making it vanish")
stub.renderers.cjMarkerSizes(sizes, function(v) setting("Markers", "MarkerSizes", v) end)
    .content[1].events.mouseClick()
check(next(stub.settingsStore.SettingsCombatJuiceMarkers.MarkerSizes) == nil,
      "and one button puts every marker back to its own size")

setting("Markers", "MarkerSizes", { faded_triangles = 2 })
player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.2, lethal = false })
check(math.abs(stub.hud.layout.content.faded_triangles.content[1].props.size.x - 21) < 1e-6,
      "in game, the hit marker is drawn at its own size")
player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.2, lethal = true })
local crossPart = stub.hud.layout.content.cross.content[1]
check(math.abs(crossPart.props.size.x - 16.8) < 1e-6,
      "and the kill marker at its own, a cross 1.6 times its first size by default")
for _ = 1, 15 do player.engineHandlers.onUpdate(0.016) end -- 0.24s
check(crossPart.props.alpha == 1, "which holds at full strength for its hold time")
for _ = 1, 15 do player.engineHandlers.onUpdate(0.016) end -- 0.48s
check(crossPart.props.alpha < 1 and crossPart.props.alpha > 0, "and then fades")
setting("Markers", "MarkerSizes", {})
for _ = 1, 120 do player.engineHandlers.onUpdate(0.016) end

print("\n== blows that take only stamina ==")
local markerStore = stub.settingsStore.SettingsCombatJuiceMarkers
local effectStore = stub.settingsStore.SettingsCombatJuiceEffects
local function blow(staminaOnly)
    stub.realTime = stub.realTime + 1 -- clear of any spark's light
    stub.sentGlobalEvents = {}
    player.eventHandlers.CJ_AttackLanded({ victim = victim, successful = true,
        staminaOnly = staminaOnly, hitPos = stub.vec3(0, 100, 50) })
    return sentLights()[1]
end
local light = blow(true)
player.engineHandlers.onUpdate(0.05) -- the triangles spring out from nothing
local triangle = stub.hud.layout.content.faded_triangles.content[1]
check(triangle.props.color == markerStore.StaminaMarkerColor and triangle.props.alpha > 0,
      "shows the hit marker, in the stamina colour")
check(light and light.r == effectStore.StaminaLightColor.r and light.g == effectStore.StaminaLightColor.g
      and light.power < effectStore.HitLightPower and light.radius < effectStore.HitLightRadius,
      "and a warm light, dimmer and smaller than the hit light")
light = blow(false)
check(light and light.r == effectStore.HitLightColor.r and light.g == effectStore.HitLightColor.g,
      "a blow that took health gets the ordinary light")
player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.2, lethal = false })
check(triangle.props.color == markerStore.MarkerColor, "and the ordinary marker, from its damage")
setting("Markers", "StaminaMarkers", false)
for _ = 1, 120 do player.engineHandlers.onUpdate(0.016) end
blow(true)
player.engineHandlers.onUpdate(0.05)
check(triangle.props.alpha == 0, "stamina markers can be switched off on their own")
setting("Markers", "StaminaMarkers", true)
for _ = 1, 120 do player.engineHandlers.onUpdate(0.016) end

print("\n== enchanted hit lights ==")
local enchantStore = stub.settingsStore.SettingsCombatJuiceEnchantLights
local function effect(id, school, color) return { id = id, effect = { school = school, color = color } } end
local violet = { r = 0.62, g = 0.22, b = 0.85 }
stub.enchantments.fire_en = { type = 1, effects = { effect("firedamage", "destruction", { r = 1, g = 0.5, b = 0.2 }) } }
stub.enchantments.frost_en = { type = 1, effects = { effect("frostdamage", "destruction", { r = 0.5, g = 0.6, b = 0.9 }) } }
stub.enchantments.fortify_en = { type = 1, effects = { effect("fortifyattribute", "restoration", { r = 0.5, g = 0.5, b = 0.75 }) } }
stub.enchantments.venom_en = { type = 1, effects = { effect("h2h_venom", "destruction", violet),
                                                     effect("firedamage", "destruction", {}) } }
stub.enchantments.aura_en = { type = 3, effects = { effect("firedamage", "destruction", {}) } }
stub.weaponRecords.fire_sword = { type = 1, enchant = "fire_en" }
stub.weaponRecords.rose = { type = 0, enchant = "venom_en" }
stub.weaponRecords.aura_blade = { type = 1, enchant = "aura_en" }
stub.weaponRecords.bow = { type = 9, enchant = "" }
stub.weaponRecords.frost_arrow = { type = 12, enchant = "frost_en" }
stub.weaponRecords.star = { type = 11, enchant = "fortify_en" }
local function same(light, color) return light and light.r == color.r and light.g == color.g and light.b == color.b end
local function strike(weapon, ammo)
    stub.realTime = stub.realTime + 1
    stub.sentGlobalEvents = {}
    player.eventHandlers.CJ_AttackLanded({ victim = victim, successful = true, staminaOnly = false,
        hitPos = stub.vec3(0, 100, 50), weapon = weapon, ammo = ammo })
    return sentLights()[1]
end
local heldBefore = stub.equipped
local sword = { kind = "weapon", recordId = "fire_sword", charge = 100 }
stub.equipped = sword
player.engineHandlers.onUpdate(0.016) -- the charge is read
sword.charge = 90                     -- and the blow spends some
local light = strike("fire_sword")
check(same(light, enchantStore.EnchantFireColor) and light.power == enchantStore.EnchantLightPower,
      "a fire enchantment that fired lights the hit in the fire colour")
check(same(strike("fire_sword"), effectStore.HitLightColor),
      "a blow it had no charge to fire on is lit as a plain hit")
sword.charge = 80
check(same(strike("fire_sword"), enchantStore.EnchantFireColor),
      "the charge drop is seen as the hit is reported, even before an update reads it")
check(same(strike("bow", "frost_arrow"), enchantStore.EnchantFrostColor), "enchanted arrows always fire")
check(same(strike("star"), enchantStore.EnchantRestorationColor),
      "and so do thrown weapons; an effect that is no element takes its school's colour")
local rose = { kind = "weapon", recordId = "rose", charge = 160 }
stub.equipped = rose
player.engineHandlers.onUpdate(0.016)
rose.charge = 144
check(same(strike("rose"), violet), "a mod's own magic effect lights in the colour on its own record")
local aura = { kind = "weapon", recordId = "aura_blade", charge = 100 }
stub.equipped = aura
player.engineHandlers.onUpdate(0.016)
aura.charge = 90
check(same(strike("aura_blade"), effectStore.HitLightColor), "an enchantment that is not cast on strike does nothing")
stub.equipped = sword
player.engineHandlers.onUpdate(0.016)
setting("EnchantLights", "EnchantLightEnabled", false)
sword.charge = 70
check(same(strike("fire_sword"), effectStore.HitLightColor), "and all of it can be switched off")
setting("EnchantLights", "EnchantLightEnabled", true)
stub.equipped = heldBefore

print("\n== the reticle under a kill marker ==")
local interfaces = stub.packages["openmw.interfaces"]
local reticleCalls = {}
local function killWith(marker)
    setting("Markers", "KillMarker", marker)
    reticleCalls = {}
    player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.5, lethal = true })
    for _ = 1, 120 do player.engineHandlers.onUpdate(0.016) end
end
interfaces.DynamicReticle = { version = 1.1, setAlphaMultiplier = function(source, alpha)
    table.insert(reticleCalls, { source = source, alpha = alpha })
end }
killWith("cross")
check(reticleCalls[1] and reticleCalls[1].alpha == 0 and reticleCalls[1].source == "CombatJuice",
      "a centred kill marker hides Dynamic Reticle's reticle as it appears")
local rising = true
for i = 2, #reticleCalls do rising = rising and reticleCalls[i].alpha >= reticleCalls[i - 1].alpha end
check(rising and #reticleCalls > 2 and reticleCalls[#reticleCalls].alpha == 1,
      "fades it back in as the marker fades, and hands it back at the end")
killWith("faded_triangles")
check(#reticleCalls == 0, "a marker that slides apart around the crosshair leaves it alone")
player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.2, lethal = false })
setting("Markers", "HitMarker", "sm_marker")
killWith("faded_triangles")
player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.2, lethal = false })
for _ = 1, 120 do player.engineHandlers.onUpdate(0.016) end
check(#reticleCalls == 0, "and so does a centred marker on an ordinary hit")
setting("Markers", "HitMarker", "faded_triangles")
interfaces.DynamicReticle = { version = 1.0 }
check(pcall(killWith, "cross"), "an older Dynamic Reticle, without the call, is left alone without an error")
interfaces.DynamicReticle = nil
check(pcall(killWith, "cross"), "and so is having no Dynamic Reticle at all")
setting("Markers", "KillMarker", "cross")

stub.stance = 1                        -- weapon drawn
stub.equipped = { kind = "weapon", weaponType = 9 }  -- a bow, which the defaults sound on
stub.sentSounds = {}
player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.2, lethal = false })
check(#stub.sentSounds == 1, "a hit plays the hit marker sound")
stub.sentSounds = {}
player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.9, lethal = true })
check(#stub.sentSounds == 1 and stub.sentSounds[1].path:find("bass_stab"),
      "and a kill plays the kill sound instead")

stub.sentSounds = {}
player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.1, weak = true })
check(#stub.sentSounds == 0, "a glancing hit is silent")

stub.equipped = { kind = "weapon", weaponType = 1 }  -- a sword: off by default
stub.sentSounds = {}
player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.2, lethal = false })
check(#stub.sentSounds == 0, "and melee is silent until switched on")
setting("MarkerSounds", "MeleeSound", true)
stub.sentSounds = {}
player.eventHandlers.CJ_DamageDealt({ victim = victim, fraction = 0.2, lethal = false })
check(#stub.sentSounds == 1, "once switched on, melee plays it")

print("\n== fists do not spark ==")
local swordBefore = stub.equipped
stub.equipped = nil
local function punch(handlers, target, material)
    stub.realTime = stub.realTime + 1
    stub.sentGlobalEvents = {}
    local var = { material = material, hitPos = hitPos }
    handlers[1](target, var)
    local vfx = 0
    for _, ev in ipairs(stub.sentGlobalEvents) do if ev.name == "SpawnVfx" then vfx = vfx + 1 end end
    return vfx, #sentLights(), var
end
local vfx, lit = punch(stub.impactObjectHandlers, stub.newObject("static"), "Stone")
check(vfx == 0 and lit == 0, "a punch on stone throws no sparks and no spark light")
vfx, lit = punch(stub.impactObjectHandlers, stub.newObject("static"), "Metal")
check(vfx == 0 and lit == 0, "nor on bare metal")
vfx, lit = punch(stub.impactActorHandlers, stub.newObject("npc"), "ParryArmorHeavy")
check(vfx == 0 and lit == 0, "nor on heavy armour")
local _, _, var = punch(stub.impactActorHandlers, stub.newObject("npc"), "Unarmored")
check(var.noSound == true, "a bare body part is still kept quiet")
stub.equipped = { kind = "weapon", weaponType = 9 }
vfx = punch(stub.impactObjectHandlers, stub.newObject("static"), "Metal")
check(vfx == 0, "and a bow held in hand does not count as a blade")
stub.equipped = swordBefore

print("\n== spark variety ==")
local function sentVfx()
    local out = {}
    for _, ev in ipairs(stub.sentGlobalEvents) do
        if ev.name == "SpawnVfx" then table.insert(out, ev.data) end
    end
    return out
end

local seen, taken = {}, 0
for _ = 1, 40 do
    stub.sentGlobalEvents = {}
    local var = { material = "Metal", hitPos = hitPos }
    stub.impactActorHandlers[1](stub.newObject("npc"), var)
    if var.noVfx then taken = taken + 1 end
    for _, v in ipairs(sentVfx()) do seen[v.model] = true end
end
check(taken == 40, "a plain metal impact is taken over, so the burst can be chosen")
local variants = 0
for _ in pairs(seen) do variants = variants + 1 end
check(variants > 1, "and several different bursts are played (" .. variants .. " over 40 hits)")

stub.sentGlobalEvents = {}
local var = { material = "Stone", hitPos = hitPos }
stub.impactActorHandlers[1](stub.newObject("npc"), var)
check(not var.noVfx, "an impact that also throws dust keeps its own effect")
local extra = sentVfx()
check(#extra == 1 and extra[1].model:find("cluster"),
      "and gets a cluster of hard-thrown sparks over the top")

setting("Effects", "SparkVariety", false)
stub.sentGlobalEvents = {}
var = { material = "Metal", hitPos = hitPos }
stub.impactActorHandlers[1](stub.newObject("npc"), var)
check(not var.noVfx and #sentVfx() == 0, "with variety off, Impact Effects plays its own mesh")
setting("Effects", "SparkVariety", true)

print("\n== the global script carries it out ==")
stub.timeScale = 1
global.eventHandlers.CJ_Slowdown({ scale = 0.2, inTime = 0.05, hold = 0.1, outTime = 0.3 })
local minScale = 1
for _ = 1, 40 do
    stub.realTime = stub.realTime + 0.02
    global.engineHandlers.onUpdate()
    minScale = math.min(minScale, stub.timeScale)
end
check(math.abs(minScale - 0.2) < 0.02, "slow motion eases down to its scale")
check(math.abs(stub.timeScale - 1) < 1e-6, "and comes back to normal speed")

-- A light fades by being handed from one record to a darker one. Track how many
-- are lit on each frame: two at once would read as a flicker, and none would be
-- a hole in the fade.
local function litCount()
    local n = 0
    for _, obj in ipairs(stub.allObjects) do
        if obj.kind == "light" and obj.enabled and obj:isValid() then n = n + 1 end
    end
    return n
end

stub.allObjects = {}
global.eventHandlers.CJ_SpawnLight({ player = stub.player, pos = stub.vec3(1, 2, 3),
    radius = 160, duration = 0.2, power = 1, r = 0.62, g = 0.78, b = 1.0 })
local worst, levels, lastPower = 0, 0, nil
for _ = 1, 40 do
    stub.realTime = stub.realTime + 0.005
    global.engineHandlers.onUpdate()
    local lit = litCount()
    worst = math.max(worst, lit)
    local power = nil
    for _, obj in ipairs(stub.allObjects) do
        if obj.enabled and obj.recordColor then power = obj.recordColor end
    end
    if power and power ~= lastPower then levels = levels + 1 lastPower = power end
end
check(worst <= 1, "never more than one light is lit at a time, so the fade cannot flicker")
check(levels >= 3, "and it steps down through several levels on the way out (" .. levels .. ")")
stub.realTime = stub.realTime + 0.05
global.engineHandlers.onUpdate()
check(litCount() == 0, "and is out at the end")

stub.allObjects = {}
global.eventHandlers.CJ_SpawnLight({ player = stub.player, pos = stub.vec3(4, 5, 6),
    radius = 90, duration = 0.06, power = -0.5, r = 1.0, g = 0.86, b = 0.6 })
check(stub.lastLightRecord and stub.lastLightRecord.isNegative,
      "a negative power asks the engine for a negative light")

print("\n== loading actor.lua ==")
local npc = stub.newObject("npc", { id = "bandit_z" })
stub.install(npc)
stub.hitHandlers, stub.damageListeners = {}, {}
local actor = loadScript("actor.lua")
check(#stub.hitHandlers == 1, "actor registered an onHit handler")
actor.engineHandlers.onActive()
check(#stub.damageListeners == 1, "actor registered its MSS damage listener")

stub.sentObjectEvents = {}
stub.hitHandlers[1]({ attacker = stub.player, successful = true, hitPos = { x = 0, y = 0, z = 0 } })
local told
for _, ev in ipairs(stub.sentObjectEvents) do if ev.name == "CJ_AttackLanded" then told = ev end end
check(told ~= nil and told.target == stub.player, "the victim tells the attacking player the hit landed")
check(told and told.data.hitPos ~= nil, "and where it landed, for the light")
local function landed(attack)
    stub.sentObjectEvents = {}
    attack.attacker = stub.player
    stub.hitHandlers[1](attack)
    for _, ev in ipairs(stub.sentObjectEvents) do
        if ev.name == "CJ_AttackLanded" then return ev.data end
    end
end
check(landed({ successful = true, damage = { fatigue = 12 } }).staminaOnly == true,
      "a punch that takes only stamina says so")
check(landed({ successful = true, damage = { health = 4, fatigue = 12 } }).staminaOnly == false,
      "one that takes health as well is an ordinary hit")
check(landed({ successful = false, damage = { fatigue = 12 } }).staminaOnly == false, "and a miss is neither")

stub.sentObjectEvents = {}
stub.damageListeners[1]({ actor = npc, previousHealth = 10, health = 0, baseHealth = 40,
    hit = { attacker = stub.player, successful = true } })
local killed
for _, ev in ipairs(stub.sentObjectEvents) do if ev.name == "CJ_ActorKilled" then killed = ev end end
check(killed ~= nil, "a lethal blow from the player reports a kill")

print("\n== gear knocked loose on death ==")
local SLOT = stub.packages["openmw.types"].Actor.EQUIPMENT_SLOT
local LOOSE = "SettingsCombatJuiceLooseGear"
local function gearSetting(key, value)
    stub.globalStore[LOOSE] = stub.globalStore[LOOSE] or {}
    stub.globalStore[LOOSE][key] = value
end
local function dress()
    npc.equipment = {
        [SLOT.CarriedRight] = stub.newObject("weapon"),
        [SLOT.CarriedLeft] = stub.newObject("armor"),
        [SLOT.Helmet] = stub.newObject("armor"),
        [SLOT.Boots] = stub.newObject("armor"),
        [SLOT.Cuirass] = stub.newObject("armor"),
        [SLOT.Shirt] = stub.newObject("clothing"),
    }
    return npc.equipment
end
local function die(previousHealth)
    stub.sentGlobalEvents = {}
    stub.damageListeners[1]({ actor = npc, previousHealth = previousHealth or 10, health = 0,
        baseHealth = 40, hit = { attacker = stub.player, successful = true } })
    for _, ev in ipairs(stub.sentGlobalEvents) do
        if ev.name == "CJ_ThrowGear" then return ev.data end
    end
end
local function thrownItems(data)
    local set = {}
    for _, entry in ipairs(data and data.items or {}) do set[entry.item] = true end
    return set
end

npc.position = stub.vec3(100, 0, 0) -- east of the player, who stands at the origin
gearSetting("WeaponLooseChance", 1)
gearSetting("HelmetLooseChance", 1)
gearSetting("BootsLooseChance", 0)
gearSetting("WornLooseChance", 0)
local kit = dress()
local gear = die()
local flew = thrownItems(gear)
check(flew[kit[SLOT.CarriedRight]] and flew[kit[SLOT.CarriedLeft]] and flew[kit[SLOT.Helmet]],
      "at chance 1 the weapon, the shield and the helmet come loose")
check(not flew[kit[SLOT.Boots]] and not flew[kit[SLOT.Cuirass]], "at chance 0 the boots stay on")
check(npc.equipment[SLOT.CarriedRight] == nil and npc.equipment[SLOT.Helmet] == nil
      and npc.equipment[SLOT.Boots] == kit[SLOT.Boots],
      "what came loose is unequipped, the rest is still worn")
check(gear and gear.away and gear.away.x > 0.99, "and it flies away from the killer")

gearSetting("WornLooseChance", 1)
kit = dress()
flew = thrownItems(die())
check(flew[kit[SLOT.Cuirass]] and flew[kit[SLOT.Shirt]], "the other worn pieces have a chance of their own")
check(not flew[kit[SLOT.Boots]], "which the boots, having theirs, are not rolled against again")

gearSetting("BootsLooseChance", 1)
kit = dress()
flew = thrownItems(die())
check(flew[kit[SLOT.Boots]], "boots at chance 1 go flying")

kit = dress()
check(die(0) == nil and npc.equipment == kit, "a corpse hit again sheds nothing")

gearSetting("LooseGearEnabled", false)
check(die() == nil and npc.equipment == kit, "switched off, nothing comes loose")
gearSetting("LooseGearEnabled", true)

stub.contentFiles["LuaPhysicsEngine.omwscripts"] = false
check(die() == nil and npc.equipment == kit, "without LuaPhysics nothing is taken off at all")
stub.contentFiles["LuaPhysicsEngine.omwscripts"] = nil

gear = die()
stub.sentObjectEvents = {}
math.randomseed(1) -- the scatter is random; a single item can go a little backwards
global.eventHandlers.CJ_ThrowGear(gear)
local impulses, upward, awayward = 0, true, 0
for _, ev in ipairs(stub.sentObjectEvents) do
    if ev.name == "LuaPhysics_ApplyImpulse" and ev.target.teleported then
        impulses = impulses + 1
        upward = upward and ev.data.impulse.z > 0
        awayward = awayward + ev.data.impulse.x
    end
end
check(impulses == #gear.items, "the global script puts every item in the world and throws it")
check(upward and awayward > 0, "up and away from the killer, rather than dropped")

print("\n== a shader that will not load ==")
stub.install(stub.player)
stub.packages["openmw.postprocessing"].load = function()
    error("Failed loading shader 'cc_killflash'")
end
stub.settingsPages, stub.settingsGroups = {}, {}
stub.hitHandlers = {}
local okLoad, player2 = pcall(loadScript, "player.lua")
check(okLoad, "the player script still loads")
setting("Slowdown", "SmallSlowdownChance", 1) -- loading it put the default back
if okLoad then
    stub.sentGlobalEvents = {}
    player2.eventHandlers.CJ_ActorKilled({ victim = stub.newObject("npc") })
    check(sentSlowdown() ~= nil, "and kills still slow time")
    check(pcall(player2.engineHandlers.onFrame), "and onFrame does not touch the missing shader")
end

print(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)

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
check(#stub.settingsGroups == 6, "six settings groups registered")

local slow = stub.settingsStore["SettingsCombatJuiceSlowdown"]
check(slow.SmallSlowdownTrigger == "Every kill", "the short slow motion defaults to every kill")
check(slow.SmallSlowdownChance == 1, "at 100% by default")
check(slow.BigSlowdownTrigger == "Long encounter end", "the long one defaults to long fights only")
check(slow.BigSlowdownChance == 1, "at 100% by default")
check(slow.LongEncounterSeconds == 20, "a long fight is 20 seconds by default")
local cam = stub.settingsStore["SettingsCombatJuiceCamera"]
check(cam.ShakeStrength == 1.0 and cam.ShakeDuration == 0.3 and cam.ShakeFrequency == 38,
      "camera shake defaults match the tuned in-game settings")
check(cam.ShakeTakenHitFactor == 0, "and taking a hit does not shake by default")
check(stub.settingsStore["SettingsCombatJuiceFlash"].FlashOn == "Short slow motion",
      "the kill flash rides the short slow motion by default")

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
check(s and math.abs((s.inTime + s.hold + s.outTime) - 1.5) < 1e-6,
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
check(#hm.ids >= 5, "every definition file in hitmarkers/ is found (" .. #hm.ids .. ")")
local byStyle = { slide = 0, fade = 0 }
for _, id in ipairs(hm.ids) do
    local def = hm.get(id)
    byStyle[def.style] = (byStyle[def.style] or 0) + 1
end
check(byStyle.slide >= 2 and byStyle.fade >= 3,
      "both animation styles are represented, Dynamic Reticle's and Stupid-Metal's")
check(hm.get("sm_skull").recolour == false, "the skull is marked as keeping its own colours")
check(hm.get("faded_triangles").recolour == true, "and the white art takes the colour setting")
check(#hm.get("faded_triangles").parts == 4 and #hm.get("sm_skull").parts == 1,
      "a marker can be four pieces or one")

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

stub.sentObjectEvents = {}
stub.damageListeners[1]({ actor = npc, previousHealth = 10, health = 0, baseHealth = 40,
    hit = { attacker = stub.player, successful = true } })
local killed
for _, ev in ipairs(stub.sentObjectEvents) do if ev.name == "CJ_ActorKilled" then killed = ev end end
check(killed ~= nil, "a lethal blow from the player reports a kill")

print("\n== a shader that will not load ==")
stub.install(stub.player)
stub.packages["openmw.postprocessing"].load = function()
    error("Failed loading shader 'cc_killflash'")
end
stub.settingsPages, stub.settingsGroups = {}, {}
stub.hitHandlers = {}
local okLoad, player2 = pcall(loadScript, "player.lua")
check(okLoad, "the player script still loads")
if okLoad then
    stub.sentGlobalEvents = {}
    player2.eventHandlers.CJ_ActorKilled({ victim = stub.newObject("npc") })
    check(sentSlowdown() ~= nil, "and kills still slow time")
    check(pcall(player2.engineHandlers.onFrame), "and onFrame does not touch the missing shader")
end

print(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)

-- Runs the mod scripts against a stubbed OpenMW API, so the wiring can be
-- checked without starting the game:
--
--     lua tools/tests/test.lua "scripts/MaxYari/cinematic combat"
--
package.path = package.path .. ";" .. arg[1] .. "/?.lua;" .. arg[0]:gsub("[^/]*$", "") .. "?.lua"
local MOD = arg[1]

local stub = require("stub")
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
        if name:match("cinematic combat") then
            if loaded[name] then return loaded[name] end
            local file = MOD .. "/" .. name:gsub("scripts/MaxYari/cinematic combat/", "") .. ".lua"
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
    stub.setSetting("SettingsCinematicCombat" .. group, key, value)
end

local function sentSlowdown()
    for _, e in ipairs(stub.sentGlobalEvents) do
        if e.name == "CC_Slowdown" then return e.data end
    end
end

local function sentLights()
    local out = {}
    for _, e in ipairs(stub.sentGlobalEvents) do
        if e.name == "CC_SpawnLight" then table.insert(out, e.data) end
    end
    return out
end

print("== loading global.lua ==")
stub.install(stub.player)
_G.require = makeLoader()
local global = loadScript("global.lua")
check(type(global.engineHandlers.onUpdate) == "function", "global exposes onUpdate")
check(global.eventHandlers.CC_Slowdown ~= nil, "global takes slow motion requests")

print("\n== loading player.lua ==")
stub.enableImpactEffects()
local player = loadScript("player.lua")
check(#stub.settingsPages == 1, "one settings page registered")
check(#stub.settingsGroups == 4, "four settings groups registered")

local slow = stub.settingsStore["SettingsCinematicCombatSlowdown"]
check(slow.SmallSlowdownTrigger == "Every kill", "the short slow motion defaults to every kill")
check(slow.SmallSlowdownChance == 1, "at 100% by default")
check(slow.BigSlowdownTrigger == "Long encounter end", "the long one defaults to long fights only")
check(slow.BigSlowdownChance == 1, "at 100% by default")
check(slow.LongEncounterSeconds == 20, "a long fight is 20 seconds by default")
local cam = stub.settingsStore["SettingsCinematicCombatCamera"]
check(cam.ShakeStrength == 1.0 and cam.ShakeDuration == 0.3 and cam.ShakeFrequency == 38,
      "camera shake defaults match the tuned in-game settings")
check(cam.ShakeTakenHitFactor == 0, "and taking a hit does not shake by default")
check(stub.settingsStore["SettingsCinematicCombatFlash"].FlashTrigger == "Every kill",
      "the kill flash defaults to every kill")

print("\n== a plain kill ==")
player.engineHandlers.onUpdate(0.016)
local a = stub.newObject("npc", { id = "bandit_a" })
local b = stub.newObject("npc", { id = "bandit_b" })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = a, targets = { stub.player } })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = b, targets = { stub.player } })

stub.sentGlobalEvents = {}
a.dead = true
player.eventHandlers.CC_ActorKilled({ victim = a })
local s = sentSlowdown()
check(s ~= nil, "a kill mid fight still slows time")
check(s and math.abs((s.inTime + s.hold + s.outTime) - 0.22) < 1e-6,
      "with the short slow motion's duration")

print("\n== the last enemy of a short fight ==")
stub.sentGlobalEvents = {}
stub.realTime = stub.realTime + 3
b.dead = true
player.eventHandlers.CC_ActorKilled({ victim = b })
s = sentSlowdown()
check(s ~= nil and math.abs((s.inTime + s.hold + s.outTime) - 0.22) < 1e-6,
      "gets the short one too: the long one is set to long fights only")

print("\n== the last enemy of a long fight ==")
local c = stub.newObject("npc", { id = "bandit_c" })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = c, targets = { stub.player } })
stub.realTime = stub.realTime + 25 -- a long fight
stub.sentGlobalEvents = {}
c.dead = true
player.eventHandlers.CC_ActorKilled({ victim = c })
s = sentSlowdown()
check(s ~= nil, "slows time")
check(s and math.abs((s.inTime + s.hold + s.outTime) - 0.45) < 1e-6,
      "and the long slow motion wins, since both qualified")

print("\n== triggers and chance ==")
setting("Slowdown", "SmallSlowdownTrigger", "Encounter end")
local d = stub.newObject("npc", { id = "bandit_d" })
local e = stub.newObject("npc", { id = "bandit_e" })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = d, targets = { stub.player } })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = e, targets = { stub.player } })
stub.sentGlobalEvents = {}
d.dead = true
player.eventHandlers.CC_ActorKilled({ victim = d })
check(sentSlowdown() == nil, "'encounter end' skips a kill in the middle of a fight")
stub.sentGlobalEvents = {}
e.dead = true
player.eventHandlers.CC_ActorKilled({ victim = e })
check(sentSlowdown() ~= nil, "and takes the one that ends it")

setting("Slowdown", "SmallSlowdownTrigger", "Every kill")
setting("Slowdown", "SmallSlowdownChance", 0)
stub.sentGlobalEvents = {}
player.eventHandlers.CC_ActorKilled({ victim = stub.newObject("npc") })
check(sentSlowdown() == nil, "a chance of 0 never plays")
setting("Slowdown", "SmallSlowdownChance", 1)

setting("Slowdown", "SlowdownEnabled", false)
stub.sentGlobalEvents = {}
player.eventHandlers.CC_ActorKilled({ victim = stub.newObject("npc") })
check(sentSlowdown() == nil, "and the group can be switched off entirely")
setting("Slowdown", "SlowdownEnabled", true)

print("\n== the kill flash ==")
stub.shaderUniform = nil
player.eventHandlers.CC_ActorKilled({ victim = stub.newObject("npc") })
stub.realTime = stub.realTime + 0.1
player.engineHandlers.onFrame()
check(stub.shaderUniform ~= nil and stub.shaderUniform > 0, "fires on a plain kill by default")
stub.realTime = stub.realTime + 2
player.engineHandlers.onFrame()
check(stub.shaderUniform == 0, "and fades out")

setting("Flash", "FlashTrigger", "Long encounter end")
stub.shaderUniform = nil
player.eventHandlers.CC_ActorKilled({ victim = stub.newObject("npc") })
player.engineHandlers.onFrame()
check(stub.shaderUniform == nil, "set to long fights only, a plain kill does not fire it")
setting("Flash", "FlashTrigger", "Every kill")

print("\n== camera shake and impact lights ==")
local function frame(dt)
    stub.realTime = stub.realTime + (dt or 0.016)
    stub.cameraExtras = { pitch = 0, yaw = 0, roll = 0 }
    player.engineHandlers.onFrame()
end

stub.sentGlobalEvents = {}
player.eventHandlers.CC_AttackLanded({ victim = stub.newObject("npc"), successful = true,
                                       hitPos = { x = 1, y = 2, z = 3 } })
frame()
local moved = math.abs(stub.cameraExtras.pitch) + math.abs(stub.cameraExtras.yaw)
    + math.abs(stub.cameraExtras.roll)
check(moved > 0 and moved < math.rad(15), "a landed hit shakes the camera")

local lights = sentLights()
check(#lights == 1, "and lights the hit")
check(lights[1] and lights[1].r > lights[1].b, "with the warm light, since nothing sparked")

stub.sentGlobalEvents = {}
stub.impactActorHandlers[1](stub.newObject("npc"),
    { material = "ParryArmorHeavy", hitPos = { x = 1, y = 2, z = 3 } })
lights = sentLights()
check(#lights == 1 and lights[1].b > lights[1].r, "a spark material lights it cold instead")

player.eventHandlers.CC_AttackLanded({ victim = stub.newObject("npc"), successful = true,
                                       hitPos = { x = 1, y = 2, z = 3 } })
check(#sentLights() == 1, "and the warm light does not double up on the same hit")

stub.sentGlobalEvents = {}
player.eventHandlers.CC_AttackLanded({ victim = stub.newObject("npc"), successful = false })
check(#sentLights() == 0, "a miss lights nothing")

print("\n== the global script carries it out ==")
stub.timeScale = 1
global.eventHandlers.CC_Slowdown({ scale = 0.2, inTime = 0.05, hold = 0.1, outTime = 0.3 })
local minScale = 1
for _ = 1, 40 do
    stub.realTime = stub.realTime + 0.02
    global.engineHandlers.onUpdate()
    minScale = math.min(minScale, stub.timeScale)
end
check(math.abs(minScale - 0.2) < 0.02, "slow motion eases down to its scale")
check(math.abs(stub.timeScale - 1) < 1e-6, "and comes back to normal speed")

global.eventHandlers.CC_SpawnLight({ player = stub.player, pos = { x = 1, y = 2, z = 3 },
    radius = 160, duration = 0.09, r = 0.62, g = 0.78, b = 1.0 })
global.eventHandlers.CC_SpawnLight({ player = stub.player, pos = { x = 4, y = 5, z = 6 },
    radius = 90, duration = 0.06, r = 1.0, g = 0.86, b = 0.6 })
local saved = global.engineHandlers.onSave()
local sets = 0
for _ in pairs(saved.lightSets or {}) do sets = sets + 1 end
check(sets == 2, "the cold and the warm light get a record and a pool each")
stub.realTime = stub.realTime + 0.2
global.engineHandlers.onUpdate()
check(true, "and both are switched off again without error")

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
for _, ev in ipairs(stub.sentObjectEvents) do if ev.name == "CC_AttackLanded" then told = ev end end
check(told ~= nil and told.target == stub.player, "the victim tells the attacking player the hit landed")
check(told and told.data.hitPos ~= nil, "and where it landed, for the light")

stub.sentObjectEvents = {}
stub.damageListeners[1]({ actor = npc, previousHealth = 10, health = 0, baseHealth = 40,
    hit = { attacker = stub.player, successful = true } })
local killed
for _, ev in ipairs(stub.sentObjectEvents) do if ev.name == "CC_ActorKilled" then killed = ev end end
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
    player2.eventHandlers.CC_ActorKilled({ victim = stub.newObject("npc") })
    check(sentSlowdown() ~= nil, "and kills still slow time")
    check(pcall(player2.engineHandlers.onFrame), "and onFrame does not touch the missing shader")
end

print(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)

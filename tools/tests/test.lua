-- Runs the mod scripts against a stubbed OpenMW API, so the wiring can be checked
-- without starting the game:
--
--     lua tools/tests/test.lua "scripts/MaxYari/cinematic combat"
--
-- Drives the Cinematic Combat scripts against the stubbed OpenMW API.
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

-- OpenMW resolves `require("scripts/MaxYari/...")` paths; map them to disk.
local function modRequire(path)
    local file = MOD .. "/" .. path:gsub("%.", "/"):gsub("scripts/MaxYari/cinematic combat/", "") .. ".lua"
    return file
end

local loaded = {}
local function makeLoader()
    local real = _G.require
    return function(name)
        if stub.packages[name] then return stub.packages[name] end
        if name:match("cinematic combat") then
            if loaded[name] then return loaded[name] end
            local file = MOD .. "/" .. name:gsub("scripts/MaxYari/cinematic combat/", "") .. ".lua"
            local chunk = assert(loadfile(file))
            loaded[name] = chunk()
            return loaded[name]
        end
        return real(name)
    end
end

print("== loading global.lua ==")
stub.install(stub.player)
_G.require = makeLoader()
local global = assert(loadfile(MOD .. "/global.lua"))()
check(type(global.engineHandlers.onUpdate) == "function", "global exposes onUpdate")

print("\n== loading player.lua ==")
loaded = {}
_G.require = makeLoader()
local player = assert(loadfile(MOD .. "/player.lua"))()
check(#stub.settingsPages == 1, "one settings page registered")
check(#stub.settingsGroups == 4, "four settings groups registered")
check(#stub.textKeyHandlers == 1, "player registered a text key handler")
check(#stub.hitHandlers == 1, "player registered an onHit handler")

local hitstopDefaults = stub.settingsStore["SettingsCinematicCombatHitstop"]
check(hitstopDefaults.HitstopDuration == 0.1, "hit stop duration defaults to 0.1")
check(hitstopDefaults.HitstopTimeScale == 0.1, "hit stop time scale defaults to 0.1")
check(stub.settingsStore["SettingsCinematicCombatSlowdown"].SlowdownOnKillChance == 0,
      "kill chance defaults to 0 so the encounter path can be tested alone")

-- player onInit should mirror the settings actors need
player.engineHandlers.onInit()
local synced
for _, e in ipairs(stub.sentGlobalEvents) do if e.name == "CC_SyncShared" then synced = e.data end end
check(synced ~= nil and synced.hitFreezeFrames == 2, "shared settings mirrored to the global script")

print("\n== a swing that hits ==")
stub.sentGlobalEvents = {}
stub.skipAnimCalls = 0
stub.textKeyHandlers[1]("weapononehand", "chop min hit")
player.engineHandlers.onUpdate(0.016)
check(stub.skipAnimCalls == 0, "'min hit' does not hold the animation")

stub.textKeyHandlers[1]("weapononehand", "chop hit")
player.engineHandlers.onUpdate(0.016)
player.engineHandlers.onUpdate(0.016)
check(stub.skipAnimCalls == 2, "the hit key holds the animation for 2 frames")
player.engineHandlers.onUpdate(0.016)
check(stub.skipAnimCalls == 2, "the hold stops on its own")

player.eventHandlers.CC_AttackLanded({ victim = stub.newObject("npc"), successful = true })
local hitstop
for _, e in ipairs(stub.sentGlobalEvents) do
    if e.name == "CC_TimeEffect" and e.data.kind == "hitstop" then hitstop = e.data end
end
check(hitstop ~= nil, "a landed hit asks for a hit stop")
check(hitstop and hitstop.scale == 0.1 and hitstop.duration == 0.1, "with the configured scale and duration")

print("\n== a swing that misses ==")
stub.sentGlobalEvents = {}
player.eventHandlers.CC_AttackLanded({ victim = stub.newObject("npc"), successful = false })
local anyStop = false
for _, e in ipairs(stub.sentGlobalEvents) do if e.name == "CC_TimeEffect" then anyStop = true end end
check(not anyStop, "a miss does not stop time with the default settings")

print("\n== encounters ==")
local a, b = stub.newObject("npc", { id = "bandit_a" }), stub.newObject("npc", { id = "bandit_b" })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = a, targets = { stub.player } })
player.eventHandlers.OMWMusicCombatTargetsChanged({ actor = b, targets = { stub.player } })

stub.sentGlobalEvents = {}
a.dead = true
player.eventHandlers.CC_ActorKilled({ victim = a })
local slow = nil
for _, e in ipairs(stub.sentGlobalEvents) do
    if e.name == "CC_TimeEffect" and e.data.kind == "slowdown" then slow = e.data end
end
check(slow == nil, "killing one of two enemies does not slow time (chance is 0)")

stub.sentGlobalEvents = {}
b.dead = true
player.eventHandlers.CC_ActorKilled({ victim = b })
for _, e in ipairs(stub.sentGlobalEvents) do
    if e.name == "CC_TimeEffect" and e.data.kind == "slowdown" then slow = e.data end
end
check(slow ~= nil, "killing the last enemy of the encounter always slows time")
check(slow and slow.scale == 0.2, "at the configured time scale")

print("\n== camera shake and the kill vignette ==")
-- The engine's own camera script zeroes the extra angles in its onUpdate, which
-- runs before our onFrame, so a frame here does the same.
local function frame(dt)
    stub.realTime = stub.realTime + (dt or 0.016)
    stub.cameraExtras = { pitch = 0, yaw = 0, roll = 0 }
    player.engineHandlers.onFrame()
end

-- The kill above started the vignette.
stub.shaderUniform = nil
frame(0.1)
check(stub.shaderUniform ~= nil and stub.shaderUniform > 0, "the kill vignette is fading in")
frame(1.0)
check(stub.shaderUniform == 0, "and is back to nothing once it is over")

player.interface.shake(1)
frame()
local moved = math.abs(stub.cameraExtras.pitch) + math.abs(stub.cameraExtras.yaw)
    + math.abs(stub.cameraExtras.roll)
check(moved > 0, "the camera shake moves the camera")
check(moved < math.rad(15), "by a sane number of degrees")
frame(1.0)
check(stub.cameraExtras.pitch == 0 and stub.cameraExtras.yaw == 0 and stub.cameraExtras.roll == 0,
      "and settles back to zero")

print("\n== a murder out of combat ==")
stub.realTime = stub.realTime + 60 -- long after that fight
stub.sentGlobalEvents = {}
player.eventHandlers.CC_ActorKilled({ victim = stub.newObject("npc", { id = "trader" }) })
slow = nil
for _, e in ipairs(stub.sentGlobalEvents) do
    if e.name == "CC_TimeEffect" and e.data.kind == "slowdown" then slow = e.data end
end
check(slow == nil, "killing a bystander who was not fighting does not count as ending an encounter")

print("\n== global script carries out the time effects ==")
stub.timeScale = 1
global.eventHandlers.CC_TimeEffect({ kind = "hitstop", scale = 0.1, duration = 0.1 })
check(stub.timeScale == 0.1, "hit stop applies its scale immediately, with no ramp")
stub.realTime = stub.realTime + 0.05
global.engineHandlers.onUpdate()
check(stub.timeScale == 0.1, "and holds it")
stub.realTime = stub.realTime + 0.06
global.engineHandlers.onUpdate()
check(stub.timeScale == 1, "and releases it abruptly when the duration is up")

global.eventHandlers.CC_TimeEffect({ kind = "slowdown", scale = 0.2, inTime = 0.05, hold = 0.1, outTime = 0.3 })
local minScale = 1
for _ = 1, 40 do
    stub.realTime = stub.realTime + 0.02
    global.engineHandlers.onUpdate()
    minScale = math.min(minScale, stub.timeScale)
end
check(math.abs(minScale - 0.2) < 0.02, "kill slow motion eases down to its scale")
check(math.abs(stub.timeScale - 1) < 1e-6, "and comes back to normal speed")

print("\n== the spark light ==")
stub.sentGlobalEvents = {}
global.eventHandlers.CC_SparkFlash({ player = stub.player, pos = { x = 1, y = 2, z = 3 },
    radius = 160, duration = 0.09, r = 0.6, g = 0.8, b = 1.0 })
local lit = global.engineHandlers.onSave and global.engineHandlers.onSave()
check(lit ~= nil and lit.lightRecordId ~= nil, "a light record is created on the first flash")
stub.realTime = stub.realTime + 0.2
global.engineHandlers.onUpdate()
check(true, "the light is switched off again without error")

print("\n== loading actor.lua ==")
local npc = stub.newObject("npc", { id = "bandit_c" })
stub.install(npc)
loaded = {}
_G.require = makeLoader()
stub.textKeyHandlers, stub.hitHandlers, stub.damageListeners = {}, {}, {}
local actor = assert(loadfile(MOD .. "/actor.lua"))()
check(#stub.hitHandlers == 1, "actor registered an onHit handler")
check(#stub.textKeyHandlers == 1, "actor registered a text key handler")
actor.engineHandlers.onActive()
check(#stub.damageListeners == 1, "actor registered its MSS damage listener")

stub.sentObjectEvents = {}
stub.hitHandlers[1]({ attacker = stub.player, successful = true, hitPos = { x = 0, y = 0, z = 0 } })
local told
for _, e in ipairs(stub.sentObjectEvents) do if e.name == "CC_AttackLanded" then told = e end end
check(told ~= nil and told.target == stub.player, "the victim tells the attacking player the hit landed")

stub.sentObjectEvents = {}
stub.damageListeners[1]({ actor = npc, previousHealth = 10, health = 0, baseHealth = 40,
    hit = { attacker = stub.player, successful = true } })
local killed
for _, e in ipairs(stub.sentObjectEvents) do if e.name == "CC_ActorKilled" then killed = e end end
check(killed ~= nil, "a lethal blow from the player reports a kill")

-- NPC hit key hold, once the player's settings have been mirrored
stub.globalStore["CinematicCombatShared"] = { freezeNpcAttacks = true, hitFreezeFrames = 2 }
loaded = {}
_G.require = makeLoader()
stub.textKeyHandlers = {}
local actor2 = assert(loadfile(MOD .. "/actor.lua"))()
stub.skipAnimCalls = 0
stub.textKeyHandlers[1]("weapononehand", "slash hit")
actor2.engineHandlers.onUpdate(0.016)
actor2.engineHandlers.onUpdate(0.016)
actor2.engineHandlers.onUpdate(0.016)
check(stub.skipAnimCalls == 2, "an enemy's swing is held at its hit key too")

print(string.format("\n%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)

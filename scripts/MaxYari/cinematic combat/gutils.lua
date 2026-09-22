local module = {}

DebugLevel = DebugLevel or 1

function module.print(...)
    local args = { ... }
    local lvl = args[#args]
    if type(lvl) ~= "number" then lvl = 1 else table.remove(args) end
    if lvl > DebugLevel then return end
    for i, v in ipairs(args) do args[i] = tostring(v) end
    print("[CinematicCombat]: " .. table.concat(args, " "))
end

function module.lerp(a, b, t)
    return a + (b - a) * t
end

function module.clamp(v, min, max)
    if v < min then return min end
    if v > max then return max end
    return v
end

-- A cheap deterministic-ish noise in -1..1, used for the camera shake so it
-- wobbles instead of swinging like a pendulum.
function module.noise(t)
    return math.sin(t * 12.9898) * 0.6 + math.sin(t * 27.7 + 1.3) * 0.3 + math.sin(t * 53.3 + 2.1) * 0.1
end

return module

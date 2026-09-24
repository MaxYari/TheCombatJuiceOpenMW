-- The hit marker sounds, gathered from the VFS so that dropping a wav in the
-- folder is all it takes to add one.

local vfs = require("openmw.vfs")

local PREFIX = "sounds/MaxYari/combat juice/hitmarkers/"

local module = { names = {}, paths = {} }

for path in vfs.pathsWithPrefix(PREFIX) do
    local name = path:sub(#PREFIX + 1):gsub("%.%w+$", "")
    if name ~= "" then
        table.insert(module.names, name)
        module.paths[name] = path
    end
end
table.sort(module.names)

function module.path(name)
    return module.paths[name] or module.paths[module.names[1]]
end

return module

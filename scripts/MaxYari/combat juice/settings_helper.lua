local storage = require("openmw.storage")
local async = require("openmw.async")

--- A little helper that for live settings update without constantly hitting the storage
local SettingsHelper = {}
SettingsHelper.__index = SettingsHelper
function SettingsHelper:new(sectionName)
    local inst = {
        sectionName = sectionName,
        store = storage.playerSection(sectionName),
        settings = {},
        trackedSettings = {}
    }

    inst.store:subscribe(async:callback(function(val)
        -- a setting changed: refresh everything this script has ever read
        for key, _ in pairs(inst.trackedSettings) do
            inst.settings[key] = inst.store:get(key)
        end
    end))

    -- Im not sure how this whole metatable nonesense works - but it does
    setmetatable(inst, self)

    return inst
end

function SettingsHelper:__index(key)
    if not self.trackedSettings[key] then
        self.trackedSettings[key] = true
        self.settings[key] = self.store:get(key)
    end
    return self.settings[key]
end

return SettingsHelper

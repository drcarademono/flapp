local State = require("core/state")
local Save = {}; Save.__index = Save

function Save.new(path, LuaSettings)
    return setmetatable({path=path, settings=LuaSettings:open(path)},Save)
end

function Save:load()
    local data=self.settings:readSetting("state")
    if data==nil then return nil end
    local ok,value=pcall(State.validate,State.copy(data)); if not ok then return nil,value end
    return value
end

function Save:write(state)
    State.validate(state)
    self.settings:saveSetting("state",State.copy(state)); self.settings:flush()
    return true
end

function Save:clear()
    self.settings:delSetting("state"); self.settings:flush()
end

return Save

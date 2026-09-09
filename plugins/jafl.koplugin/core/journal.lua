local State = require("core/state")
local Journal = {}; Journal.__index = Journal

function Journal.new(state, random)
    state.rng=state.rng or {draws={},cursor=0}
    return setmetatable({state=state,source=random or math.random},Journal)
end

function Journal:draw(sides)
    local rng=self.state.rng
    local value=self.source(sides)
    rng.draws[#rng.draws+1]={sides=sides,value=value}
    rng.cursor=#rng.draws
    return value
end

function Journal:begin(label)
    assert(not self.transaction,"nested game transaction")
    self.transaction={label=label,before=State.copy(self.state)}
end

function Journal:commit()
    self.transaction=nil
end

function Journal:rollback()
    if not self.transaction then return end
    State.replace(self.state,self.transaction.before)
    self.transaction=nil
end

return Journal

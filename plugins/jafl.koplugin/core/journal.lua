local State = require("core/state")
local Journal = {}; Journal.__index = Journal

function Journal.new(state, random)
    state.rng=state.rng or {draws={},cursor=0}
    state.undo=state.undo or {}
    return setmetatable({state=state,source=random or math.random},Journal)
end

function Journal:draw(sides)
    local rng=self.state.rng
    if rng.cursor<#rng.draws then
        rng.cursor=rng.cursor+1
        local saved=rng.draws[rng.cursor]
        assert(saved.sides==sides,"saved RNG draw does not match requested die")
        return saved.value
    end
    local value=self.source(sides)
    rng.draws[#rng.draws+1]={sides=sides,value=value}
    rng.cursor=#rng.draws
    return value
end

function Journal:begin(label,metadata)
    assert(not self.transaction,"nested game transaction")
    -- Keep history outside snapshots; otherwise every record recursively copies
    -- all earlier records and save files grow exponentially.
    local undo=self.state.undo; self.state.undo=nil
    local before=State.copy(self.state); self.state.undo=undo
    self.transaction={label=label,metadata=State.copy(metadata),before=before,undo=State.copy(undo)}
end

function Journal:commit()
    if self.transaction and self.transaction.label~="reroll" then
        self.state.undo[#self.state.undo+1]={label=self.transaction.label,metadata=self.transaction.metadata,before=self.transaction.before}
        if #self.state.undo>10 then table.remove(self.state.undo,1) end
    end
    self.transaction=nil
end

function Journal:rollback()
    if not self.transaction then return end
    State.replace(self.state,self.transaction.before)
    self.state.undo=self.transaction.undo
    self.transaction=nil
end

function Journal:undo()
    local record=table.remove(self.state.undo)
    if not record then return nil,"There is no action to undo." end
    local remaining=self.state.undo
    State.replace(self.state,record.before); self.state.undo=remaining
    return record
end

return Journal

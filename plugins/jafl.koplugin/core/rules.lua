local Rules={}

local function add(target,value)
    for name in tostring(value or ""):gmatch("[^,]+") do target[name:match("^%s*(.-)%s*$"):lower()]=true end
end

function Rules.set_fixed(state,value)
    state.models.rules.fixed={}; add(state.models.rules.fixed,value); return state.models.rules.fixed
end

function Rules.enter_book(state,properties)
    state.models.rules.temporary={}; add(state.models.rules.temporary,properties and properties.Rules)
    return state.models.rules.temporary
end

function Rules.active(state,name)
    name=tostring(name or ""):lower()
    return state.models.rules.fixed[name] or state.models.rules.temporary[name] or false
end

return Rules

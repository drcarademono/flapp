local Stats={}
Stats.basic={Charisma=true,Combat=true,Magic=true,Sanctity=true,Scouting=true,Thievery=true}

local function key(name) return tostring(name or ""):gsub("^%l",string.upper) end

function Stats.dead(state)
    if state.stamina<=0 then return true end
    for name in pairs(Stats.basic) do if (state.models.stats.natural[name] or state.abilities[name] or 0)<=0 then return true end end
    return false
end

-- Adventurer.adjustAbility: basic abilities are naturally bounded 1..12;
-- a fatal underflow kills through current Stamina but leaves the natural score 1.
function Stats.adjust(state,name,delta,fatal)
    name=key(name); delta=tonumber(delta) or 0
    if Stats.basic[name] then
        local old=state.models.stats.natural[name] or state.abilities[name] or 0
        local target=old+delta; local death=fatal and target<1
        target=math.max(1,math.min(12,target)); local applied=target-old
        state.models.stats.natural[name]=target; state.abilities[name]=target
        if death then state.stamina=0 end
        return applied,death
    elseif name=="Rank" then
        local old=state.rank or 1; local target=old+delta; local death=fatal and target<=0
        if target<=0 then target=1 end
        state.rank=target
        if death then state.stamina=0 end
        return target-old,death
    elseif name=="Stamina" then
        local old=state.max_stamina or 0; local target=old+delta; local death=fatal and target<1
        if target<1 then target=1 end
        local applied=target-old; state.max_stamina=target
        state.stamina=math.max(0,math.min(target,(state.stamina or 0)+applied))
        if death then state.stamina=0 end
        return applied,death
    elseif name=="Defence" then return 0,false end
    return 0,false
end

function Stats.damage(state,amount)
    local old=state.stamina; state.stamina=math.max(0,old-math.max(0,tonumber(amount) or 0)); return old-state.stamina,state.stamina==0
end

function Stats.heal(state,amount)
    amount=tonumber(amount) or -1
    local old=state.stamina
    if amount<0 then state.stamina=state.max_stamina else state.stamina=math.min(state.max_stamina,state.stamina+amount) end
    return state.stamina-old
end

return Stats

local State=require("core/state")
local Inventory={}

function Inventory.tags(value)
    if type(value)=="table" then return value end
    local out={}; for tag in tostring(value or ""):gmatch("[^,%s|]+") do out[tag:lower()]=true end
    return out
end

function Inventory.prepare_item(item)
    item=State.new_item(item); item.id=item.id or (item.kind..":"..item.name..":"..tostring(item.bonus or 0))
    item.tags=Inventory.tags(item.tags)
    for i,effect in ipairs(item.effects) do item.effects[i]=State.new_effect(effect) end
    return item
end

function Inventory.matches(item,wanted)
    wanted=wanted or {}; local name=wanted.item or wanted.name or wanted.weapon or wanted.armour or wanted.tool
    if name and name~="*" and item.name:lower()~=name:lower() then return false end
    local kind=wanted.weapon and "weapon" or wanted.armour and "armour" or wanted.tool and "tool"
    if kind and item.kind~=kind and not item[kind] then return false end
    if wanted.group and item.group~=wanted.group then return false end
    if wanted.bonus and tonumber(item.bonus)~=tonumber(wanted.bonus) then return false end
    for tag in pairs(Inventory.tags(wanted.tags)) do if not Inventory.tags(item.tags)[tag] then return false end end
    return true
end

function Inventory.count(state,wanted)
    local count=0; for _,item in ipairs(state.items) do if Inventory.matches(item,wanted) then count=count+(item.quantity or 1) end end
    return count
end

function Inventory.equip(state,item)
    if item.kind=="weapon" or item.kind=="armour" then
        local slot=item.kind
        for _,candidate in ipairs(state.items) do if candidate.kind==slot then candidate.equipped=false end end
        item.equipped=true; state.models.equipment[slot]=item.id
    elseif item.kind=="tool" then item.equipped=true; state.models.equipment.tools[item.id]=true end
end

function Inventory.unequip(state,item)
    item.equipped=false
    if state.models.equipment[item.kind]==item.id then state.models.equipment[item.kind]=nil end
    if item.kind=="tool" then state.models.equipment.tools[item.id]=nil end
end

local function effects_from(state)
    local out={}
    for _,item in ipairs(state.items) do
        for _,effect in ipairs(item.effects or {}) do
            local active=effect.kind=="aura" or (effect.kind=="wielded" and item.equipped) or
                (effect.kind=="tool" and item.equipped)
            if active then out[#out+1]=effect end
        end
    end
    for god,effects in pairs(state.models.god_effects or {}) do if state.gods[god] then
        for _,effect in ipairs(effects) do out[#out+1]=effect end
    end end
    for _,collection in pairs(state.models.afflictions) do
        for _,affliction in pairs(collection) do
            if type(affliction)=="table" then
                if affliction.effects then for _,effect in ipairs(affliction.effects) do out[#out+1]=effect end
                else for _,instance in ipairs(affliction) do for _,effect in ipairs(instance.effects or {}) do out[#out+1]=effect end end end
            end
        end
    end
    return out
end

function Inventory.attach_god_effects(state,god,node)
    local effects={}
    for _,child in ipairs(node.children or {}) do if type(child)=="table" and child.name=="effect" then
        effects[#effects+1]=State.new_effect{kind=child.attr.type or "aura",ability=child.attr.ability,
            operation=child.attr.target and "target" or child.attr.divide and "divide" or "add",
            value=child.attr.bonus or child.attr.divide or child.attr.target}
    end end
    if #effects>0 then state.models.god_effects[god]=effects end
end

function Inventory.ability(state,name,modifier)
    local natural=state.models.stats.natural[name] or state.abilities[name] or (name=="Rank" and state.rank) or 0
    if name=="Defence" then
        natural=(state.models.stats.natural.Combat or state.abilities.Combat or 0)+(state.rank or 0)
    end
    if modifier=="natural" then return natural end
    local value=state.abilities[name] or (name=="Rank" and state.rank) or natural
    if name=="Combat" then
        local id=state.models.equipment.weapon
        for _,item in ipairs(state.items) do if item.id==id and item.equipped then value=value+(tonumber(item.bonus) or 0); break end end
    elseif name=="Defence" then
        value=natural; local id=state.models.equipment.armour
        for _,item in ipairs(state.items) do if item.id==id and item.equipped then value=value+(tonumber(item.bonus) or 0); break end end
    else
        local best=0
        for _,item in ipairs(state.items) do if item.kind=="tool" and item.equipped and tostring(item.ability or ""):lower()==name:lower() then best=math.max(best,tonumber(item.bonus) or 0) end end
        value=value+best
    end
    for _,effect in ipairs(effects_from(state)) do
        if effect.ability=="*" or tostring(effect.ability or ""):lower()==name:lower() then
            if effect.operation=="target" or effect.target then value=tonumber(effect.value or effect.target) or value
            elseif effect.operation=="divide" or effect.divide then
                local divisor=tonumber(effect.value or effect.divide) or 1
                value=value>=0 and math.floor((value+divisor-1)/divisor) or math.ceil(value/divisor)
            else value=value+(tonumber(effect.value or effect.bonus) or 0) end
        end
    end
    return math.max(0,value)
end

function Inventory.consume_blessing(state,name)
    for key,value in pairs(state.blessings) do if key:lower():find(name:lower(),1,true) then
        if type(value)~="table" or not value.permanent then state.blessings[key]=nil end
        return true
    end end
    return false
end

function Inventory.afflict(state,kind,node)
    local a=node.attr; local key=kind.."s"; local collection=state[key]
    state.models.afflictions[key]=collection
    local effects={}
    for _,child in ipairs(node.children or {}) do if type(child)=="table" and child.name=="effect" then
        local operation=child.attr.target and "target" or child.attr.divide and "divide" or "add"
        effects[#effects+1]=State.new_effect{kind=child.attr.type or "aura",operation=operation,
            ability=child.attr.ability,value=child.attr.bonus or child.attr.divide or child.attr.target,
            uses=child.attr.uses,text=child.attr.text or child.attr.description}
    end end
    local value=State.new_affliction(kind,{name=a.name or kind,effects=effects,cumulative=a.cumulative=="t"})
    if value.cumulative then
        local existing=collection[value.name]
        if existing and existing.effects then existing={existing} end
        collection[value.name]=existing or {}; table.insert(collection[value.name],value)
    else collection[value.name]=value end
end

function Inventory.bless(state,attributes)
    local name=attributes.blessing; local value={name=name,type=name,bonus=tonumber(attributes.bonus),permanent=attributes.permanent=="t",effects={}}
    for _,ability in ipairs(State.ability_names) do if name and name:lower()==ability:lower() then
        value.type="ability"; value.effects[1]=State.new_effect{kind="aura",ability=ability,operation="add",value=value.bonus or 1}
    end end
    if name and name:lower():find("defen",1,true) then
        value.type="defence"; value.effects[1]=State.new_effect{kind="aura",ability="Defence",operation="add",value=value.bonus or 3}
    end
    state.blessings[name]=value; state.models.afflictions.blessings=state.blessings
    return value
end

function Inventory.has_blessing(state,name)
    for key in pairs(state.blessings) do if key:lower():find(name:lower(),1,true) then return true end end
    return false
end

function Inventory.cache(state,key,attributes,node)
    local cache=state.caches[key]
    if not cache then cache=State.new_cache(); state.caches[key]=cache end
    cache.rules.maximum=tonumber(attributes.max) or cache.rules.maximum
    cache.rules.multiples=tonumber(attributes.multiples) or cache.rules.multiples
    cache.rules.withdraw_charge=tonumber(attributes.withdrawcharge) or cache.rules.withdraw_charge
    cache.rules.item_limit=tonumber(attributes.itemlimit) or cache.rules.item_limit
    if node and not cache.rules._configured then
        for _,child in ipairs(node.children or {}) do if type(child)=="table" then
            if child.name=="include" then cache.rules.include[#cache.rules.include+1]=child.attr
            elseif child.name=="exclude" then cache.rules.exclude[#cache.rules.exclude+1]=child.attr end
        end end
        cache.rules._configured=true
    end
    return cache
end

function Inventory.cache_accepts(cache,item)
    local included=#cache.rules.include==0
    for _,filter in ipairs(cache.rules.include) do if Inventory.matches(item,filter) then included=true end end
    for _,filter in ipairs(cache.rules.exclude) do if Inventory.matches(item,filter) then return false end end
    return included
end

return Inventory

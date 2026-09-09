local State = {}

State.professions = { Priest = true, Mage = true, Rogue = true, Troubadour = true, Warrior = true, Wayfarer = true }
State.ability_names = { "Charisma", "Combat", "Magic", "Sanctity", "Scouting", "Thievery" }

local function empty_models()
    return {
        stats={natural={},modifiers={},derived={}}, equipment={weapon=nil,armour=nil,tools={}},
        afflictions={blessings={},curses={},diseases={},poisons={}},
        fleet={active=nil,ships={},location="*land*",next_id=1}, rules={fixed={},temporary={}}, god_effects={}, next_item_id=1, visits={},
        extra_choices={}, cache_metadata={},
    }
end

function State.new()
    return {
        schema = 2, name = "", profession = "", gender = "m", book = "1", section = "New",
        abilities = {}, stamina = 0, max_stamina = 0, rank = 1, defence = 0, shards = 0,
        ticks = 0, items = {}, codewords = {}, flags = {}, titles = {}, gods = {},
        blessings = {}, curses = {}, diseases = {}, poisons = {}, ships = {}, caches = {}, variables = {}, history = {},
        pending = nil, progress=nil, rng={draws={},cursor=0}, models=empty_models(), hardcore = false,
    }
end

function State.replace(target,source)
    for key in pairs(target) do target[key]=nil end
    for key,value in pairs(State.copy(source)) do target[key]=value end
    return target
end

function State.migrate(s)
    local schema=tonumber(s.schema) or 1
    assert(schema<=2,"unsupported save schema")
    if schema==1 then
        s.schema=2
        s.models=empty_models()
        s.rng={draws={},cursor=0}
        s.progress=nil
    end
    return s
end

function State.new_item(values)
    values=State.copy(values or {}); values.kind=values.kind or values.type or
        (values.weapon and "weapon") or (values.armour and "armour") or (values.tool and "tool") or "item"
    values.name=values.name or "unknown item"; values.quantity=tonumber(values.quantity) or 1
    values.tags=values.tags or {}; values.effects=values.effects or {}; values.equipped=values.equipped==true
    return values
end

function State.new_effect(values)
    values=State.copy(values or {}); values.kind=values.kind or "aura"; values.operation=values.operation or "add"
    values.uses=values.uses and tonumber(values.uses) or nil
    return values
end

function State.new_affliction(kind,values)
    values=State.copy(values or {}); values.kind=kind; values.name=values.name or kind
    values.effects=values.effects or {}; values.cumulative=values.cumulative==true
    return values
end

function State.new_ship(values)
    values=State.copy(values or {}); values.id=values.id or tostring(values.name or "ship")
    values.cargo=values.cargo or {}; values.crew=values.crew or {quality=0}; values.location=values.location or ""
    return values
end

function State.new_cache(values)
    values=State.copy(values or {}); values.items=values.items or {}; values.shards=tonumber(values.shards) or 0
    values.rules=values.rules or {maximum=nil,multiples=nil,withdraw_charge=0,item_limit=nil,include={},exclude={}}
    return values
end

function State.new_extra_choice(values)
    values=State.copy(values or {}); assert(values.key,"extra choice requires key")
    values.destination=values.destination or {book=values.book,section=values.section}
    values.activation=values.activation or {book=values.atbook,section=values.atsection,tag=values.tag}
    return values
end

function State.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}; if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for k, v in pairs(value) do out[State.copy(k, seen)] = State.copy(v, seen) end
    return out
end

function State.validate(s)
    assert(type(s) == "table", "invalid save")
    State.migrate(s)
    assert(s.schema == 2, "unsupported save schema")
    assert(type(s.book) == "string" and type(s.section) == "string", "invalid address")
    assert(type(s.abilities) == "table" and type(s.items) == "table", "invalid character")
    assert(type(s.variables) == "table" and type(s.flags) == "table", "invalid game state")
    assert(type(s.shards) == "number" and type(s.stamina) == "number", "invalid numeric state")
    s.diseases=s.diseases or {}; s.poisons=s.poisons or {}; s.caches=s.caches or {}; s.history=s.history or {}
    s.models=s.models or empty_models(); s.rng=s.rng or {draws={},cursor=0}
    s.models.stats=s.models.stats or {natural={},modifiers={},derived={}}
    s.models.equipment=s.models.equipment or {weapon=nil,armour=nil,tools={}}
    s.models.afflictions=s.models.afflictions or {blessings={},curses={},diseases={},poisons={}}
    s.models.fleet=s.models.fleet or {active=nil,ships={}}
    s.models.fleet.location=s.models.fleet.location or "*land*"; s.models.fleet.next_id=s.models.fleet.next_id or 1
    s.models.rules=s.models.rules or {fixed={},temporary={}}
    s.models.god_effects=s.models.god_effects or {}
    s.models.next_item_id=s.models.next_item_id or 1
    for index,item in ipairs(s.items) do
        if not item.id then item.id="item-"..s.models.next_item_id; s.models.next_item_id=s.models.next_item_id+1 end
        s.items[index]=require("core/inventory").prepare_item(item)
    end
    s.models.visits=s.models.visits or {}; s.models.extra_choices=s.models.extra_choices or {}
    s.models.cache_metadata=s.models.cache_metadata or {}
    s.models.afflictions.blessings=s.blessings; s.models.afflictions.curses=s.curses
    s.models.afflictions.diseases=s.diseases; s.models.afflictions.poisons=s.poisons
    s.models.fleet.ships=s.ships
    for _,name in ipairs(State.ability_names) do
        if s.models.stats.natural[name]==nil then s.models.stats.natural[name]=s.abilities[name] end
    end
    if s.progress then
        s.progress.applied=s.progress.applied or {}; s.progress.completed=s.progress.completed or {}
    end
    return s
end

function State.item_count(s, wanted)
    local count = 0
    for _, item in ipairs(s.items) do if item.name:lower() == wanted:lower() then count = count + (item.quantity or 1) end end
    return count
end

function State.has_item(s, wanted, kind, bonus, tags)
    for _,item in ipairs(s.items) do
        local name_ok=not wanted or wanted=="*" or item.name:lower()==wanted:lower()
        local kind_ok=not kind or item[kind]==true or item.type==kind
        local bonus_ok=not bonus or tonumber(item.bonus)==tonumber(bonus)
        local tags_ok=not tags or tostring(item.tags or ""):find(tags,1,true)~=nil
        if name_ok and kind_ok and bonus_ok and tags_ok then return true,item end
    end
    return false
end

function State.remove_matching_items(s, a, count)
    count=count or math.huge
    local removed={}
    for i=#s.items,1,-1 do
        local item=s.items[i]
        local kind=a.weapon and "weapon" or a.armour and "armour" or a.tool and "tool" or nil
        local match=State.has_item({items={item}},a.item or a.name,kind,a.bonus,a.tags)
        if match and count>0 then
            local take=math.min(item.quantity or 1,count)
            local copy=State.copy(item); copy.quantity=take; table.insert(removed,copy)
            item.quantity=(item.quantity or 1)-take; count=count-take
            if item.quantity<=0 then table.remove(s.items,i) end
        end
    end
    return removed
end

function State.add_item(s, item)
    if not item.id then item=State.copy(item); item.id="item-"..s.models.next_item_id; s.models.next_item_id=s.models.next_item_id+1 end
    item = require("core/inventory").prepare_item(item)
    table.insert(s.items, item)
    if (item.kind=="weapon" and not s.models.equipment.weapon) or
            (item.kind=="armour" and not s.models.equipment.armour) then require("core/inventory").equip(s,item) end
end

function State.remove_item(s, name, count)
    count = count or 1
    for i = #s.items, 1, -1 do
        local item = s.items[i]
        if item.name:lower() == name:lower() then
            local take = math.min(item.quantity or 1, count)
            item.quantity = (item.quantity or 1) - take; count = count - take
            if item.quantity == 0 then table.remove(s.items, i) end
            if count == 0 then return true end
        end
    end
    return false
end

return State

local State = {}

State.professions = { Priest = true, Mage = true, Rogue = true, Troubadour = true, Warrior = true, Wayfarer = true }
State.ability_names = { "Charisma", "Combat", "Magic", "Sanctity", "Scouting", "Thievery" }

function State.new()
    return {
        schema = 1, name = "", profession = "", gender = "m", book = "1", section = "New",
        abilities = {}, stamina = 0, max_stamina = 0, rank = 1, defence = 0, shards = 0,
        ticks = 0, items = {}, codewords = {}, flags = {}, titles = {}, gods = {},
        blessings = {}, curses = {}, diseases = {}, poisons = {}, ships = {}, caches = {}, variables = {}, history = {},
        pending = nil, hardcore = false,
    }
end

function State.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}; if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for k, v in pairs(value) do out[State.copy(k, seen)] = State.copy(v, seen) end
    return out
end

function State.validate(s)
    assert(type(s) == "table" and s.schema == 1, "unsupported save schema")
    assert(type(s.book) == "string" and type(s.section) == "string", "invalid address")
    assert(type(s.abilities) == "table" and type(s.items) == "table", "invalid character")
    assert(type(s.variables) == "table" and type(s.flags) == "table", "invalid game state")
    assert(type(s.shards) == "number" and type(s.stamina) == "number", "invalid numeric state")
    s.diseases=s.diseases or {}; s.poisons=s.poisons or {}; s.caches=s.caches or {}; s.history=s.history or {}
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
    item = State.copy(item); item.name = item.name or "unknown item"; item.quantity = item.quantity or 1
    table.insert(s.items, item)
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

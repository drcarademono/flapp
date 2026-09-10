local XML=require("content/xml")
local Inventory=require("core/inventory")
local State=require("core/state")

local Character={}

local function text(node)
    local out={}; for _,child in ipairs(node.children or {}) do
        if type(child)=="string" then out[#out+1]=child end
    end
    return table.concat(out)
end

function Character.load(catalog,book)
    local path,error_message=catalog:section_path(book,"Adventurers")
    if not path then return nil,error_message end
    local root,parse_error=XML.read(path); if not root then return nil,parse_error end
    local template={abilities={},items={},starting={}}
    for _,container in ipairs(root.children or {}) do if type(container)=="table" then
        if container.name=="abilities" then
            for _,node in ipairs(container.children or {}) do if type(node)=="table" and node.name=="profession" then
                local values={}; for number in text(node):gmatch("%-?%d+") do values[#values+1]=tonumber(number) end
                template.abilities[node.attr.name]=values
            end end
        elseif container.name=="items" then
            for _,node in ipairs(container.children or {}) do if type(node)=="table" then
                template.items[#template.items+1]={name=node.attr.name,kind=node.name,profession=node.attr.profession,
                    bonus=tonumber(node.attr.bonus),weapon=node.name=="weapon",armour=node.name=="armour",tool=node.name=="tool"}
            end end
        elseif container.name=="starting" then
            for _,node in ipairs(container.children or {}) do if type(node)=="table" and node.name=="adventurer" then template.starting[#template.starting+1]=node.attr end end
        elseif container.name=="stamina" then template.stamina=tonumber(container.attr.amount)
        elseif container.name=="rank" then template.rank=tonumber(container.attr.amount)
        elseif container.name=="gold" then template.shards=tonumber(container.attr.amount) end
    end end
    return template
end

function Character.find(template,key)
    key=tostring(key or ""):lower()
    for _,adventurer in ipairs(template.starting) do
        if adventurer.profession:lower()==key or adventurer.name:lower()==key or adventurer.name:lower():match("^"..key.."[%s%-]") then return adventurer end
    end
end

function Character.apply(state,template,adventurer)
    local scores=assert(template.abilities[adventurer.profession],"missing profession template")
    state.name=adventurer.name; state.profession=adventurer.profession; state.gender=(adventurer.gender or "m"):lower()
    for index,name in ipairs(State.ability_names) do state.abilities[name]=scores[index]; state.models.stats.natural[name]=scores[index] end
    state.rank=template.rank or 1; state.max_stamina=template.stamina or 1; state.stamina=state.max_stamina; state.shards=template.shards or 0
    state.items={}; state.models.equipment={weapon=nil,armour=nil,tools={}}
    for _,source in ipairs(template.items) do if not source.profession or source.profession==state.profession then
        local item=Inventory.prepare_item(source); item.id="starting-"..tostring(#state.items+1); state.items[#state.items+1]=item
        if item.kind=="weapon" or item.kind=="armour" then Inventory.equip(state,item) end
    end end
    local armour=0; for _,item in ipairs(state.items) do if item.equipped and item.kind=="armour" then armour=tonumber(item.bonus) or 0 end end
    state.defence=(state.abilities.Combat or 0)+state.rank+armour
    return state
end

return Character

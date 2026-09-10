local State=require("core/state")
local Ships={}
local capacities={barque=1,brigantine=2,brig=2,galleon=3,gall=3}
local crews={poor=0,average=1,good=2,excellent=3}

function Ships.type(name)
    name=tostring(name or "barque"):lower()
    if name:match("^brig") then return "brigantine" end
    if name:match("^gall") then return "galleon" end
    return "barque"
end

function Ships.crew(value)
    if tonumber(value) then return tonumber(value) end
    return crews[tostring(value or "poor"):lower()] or 0
end

function Ships.new(state,attributes)
    state.ships=state.models.fleet.ships
    local kind=Ships.type(attributes.ship or attributes.type)
    local ship=State.new_ship{type=kind,name=attributes.name or ("New "..kind),capacity=capacities[kind],
        crew={quality=Ships.crew(attributes.initialcrew or attributes.crew)},cargo={},docked=attributes.dock or state.models.fleet.location}
    ship.id="ship-"..tostring(state.models.fleet.next_id or 1); state.models.fleet.next_id=(state.models.fleet.next_id or 1)+1
    table.insert(state.models.fleet.ships,ship); state.models.fleet.active=#state.models.fleet.ships
    return ship
end

function Ships.active(state)
    local fleet=state.models.fleet
    return fleet.active and fleet.ships[fleet.active] or nil
end

function Ships.here(state,ship)
    return ship and ship.docked==state.models.fleet.location
end

function Ships.find(state,kind,here)
    kind=kind and Ships.type(kind); local out={}
    for index,ship in ipairs(state.models.fleet.ships) do
        if (not kind or ship.type==kind) and (not here or Ships.here(state,ship)) then out[#out+1]=index end
    end
    return out
end

function Ships.remove(state,kind)
    local matches=Ships.find(state,kind,true); local index=matches[1]
    if not index then return false end
    table.remove(state.models.fleet.ships,index)
    state.models.fleet.active=#state.models.fleet.ships>0 and math.min(index,#state.models.fleet.ships) or nil
    return true
end

function Ships.free_space(ship) return math.max(0,(ship.capacity or 0)-#(ship.cargo or {})) end

function Ships.add_cargo(ship,cargo,quantity)
    quantity=tonumber(quantity) or 1
    if not ship or Ships.free_space(ship)<quantity then return false end
    for _=1,quantity do ship.cargo[#ship.cargo+1]=cargo end
    return true
end

function Ships.remove_cargo(ship,cargo,quantity)
    quantity=tonumber(quantity) or 1; local removed=0
    for index=#(ship and ship.cargo or {}),1,-1 do
        if cargo=="*" or ship.cargo[index]:lower():match("^"..cargo:lower()) then table.remove(ship.cargo,index); removed=removed+1 end
        if removed>=quantity and cargo~="*" then break end
    end
    return removed>0
end

function Ships.set_location(state,location)
    state.models.fleet.location=location
    local ship=Ships.active(state); if ship then ship.docked=location end
end

function Ships.adjust_crew(ship,amount)
    if not ship then return false end
    ship.crew.quality=math.max(0,math.min(3,(ship.crew.quality or 0)+(tonumber(amount) or 0))); return true
end

return Ships

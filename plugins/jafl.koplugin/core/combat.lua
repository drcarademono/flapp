local Combat={}

local function truth(value,default)
    if value==nil then return default end
    value=tostring(value):lower(); return value=="t" or value=="true" or value=="1"
end

function Combat.start(game,node,opponents)
    local list={}
    for _,enemy in ipairs(opponents or {node}) do
        local a=enemy.attr
        list[#list+1]={path=enemy._path,name=a.name or "Enemy",combat=game:value(a.combat or a.attack or 0),
            defence=game:value(a.defence or 0),stamina=game:value(a.stamina or a.endurance or 1),
            flee=math.max(0,game:value(a.flee or 0)),attacks=tonumber(a.attacks) or 1,
            attackdice=tonumber(a.attackdice) or 2,playerdefence=a.playerdefence,
            abilitydamaged=a.abilitydamaged,staminalost=a.staminalost,predamage=game:value(a.predamage or 0),
            playerfirst=truth(a.playerfirst,true),modifiers=a.modifiers}
    end
    game.state.combat={schema=1,owner=node._path,group=node.attr.group,active=1,round=0,opponents=list,log={}}
    for _,enemy in ipairs(list) do if enemy.predamage>0 then
        local loss=math.min(enemy.predamage,enemy.stamina); enemy.stamina=enemy.stamina-loss; enemy.predamage_applied=true
        game.state.combat.log[#game.state.combat.log+1]=string.format("Before combat, %s takes %d damage.",enemy.name,loss)
        if enemy.staminalost then game.state.variables[enemy.staminalost]=(game.state.variables[enemy.staminalost] or 0)+loss end
    end end
    return game.state.combat
end

function Combat.current(state) return state.combat and state.combat.opponents[state.combat.active] end

local function damage(roll,defence) return math.max(0,roll-defence) end

function Combat.enemy_turn(game,enemy,hook)
    local inventory=require("core/inventory"); local defence_blessing=inventory.has_blessing(game.state,"defen")
    local defence=enemy.playerdefence and game:value(enemy.playerdefence) or game:ability("Defence")
    if tostring(enemy.modifiers or ""):lower():find("noarmour",1,true) then
        for _,item in ipairs(game.state.items) do if item.equipped and item.kind=="armour" then defence=defence-(tonumber(item.bonus) or 0) end end
    end
    for attack=1,enemy.attacks do
        if game.state.stamina<=0 then break end
        local roll=game:roll(6)+game:roll(6)+enemy.combat; local loss=damage(roll,defence)
        if defence_blessing then inventory.consume_blessing(game.state,"defen"); defence_blessing=false end
        if loss>0 then
            if inventory.consume_blessing(game.state,"injury") then loss=0 end
            local replaced=hook and hook("damage",enemy.path,loss)
            if replaced then
                -- The hook owns the damage mutation.
            elseif enemy.abilitydamaged and enemy.abilitydamaged:lower()~="stamina" then
                local name=enemy.abilitydamaged:gsub("^%l",string.upper)
                game.state.abilities[name]=math.max(0,(game.state.abilities[name] or 0)-loss)
            else game.state.stamina=math.max(0,game.state.stamina-loss) end
        end
        game.state.combat.log[#game.state.combat.log+1]=string.format("%s rolls %d against Defence %d: %s.",enemy.name,roll,defence,loss>0 and loss.." damage" or "miss")
    end
end

function Combat.stalemate(game)
    local enemy=Combat.current(game.state); if not enemy then return false end
    local cannot_win=game:ability("Combat")+enemy.attackdice*6<=enemy.defence
    local defence=enemy.playerdefence and game:value(enemy.playerdefence) or game:ability("Defence")
    local cannot_lose=enemy.combat+12<=defence
    return cannot_win and cannot_lose
end

function Combat.attack(game,hook)
    local combat=game.state.combat; local enemy=Combat.current(game.state)
    if not enemy then return "won" end
    while enemy and enemy.stamina<=enemy.flee do
        if hook and enemy.flee>0 then hook("flee",enemy.path,0) end
        combat.active=combat.active+1; combat.round=0; enemy=Combat.current(game.state)
    end
    if not enemy then return "won" end
    combat.round=combat.round+1
    if not enemy.opened and not enemy.playerfirst then Combat.enemy_turn(game,enemy,hook) end
    enemy.opened=true
    if game.state.stamina<=0 then return "lost" end
    local roll=game:ability("Combat"); for _=1,enemy.attackdice do roll=roll+game:roll(6) end
    local loss=damage(roll,enemy.defence); enemy.stamina=math.max(0,enemy.stamina-loss)
    if enemy.staminalost and loss>0 then game.state.variables[enemy.staminalost]=(game.state.variables[enemy.staminalost] or 0)+loss end
    combat.log[#combat.log+1]=string.format("You roll %d against %s's Defence %d: %s. (%d Stamina left)",roll,enemy.name,enemy.defence,loss>0 and loss.." damage" or "miss",enemy.stamina)
    if enemy.stamina<=enemy.flee then
        if hook and enemy.flee>0 then hook("flee",enemy.path,0) end
        combat.active=combat.active+1
        combat.round=0
        if not Combat.current(game.state) then return "won" end
        return "ongoing"
    end
    if hook then hook("round",enemy.path,combat.round) end
    Combat.enemy_turn(game,enemy,hook)
    return game.state.stamina<=0 and "lost" or "ongoing"
end

function Combat.flee(game,hook)
    game.state.combat=nil; return "fled"
end

return Combat

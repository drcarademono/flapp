local XML = require("content/xml")
local State = require("core/state")

local Game = {}; Game.__index = Game
local function truth(v, default)
    if v == nil then return default end
    v = tostring(v):lower(); return v == "t" or v == "true" or v == "yes" or v == "1"
end
local function words(value)
    local out = {}; for word in tostring(value or ""):gmatch("[^,|&]+") do out[#out+1] = word:match("^%s*(.-)%s*$") end
    return out
end
local function plain(node)
    if type(node) == "string" then return node:gsub("%s+", " ") end
    local out = {}; for _, child in ipairs(node.children or {}) do out[#out+1] = plain(child) end
    return table.concat(out):gsub("%s+", " "):match("^%s*(.-)%s*$")
end
local function item_from(a)
    return { name=a.name or "item", quantity=tonumber(a.quantity or a.multiple) or 1, bonus=tonumber(a.bonus),
        type=a.type, tags=a.tags, weapon=a.weapon, armour=a.armour }
end

function Game.new(catalog, state, random)
    return setmetatable({ catalog=catalog, state=state or State.new(), random=random or math.random,
        text={}, actions={}, errors={}, steps=0 }, Game)
end

function Game:value(v)
    if v == nil then return 0 end
    if type(v) == "number" then return v end
    local n = tonumber(v); if n then return n end
    local sign, key = v:match("^([+-]?)([%w_*.-]+)$")
    if key then
        n = self.state.variables[key]
        if n == nil then n = self.state.abilities[key:gsub("^%l", string.upper)] end
        n = n or 0
        return sign == "-" and -n or n
    end
    local dice, sides, add = v:match("^(%d+)[dD](%d+)([+-]?%d*)$")
    if dice then
        local total = tonumber(add) or 0
        for _=1,tonumber(dice) do total = total + self.random(tonumber(sides)) end
        return total
    end
    return 0
end

function Game:condition(a)
    local s, ok = self.state, true
    if a.codeword then
        ok = a.codeword:find("&",1,true) and true or false
        for _,w in ipairs(words(a.codeword)) do if ok then ok = s.codewords[w] == true else ok = ok or s.codewords[w] == true end end
    end
    if ok and a.title then ok=false; for _,v in ipairs(words(a.title)) do ok=ok or s.titles[v] end end
    if ok and a.god then ok = s.gods[a.god] == true end
    if ok and a.profession then ok = s.profession:lower() == a.profession:lower() end
    if ok and a.gender then ok = s.gender:sub(1,1):lower() == a.gender:sub(1,1):lower() end
    if ok and a.item then ok = State.item_count(s, a.item) >= (tonumber(a.multiple) or 1) end
    if ok and a.shards then ok = s.shards >= self:value(a.shards) end
    if ok and a.ticks then ok = s.ticks >= self:value(a.ticks) end
    if ok and a.var then
        local value = s.variables[a.var]
        if a.greaterthan then ok = value ~= nil and value > self:value(a.greaterthan)
        elseif a.lessthan then ok = value ~= nil and value < self:value(a.lessthan)
        elseif a.equals then ok = value ~= nil and value == self:value(a.equals)
        else ok = value ~= nil end
    end
    if ok and a.emptyvar then ok = s.variables[a.emptyvar] == nil end
    if ok and a.flag then ok = s.flags[a.flag] == true end
    if ok and a.dead then ok = (s.stamina <= 0) == truth(a.dead, false) end
    return truth(a["not"], false) and not ok or ok
end

function Game:mutate(name, a, direction)
    local s = self.state
    if a.staminato then
        s.stamina=math.max(0,math.min(s.max_stamina,self:value(a.staminato)))
        return
    end
    if (a.shards=="*" or a.gold=="*") and direction<0 then
        s.shards=0
        return
    end
    local amount = self:value(a.amount or a.value or 1) * direction
    local ability = a.ability and a.ability:gsub("^%l", string.upper)
    if ability == "Stamina" then s.stamina = math.max(0, math.min(s.max_stamina, s.stamina + amount))
    elseif ability == "Rank" then s.rank = math.max(0, s.rank + amount)
    elseif ability then s.abilities[ability] = math.max(0, math.min(12, (s.abilities[ability] or 0) + amount))
    elseif a.shards or a.gold or name == "adjustmoney" then s.shards = math.max(0, s.shards + self:value(a.shards or a.gold or a.amount) * direction)
    elseif a.codeword then for _,v in ipairs(words(a.codeword)) do s.codewords[v] = direction > 0 or nil end
    elseif a.title then for _,v in ipairs(words(a.title)) do s.titles[v] = direction > 0 or nil end
    elseif a.god then s.gods[a.god] = direction > 0 or nil
    elseif a.flag then s.flags[a.flag] = direction > 0 or nil
    elseif a.item or a.name then if direction > 0 then State.add_item(s,item_from(a)) else State.remove_item(s,a.item or a.name,self:value(a.multiple or 1)) end
    end
end

function Game:add_action(label, kind, data)
    local action = { label=label, kind=kind, data=data }
    self.actions[#self.actions+1] = action
    return action
end

-- The desktop engine's ExecutableRunner stops at blocking actions (fights,
-- forced gotos, and checks), then resumes at the following XML node.  A Lua
-- coroutine gives us the same ordered execution without displaying or applying
-- content which belongs after the unresolved action.
function Game:pause_section()
    local running=coroutine.running()
    -- KOReader uses LuaJIT, whose optional second coroutine.running() result is
    -- not portable across its Lua 5.1/5.2 compatibility configurations.  The
    -- runner identity is unambiguous and works in every supported build.
    if running and running==self.section_runner then coroutine.yield() end
end

function Game:resume_section()
    if not self.section_runner or coroutine.status(self.section_runner)=="dead" then return true end
    local ok,err=coroutine.resume(self.section_runner)
    if not ok then error(err) end
    return coroutine.status(self.section_runner)=="dead"
end

local function ability_key(name)
    return name and name:gsub("^%l", string.upper)
end

local function roll_dice(game, count)
    local total = 0
    for _=1,count do total = total + game.random(6) end
    return total
end

-- FightNode.java does not use a fixed weapon/enemy damage value.  A successful
-- attack deals the entire amount by which (dice + COMBAT) beats Defence.
local function combat_damage(roll, defence)
    return math.max(0, roll - defence)
end

function Game:check_adjustment(node)
    local adjustment = 0
    for _, child in ipairs(node.children or {}) do
        if type(child) == "table" and child.name == "adjust" and self:condition(child.attr) then
            adjustment = adjustment + self:value(child.attr.amount or child.attr.value)
        end
    end
    return adjustment
end

function Game:add_check(node)
    local a = node.attr
    if a.flag and not self.state.flags[a.flag] then return end

    local label = plain(node)
    if label == "" then
        if node.name == "rankcheck" then
            local dice = tonumber(a.dice) or 1
            label = "Roll "..dice..(dice == 1 and " die" or " dice")
        else
            local names = {}
            for _, name in ipairs(words(a.ability)) do names[#names+1] = name:upper() end
            label = "Make a "..table.concat(names, " or ").." roll at Difficulty "..tostring(a.level)
        end
    end

    local check = { node=node, branches={} }
    local abilities = node.name == "difficulty" and words(a.ability) or {}
    if #abilities > 1 then
        for _, ability in ipairs(abilities) do
            local data = check
            data = { node=node, branches=check.branches, ability=ability, group=check }
            self:add_action(label.." ("..ability:upper()..")", "skillcheck", data)
        end
    else
        self:add_action(label, "skillcheck", check)
    end
    self.pending_checks[#self.pending_checks+1] = check
    if a.var then self.checks_by_var[a.var] = check end
end

function Game:attach_check_branch(node)
    local check = node.attr.var and self.checks_by_var[node.attr.var]
        or self.pending_checks[#self.pending_checks]
    if check then check.branches[#check.branches+1] = node end
end

function Game:walk(node, enabled)
    self.steps=self.steps+1; if self.steps > 10000 then error("section execution limit exceeded") end
    if type(node)=="string" then if enabled and node:match("%S") then self.text[#self.text+1]=node:gsub("%s+"," ") end return end
    local n,a=node.name,node.attr
    if n=="if" or n=="elseif" then enabled=enabled and self:condition(a)
    elseif n=="else" then enabled=enabled -- grouped else parity is handled by authored mutually-exclusive blocks where possible
    end
    if not enabled then return end
    if n=="choice" then
        local alive_for_destination=(self.state.stamina>0)==truth(a.dead,false)
        if self:condition(a) and alive_for_destination and
                (not a.book or self.catalog.books[a.book] and self.catalog.books[a.book].installed) then
            self:add_action(plain(node),"goto",a)
        end
        return
    elseif n=="goto" then
        -- GotoNode.canUse() defaults dead to false: ordinary destinations are
        -- unavailable while dead, while dead="t" destinations are death-only.
        local alive_for_destination=(self.state.stamina>0)==truth(a.dead,false)
        if self:condition(a) and alive_for_destination then
            self:add_action(plain(node) ~= "" and plain(node) or ("Turn to "..tostring(a.section)),"goto",a)
            if truth(a.force,true) then self:pause_section() end
        end
        return
    elseif n=="set" then self.state.variables[a.name or a.var]=self:value(a.value or a.amount)
    elseif n=="tick" then self.state.ticks=self.state.ticks+self:value(a.count or a.amount or 1); self:mutate(n,a,1)
    elseif n=="gain" then self:mutate(n,a,1)
    elseif n=="lose" then self:mutate(n,a,-1)
    elseif n=="adjust" or n=="adjustmoney" then self:mutate(n,a,1)
    elseif n=="rest" then self.state.stamina=math.min(self.state.max_stamina,self.state.stamina+self:value(a.stamina or 0)); self.state.shards=math.max(0,self.state.shards-self:value(a.shards or 0))
    elseif n=="random" then
        local candidates={}; for _,c in ipairs(node.children) do if type(c)=="table" and c.name=="outcome" then candidates[#candidates+1]=c end end
        if #candidates>0 then self:walk(candidates[self.random(#candidates)],true) end; return
    elseif n=="difficulty" or n=="rankcheck" then
        self:add_check(node)
        return
    elseif (n=="success" or n=="failure") and not self.resolving_check then
        self:attach_check_branch(node)
        return
    elseif (n=="success" or n=="failure") and a.section then
        local fallback=(n=="success" and "Successful roll" or "Failed roll")
        self:add_action(plain(node)~="" and plain(node) or fallback,"goto",a)
        return
    elseif n=="outcomes" then
        for _,c in ipairs(node.children or {}) do
            if type(c)=="table" and (c.name=="success" or c.name=="failure") then self:attach_check_branch(c) end
        end
        return
    elseif n=="fight" then
        self:add_action("Fight "..(a.name or "enemy"),"fight",node)
        self:pause_section()
        return
    elseif n=="market" or n=="trade" then self:add_action(plain(node)~="" and plain(node) or "Open market","market",node); return
    elseif n=="buy" or n=="sell" then
        local cost=self:value(a.price or a.shards or a.amount or 0)
        local label=(n=="buy" and "Buy " or "Sell ")..(a.name or a.item or plain(node)).." ("..cost.." shards)"
        self:add_action(label,n,{attr=a,node=node,cost=cost}); return
    elseif n=="image" then self.image=self.catalog:asset_path(a.book or self.state.book,a.file or a.name); return
    end
    local branch_taken=false
    local in_chain=false
    for _,child in ipairs(node.children or {}) do
        if type(child)=="table" and child.name=="if" then
            local matched=self:condition(child.attr); branch_taken=matched; in_chain=true
            if matched then self:walk(child,true) end
        elseif type(child)=="table" and child.name=="elseif" and in_chain then
            local matched=not branch_taken and self:condition(child.attr); branch_taken=branch_taken or matched
            if matched then self:walk(child,true) end
        elseif type(child)=="table" and child.name=="else" and in_chain then
            if not branch_taken then self:walk(child,true) end
            in_chain=false; branch_taken=false
        else
            in_chain=false; branch_taken=false; self:walk(child,enabled)
        end
    end
    if n=="p" or n=="header" or n:match("^h%d$") then self.text[#self.text+1]="\n\n" end
end

function Game:load(book, section)
    local path,err=self.catalog:section_path(book,section); if not path then return nil,err end
    local root,xerr=XML.read(path); if not root then return nil,xerr end
    self.state.book,self.state.section=tostring(book),tostring(section); self.text={}; self.actions={}; self.steps=0; self.image=nil
    self.pending_checks={}; self.checks_by_var={}
    self.section_runner=coroutine.create(function() self:walk(root,true) end)
    local ok,msg=pcall(function() self:resume_section() end); if not ok then return nil,msg end
    self.state.pending={kind="section",book=self.state.book,section=self.state.section}
    return { title=(self.catalog.books[self.state.book].title or "").." — "..self.state.section,
        text=table.concat(self.text):gsub("[ \t]+\n","\n"):match("^%s*(.-)%s*$"), actions=self.actions, image=self.image }
end

function Game:choose(index)
    local action=self.actions[index]; if not action then return nil,"Invalid choice" end
    if action.kind=="skillcheck" then
        local node,a=action.data.node,action.data.node.attr
        local adjustment=self:check_adjustment(node)
        local roll,score,success,description
        if node.name=="rankcheck" then
            local dice=tonumber(a.dice) or 1
            roll=self:value(a.add or 0)+adjustment
            for _=1,dice do roll=roll+self.random(6) end
            score=self.state.rank
            success=roll<=score
            description=string.format("Rank check: rolled %d against Rank %d — %s.",roll,score,success and "success" or "failure")
            self.state.variables["*ability*"]="Rank"
        else
            local chosen=action.data.ability or words(a.ability)[1]
            score=(self.state.abilities[ability_key(chosen)] or 0)+adjustment
            roll=self.random(6)+self.random(6)+score
            success=roll>self:value(a.level)
            description=string.format("%s check: rolled %d against Difficulty %d — %s.",
                ability_key(chosen),roll,self:value(a.level),success and "success" or "failure")
            self.state.variables["*ability*"]=ability_key(chosen)
        end
        local result = node.name=="rankcheck" and (score-roll+1) or (roll-self:value(a.level))
        self.state.variables[a.var or "*difficulty*"]=result
        if a.flag then self.state.flags[a.flag]=nil end
        self.text[#self.text+1]="\n\n"..description
        local remaining={}
        if not truth(a.force,true) then
            local group=action.data.group or action.data
            for _,candidate in ipairs(self.actions) do
                if (candidate.data.group or candidate.data)~=group then remaining[#remaining+1]=candidate end
            end
        end
        self.actions=remaining
        self.resolving_check=true
        for _,branch in ipairs(action.data.branches) do
            if (branch.name=="success") == success then self:walk(branch,true) end
        end
        self.resolving_check=false
        return {title="Check result",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="goto" then
        local a=action.data
        if truth(a.pay,a.shards~=nil) then self.state.shards=math.max(0,self.state.shards-self:value(a.shards or 0)); if a.item then State.remove_item(self.state,a.item,1) end end
        if a.sail then self.state.at_sea=true end
        local starters={Liana={"Wayfarer",2,5,2,3,6,4},Andriel={"Warrior",3,6,2,4,3,2},
            Chalor={"Mage",2,2,6,1,5,3},Marana={"Rogue",5,4,4,1,2,6},
            Ignatius={"Priest",4,2,3,6,4,2},Astariel={"Troubadour",6,3,4,3,2,4}}
        if starters[a.section] and self.state.profession=="" then
            local p=starters[a.section]; self.state.profession=p[1]; self.state.name=a.section
            for i,n in ipairs(State.ability_names) do self.state.abilities[n]=p[i+1] end
            self.state.rank=1; self.state.max_stamina=9; self.state.stamina=9; self.state.shards=16
            self.state.defence=(self.state.abilities.Combat or 0)+self.state.rank+1
            State.add_item(self.state,{name="leather jerkin",armour=true,bonus=1})
            local weapons={Priest="mace",Mage="staff",Rogue="sword",Troubadour="sword",Warrior="battle-axe",Wayfarer="spear"}
            State.add_item(self.state,{name=weapons[p[1]],weapon=true}); State.add_item(self.state,{name="map"})
        end
        return self:load(a.book or self.state.book,a.section)
    elseif action.kind=="fight" then
        local a=action.data.attr
        local enemy_stamina=self:value(a.stamina or a.endurance or 1)
        local enemy_defence=self:value(a.defence or 0)
        local enemy_combat=self:value(a.combat or a.attack or 0)
        local flee_at=math.max(0,self:value(a.flee or 0))
        -- XML.parse normalizes every attribute name to lower case.
        local player_defence=a.playerdefence and self:value(a.playerdefence) or self.state.defence
        local attack_dice=tonumber(a.attackdice) or 2
        local enemy_attacks=tonumber(a.attacks) or 1
        local player_first=truth(a.playerfirst,true)
        local rounds,log=0,{}

        local pre_damage=a.predamage and self:value(a.predamage) or 0
        if pre_damage>0 then
            local dealt=math.min(pre_damage,enemy_stamina)
            enemy_stamina=enemy_stamina-dealt
            log[#log+1]=string.format("Before combat, %s takes %d damage.",a.name or "the enemy",dealt)
            if a.staminalost then self.state.variables[a.staminalost]=(self.state.variables[a.staminalost] or 0)+dealt end
        end

        local function enemy_turn()
            for attack_number=1,enemy_attacks do
                if self.state.stamina<=0 then break end
                local roll=roll_dice(self,2)+enemy_combat
                local damage=combat_damage(roll,player_defence)
                if damage>0 then
                    if a.abilitydamaged and a.abilitydamaged:lower()~="stamina" then
                        local ability=ability_key(a.abilitydamaged)
                        self.state.abilities[ability]=math.max(0,(self.state.abilities[ability] or 0)-damage)
                    else
                        self.state.stamina=math.max(0,self.state.stamina-damage)
                    end
                end
                local suffix=enemy_attacks>1 and string.format(" (attack %d)",attack_number) or ""
                log[#log+1]=string.format("%s rolls %d against Defence %d%s: %s.",a.name or "Enemy",roll,
                    player_defence,suffix,damage>0 and (damage.." damage") or "miss")
            end
        end

        while enemy_stamina>flee_at and self.state.stamina>0 and rounds<100 do
            rounds=rounds+1
            if not player_first then enemy_turn(); player_first=true end
            if self.state.stamina<=0 then break end
            local roll=roll_dice(self,attack_dice)+(self.state.abilities.Combat or 0)
            local damage=combat_damage(roll,enemy_defence)
            enemy_stamina=math.max(0,enemy_stamina-damage)
            if a.staminalost and damage>0 then self.state.variables[a.staminalost]=(self.state.variables[a.staminalost] or 0)+damage end
            log[#log+1]=string.format("You roll %d against %s's Defence %d: %s. (%d Stamina left)",roll,
                a.name or "the enemy",enemy_defence,damage>0 and (damage.." damage") or "miss",enemy_stamina)
            if enemy_stamina>flee_at then enemy_turn() end
        end

        local won=enemy_stamina<=flee_at and self.state.stamina>0
        self.text[#self.text+1]="\n\n"..table.concat(log,"\n").."\n\n"..(won and "You win the fight." or "You have been defeated.")

        self.actions={}
        -- Just like ExecutableRunner.continueExecution(), resume after the fight.
        -- This evaluates dead= conditions and applies effects in their authored
        -- order, stopping at the first usable forced goto.
        self:resume_section()
        return {title="Combat result",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="market" then
        self.actions={}; self.text={"Choose a transaction."}
        for _,child in ipairs(action.data.children) do self:walk(child,true) end
        return {title="Market",text=table.concat(self.text),actions=self.actions}
    elseif action.kind=="buy" or action.kind=="sell" then
        local a,cost=action.data.attr,action.data.cost
        local name=a.name or a.item or "item"
        if action.kind=="buy" then
            if self.state.shards<cost then return nil,"You cannot afford that." end
            self.state.shards=self.state.shards-cost; State.add_item(self.state,item_from(a))
        else
            if not State.remove_item(self.state,name,1) then return nil,"You do not have that item." end
            self.state.shards=self.state.shards+cost
        end
        self.text={action.kind=="buy" and ("Bought "..name..".") or ("Sold "..name..".")}; self.actions={}
        for _,child in ipairs(action.data.node.children) do self:walk(child,true) end
        return {title="Market",text=table.concat(self.text),actions=self.actions}
    end
    return nil,"Unsupported interaction: "..tostring(action.kind)
end

return Game

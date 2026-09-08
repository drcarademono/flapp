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
    if ok and a.weapon then ok = State.has_item(s,a.weapon=="*" and nil or a.weapon,"weapon",a.bonus,a.tags) end
    if ok and a.armour then ok = State.has_item(s,a.armour=="*" and nil or a.armour,"armour",a.bonus,a.tags) end
    if ok and a.tool then ok = State.has_item(s,a.tool=="*" and nil or a.tool,"tool",a.bonus,a.tags) end
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
    if ok and a.blessing then ok = s.blessings[a.blessing] ~= nil end
    if ok and a.curse then ok = s.curses[a.curse] ~= nil end
    if ok and a.disease then ok = s.diseases and s.diseases[a.disease] ~= nil end
    if ok and a.poison then ok = s.poisons and s.poisons[a.poison] ~= nil end
    if ok and a.resurrection then ok = s.resurrection ~= nil end
    if ok and a.book then ok = self.catalog.books[tostring(a.book)] and self.catalog.books[tostring(a.book)].installed end
    if ok and a.ability then
        local score=s.abilities[a.ability:gsub("^%l", string.upper)] or 0
        if a.greaterthan then ok=score>self:value(a.greaterthan)
        elseif a.lessthan then ok=score<self:value(a.lessthan)
        elseif a.equals then ok=score==self:value(a.equals) end
    end
    if ok and a.dead then ok = (s.stamina <= 0) == truth(a.dead, false) end
    return truth(a["not"], false) and not ok or ok
end

local function destination_matches_life_state(state, attributes)
    -- GotoNode.canUse(): an omitted dead attribute means "only while alive".
    -- Java has no active Adventurer while the profession is being selected, so
    -- the zeroed character-creation template must not count as a dead player.
    local is_dead=state.profession~="" and state.stamina<=0
    return is_dead==truth(attributes.dead,false)
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
    if direction<0 and (a.item=="*" or a.weapon=="*" or a.armour=="*" or a.tool=="*") then
        State.remove_matching_items(s,a)
        return
    end
    local amount = self:value(a.amount or a.value or a.stamina or 1) * direction
    local ability = a.ability and a.ability:gsub("^%l", string.upper)
    if ability == "Stamina" then s.stamina = math.max(0, math.min(s.max_stamina, s.stamina + amount))
    elseif ability == "Rank" then
        s.rank = math.max(0, s.rank + amount)
        s.max_stamina=math.max(1,s.max_stamina+amount); s.stamina=math.min(s.stamina,s.max_stamina)
    elseif ability then s.abilities[ability] = math.max(0, math.min(12, (s.abilities[ability] or 0) + amount))
    elseif a.shards or a.gold or name == "adjustmoney" then s.shards = math.max(0, s.shards + self:value(a.shards or a.gold or a.amount) * direction)
    elseif a.codeword then for _,v in ipairs(words(a.codeword)) do s.codewords[v] = direction > 0 or nil end
    elseif a.title then for _,v in ipairs(words(a.title)) do s.titles[v] = direction > 0 or nil end
    elseif a.god then s.gods[a.god] = direction > 0 or nil
    elseif a.flag then s.flags[a.flag] = direction > 0 or nil
    elseif a.blessing then s.blessings[a.blessing]=direction>0 and (tonumber(a.bonus) or true) or nil
    elseif a.curse then s.curses[a.curse]=direction>0 and true or nil
    elseif a.disease then s.diseases=s.diseases or {}; s.diseases[a.disease]=direction>0 and true or nil
    elseif a.poison then s.poisons=s.poisons or {}; s.poisons[a.poison]=direction>0 and true or nil
    elseif a.resurrection then s.resurrection=direction>0 and State.copy(a) or nil
    elseif a.item or a.name or a.weapon or a.armour or a.tool then
        local itemname=a.item or a.name or a.weapon or a.armour or a.tool
        if direction > 0 then
            local item=item_from(a); item.name=itemname
            item.weapon=a.weapon~=nil or item.weapon; item.armour=a.armour~=nil or item.armour; item.tool=a.tool~=nil
            State.add_item(s,item)
        else State.remove_matching_items(s,a,self:value(a.multiple or 1)) end
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

local function range_matches(spec, value)
    if not spec then return true end
    local lo,hi=spec:match("^(%-?%d+)%-(%-?%d+)$")
    if lo then return value>=tonumber(lo) and value<=tonumber(hi) end
    lo,hi=spec:match("^(%-?%d+),(%-?%d+)$")
    if lo then return value==tonumber(lo) or value==tonumber(hi) end
    lo=spec:match("^(%-?%d+)%+$")
    if lo then return value>=tonumber(lo) end
    return value==tonumber(spec)
end

local function pair_fight_nodes(root)
    local fights,damage,rounds,flees={},{},{},{}
    local function visit(node)
        if type(node)~="table" then return end
        if node.name=="fight" then fights[#fights+1]=node
        elseif node.name=="fightdamage" then damage[#damage+1]=node
        elseif node.name=="fightround" then rounds[#rounds+1]=node
        elseif node.name=="flee" then flees[#flees+1]=node end
        for _,child in ipairs(node.children or {}) do visit(child) end
    end
    visit(root)
    for i,fight in ipairs(fights) do
        fight.fightdamage=damage[i]; fight.fightround=rounds[i]; fight.flee_node=flees[i]
    end
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

function Game:open_market(node, message)
    self.actions={}; self.text={message or "Choose a transaction."}
    -- MarketNode.execute() is non-blocking in Java.  KOReader presents the
    -- market as its own screen, so this explicit first action is the equivalent
    -- of continuing to the next executable without making a transaction.
    self:add_action("Leave market","leave_market",{market=node})
    local function visit(parent)
        for _,child in ipairs(parent.children or {}) do
            if type(child)=="table" then
                local a=child.attr
                if child.name=="item" or child.name=="weapon" or child.name=="armour" or child.name=="tool" then
                    if child.name~="item" then a[child.name]=true end
                    if a.buy then
                        self:add_action("Buy "..(a.name or "item").." ("..self:value(a.buy).." shards)","buy",
                            {attr=a,node=child,cost=self:value(a.buy),market=node})
                    end
                    if a.sell then
                        self:add_action("Sell "..(a.name or "item").." ("..self:value(a.sell).." shards)","sell",
                            {attr=a,node=child,cost=self:value(a.sell),market=node})
                    end
                elseif child.name=="buy" or child.name=="sell" then
                    local cost=self:value(a.price or a.shards or a.amount or 0)
                    self:add_action((child.name=="buy" and "Buy " or "Sell ")..(a.name or a.item or plain(child))..
                        " ("..cost.." shards)",child.name,{attr=a,node=child,cost=cost,market=node})
                else visit(child) end
            end
        end
    end
    visit(node)
end

function Game:apply_affliction(kind, node)
    local a=node.attr; local collection=kind=="curse" and self.state.curses or
        kind=="disease" and self.state.diseases or self.state.poisons
    collection[a.name or kind]=true
    for _,child in ipairs(node.children or {}) do
        if type(child)=="table" and child.name=="effect" and child.attr.ability then
            local names=child.attr.ability=="*" and State.ability_names or {ability_key(child.attr.ability)}
            for _,ability in ipairs(names) do
                if child.attr.target then self.state.abilities[ability]=self:value(child.attr.target)
                else self.state.abilities[ability]=math.max(1,math.min(12,(self.state.abilities[ability] or 0)+self:value(child.attr.bonus or 0))) end
            end
        end
    end
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
        if self:condition(a) and destination_matches_life_state(self.state,a) and
                (not a.book or self.catalog.books[a.book] and self.catalog.books[a.book].installed) then
            self:add_action(plain(node),"goto",a)
        end
        return
    elseif n=="goto" then
        -- GotoNode.canUse() defaults dead to false: ordinary destinations are
        -- unavailable while dead, while dead="t" destinations are death-only.
        if self:condition(a) and destination_matches_life_state(self.state,a) then
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
        if not a.flag or self.state.flags[a.flag] then
            self:add_action(plain(node)~="" and plain(node) or "Roll dice","random",node)
            if truth(a.force,true) then self:pause_section() end
        end
        return
    elseif n=="difficulty" or n=="rankcheck" then
        self:add_check(node)
        if truth(a.force,true) then
            self:pause_section()
            for _,child in ipairs(node.children or {}) do
                if type(child)=="table" and (child.name=="success" or child.name=="failure") then self:walk(child,true) end
            end
        end
        return
    elseif n=="success" or n=="failure" then
        local result=self.state.variables[a.var or "*difficulty*"] or 0
        if (n=="success")~=(result>0) then return end
        if a.section then
            local fallback=(n=="success" and "Successful roll" or "Failed roll")
            self:add_action(plain(node)~="" and plain(node) or fallback,"goto",a)
            self:pause_section()
        else
            for _,child in ipairs(node.children or {}) do self:walk(child,true) end
        end
        return
    elseif n=="outcomes" then
        local has_check_branch=false
        for _,child in ipairs(node.children or {}) do
            if type(child)=="table" and (child.name=="success" or child.name=="failure") then
                has_check_branch=true; break
            end
        end
        local default_var=has_check_branch and "*difficulty*" or "*random*"
        local value=self.state.variables[a.var or default_var]
        if value==nil and not has_check_branch then value=self.last_roll end
        for _,c in ipairs(node.children or {}) do
            if type(c)=="table" then
                local matched=c.name=="outcome" and range_matches(c.attr.range,value) and self:condition(c.attr)
                    or c.name=="success" and value~=nil and value>0
                    or c.name=="failure" and value~=nil and value<=0
                if matched then self:walk(c,true); break end
            end
        end
        return
    elseif n=="outcome" then
        for _,child in ipairs(node.children or {}) do self:walk(child,true) end
        return
    elseif n=="fightdamage" or n=="fightround" or n=="flee" then
        -- Parsed up front and owned by the corresponding fight, as in FightNode.hookupNodes().
        return
    elseif n=="fight" then
        self:add_action("Fight "..(a.name or "enemy"),"fight",node)
        self:pause_section()
        return
    elseif n=="return" then
        if #self.state.history>0 then self:add_action(plain(node)~="" and plain(node) or "Return","return",a) end
        if truth(a.force,true) then self:pause_section() end
        return
    elseif n=="training" then
        self:add_action(plain(node)~="" and plain(node) or ("Train "..tostring(a.ability or "ability")),"training",node)
        self:pause_section(); return
    elseif n=="resurrection" then
        if a.section then self:add_action(plain(node)~="" and plain(node) or "Arrange resurrection","resurrection",a)
        elseif self.state.stamina<=0 and self.state.resurrection then self:add_action(plain(node)~="" and plain(node) or "Use resurrection","resurrect",self.state.resurrection) end
        return
    elseif n=="itemcache" or n=="moneycache" then
        local key=a.name; self.state.caches[key]=self.state.caches[key] or {items={},shards=0}
        self:add_action(a.text or plain(node) or "Open cache","cache",{key=key,node=node}); return
    elseif n=="transfer" then
        local source=a.from and self.state.caches[a.from]
        local target=a.to and a.to~="null" and (self.state.caches[a.to] or {items={},shards=0}) or nil
        if a.to and a.to~="null" then self.state.caches[a.to]=target end
        if source then
            if a.shards=="*" then self.state.shards=self.state.shards+(source.shards or 0); source.shards=0 end
            for _,item in ipairs(source.items or {}) do State.add_item(self.state,item) end; source.items={}
        elseif target then
            if a.shards=="*" then target.shards=(target.shards or 0)+self.state.shards; self.state.shards=0 end
            local moved=State.remove_matching_items(self.state,a,tonumber(a.limit) or math.huge)
            for _,item in ipairs(moved) do table.insert(target.items,item) end
        end
        return
    elseif n=="curse" or n=="disease" or n=="poison" then
        self:apply_affliction(n,node)
    elseif n=="while" then
        local guard=0
        while self.state.variables[a.var] and self.state.variables[a.var]~=0 and guard<100 do
            guard=guard+1
            for _,child in ipairs(node.children or {}) do self:walk(child,true) end
        end
        return
    elseif n=="market" or n=="trade" then
        self:add_action(plain(node)~="" and plain(node) or "Open market","market",node)
        self:pause_section()
        return
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
    pair_fight_nodes(root)
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
        if truth(a.force,true) then self:resume_section() end
        return {title="Check result",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="random" then
        local node,a=action.data,action.data.attr
        local roll=roll_dice(self,tonumber(a.dice) or 2)+self:check_adjustment(node)
        self.last_roll=roll; self.state.variables[a.var or "*random*"]=roll
        if a.flag then self.state.flags[a.flag]=nil end
        self.text[#self.text+1]="\n\nRolled "..tostring(roll).."."
        self.actions={}
        if truth(a.force,true) then self:resume_section() end
        return {title="Roll result",text=table.concat(self.text),actions=self.actions,image=self.image}
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
        table.insert(self.state.history,{book=self.state.book,section=self.state.section})
        return self:load(a.book or self.state.book,a.section)
    elseif action.kind=="return" then
        local destination=table.remove(self.state.history)
        if not destination then return nil,"There is no previous section." end
        return self:load(destination.book,destination.section)
    elseif action.kind=="training" then
        local a=action.data.attr; local ability=ability_key(a.ability)
        local roll=roll_dice(self,tonumber(a.dice) or 2)+self:value(a.add or 0)
        local old_score=ability and self.state.abilities[ability] or 0
        if ability and ability~="?" and roll>(self.state.abilities[ability] or 0) then
            self.state.abilities[ability]=math.min(12,(self.state.abilities[ability] or 0)+1)
        end
        self.state.variables.exp=roll-old_score
        if a.var then self.state.variables[a.var]=roll end
        self.text[#self.text+1]="\n\nTraining roll: "..roll.."."
        self.actions={}; self:resume_section()
        return {title="Training result",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="resurrection" then
        self.state.resurrection=State.copy(action.data)
        self.actions={}; self:resume_section()
        return {title="Resurrection arranged",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="resurrect" then
        local a=action.data; self.state.resurrection=nil
        self.state.stamina=math.max(1,self.state.stamina)
        if a.shards then self.state.shards=math.max(0,self.state.shards-self:value(a.shards)) end
        return self:load(a.book or self.state.book,a.section)
    elseif action.kind=="cache" then
        local cache=self.state.caches[action.data.key]
        local lines={"Stored shards: "..tostring(cache.shards or 0),"Stored items:"}
        for _,item in ipairs(cache.items or {}) do lines[#lines+1]="• "..item.name end
        return {title=action.data.key,text=table.concat(lines,"\n"),actions=self.actions,image=self.image}
    elseif action.kind=="fight" then
        local fight_node=action.data; local a=fight_node.attr
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
                    local replacement=fight_node.fightdamage and fight_node.fightdamage.attr.type and
                        fight_node.fightdamage.attr.type:match("^repl")
                    if replacement then
                        -- Replacement damage nodes own the damage; their common authored form
                        -- removes one randomly selected ability point per successful hit.
                        local abilities=State.ability_names
                        local ability=abilities[self.random(#abilities)]
                        self.state.abilities[ability]=math.max(0,(self.state.abilities[ability] or 0)-1)
                    elseif a.abilitydamaged and a.abilitydamaged:lower()~="stamina" then
                        local ability=ability_key(a.abilitydamaged)
                        self.state.abilities[ability]=math.max(0,(self.state.abilities[ability] or 0)-damage)
                    else
                        self.state.stamina=math.max(0,self.state.stamina-damage)
                    end
                    if fight_node.fightdamage then
                        local function damage_effect(node)
                            if type(node)~="table" then return end
                            if node.name=="tick" then self:mutate("tick",node.attr,1)
                            elseif node.name=="gain" then self:mutate("gain",node.attr,1)
                            elseif node.name=="lose" and not replacement then self:mutate("lose",node.attr,-1) end
                            for _,child in ipairs(node.children or {}) do damage_effect(child) end
                        end
                        damage_effect(fight_node.fightdamage)
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
        self:open_market(action.data)
        return {title="Market",text=table.concat(self.text),actions=self.actions}
    elseif action.kind=="leave_market" then
        self.actions={}
        self:resume_section()
        local book=self.catalog.books[self.state.book]
        return {title=(book and book.title or "").." — "..self.state.section,
            text=table.concat(self.text),actions=self.actions,image=self.image}
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
        local message=action.kind=="buy" and ("Bought "..name..".") or ("Sold "..name..".")
        if action.data.market then self:open_market(action.data.market,message)
        else
            self.text={message}; self.actions={}
            for _,child in ipairs(action.data.node.children) do self:walk(child,true) end
        end
        return {title="Market",text=table.concat(self.text),actions=self.actions}
    end
    return nil,"Unsupported interaction: "..tostring(action.kind)
end

return Game

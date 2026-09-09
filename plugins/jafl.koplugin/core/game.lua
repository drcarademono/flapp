local XML = require("content/xml")
local Compatibility = require("content/compatibility")
local Combat = require("core/combat")
local Character = require("core/character")
local Expression = require("core/expression")
local Inventory = require("core/inventory")
local Journal = require("core/journal")
local Rules = require("core/rules")
local Ships = require("core/ships")
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
local function normalize_text(value)
    return tostring(value or ""):gsub("%s+"," "):gsub(" %- "," – "):gsub("%.%.%.","…")
end
local function plain(node)
    if type(node) == "string" then return normalize_text(node) end
    local out = {}; for _, child in ipairs(node.children or {}) do out[#out+1] = plain(child) end
    return normalize_text(table.concat(out)):match("^%s*(.-)%s*$")
end
local function item_from(a,node)
    local node_kind=node and (node.name=="weapon" or node.name=="armour" or node.name=="tool") and node.name or nil
    local item={ name=a.name or a.item or "item", quantity=tonumber(a.quantity or a.multiple) or 1, bonus=tonumber(a.bonus),
        kind=node_kind or a.type, ability=a.ability, group=a.group, tags=a.tags,
        weapon=node_kind=="weapon" or a.weapon, armour=node_kind=="armour" or a.armour, tool=node_kind=="tool" or a.tool }
    item.effects={}
    for _,child in ipairs(node and node.children or {}) do if type(child)=="table" and child.name=="effect" then
        item.effects[#item.effects+1]={kind=child.attr.type or "aura",ability=child.attr.ability,
            operation=child.attr.target and "target" or child.attr.divide and "divide" or "add",
            value=child.attr.bonus or child.attr.divide or child.attr.target,uses=child.attr.uses,text=child.attr.text}
    end end
    return item
end

function Game.new(catalog, state, random)
    local game=setmetatable({ catalog=catalog, state=state or State.new(),
        text={}, actions={}, errors={}, steps=0 }, Game)
    game.journal=Journal.new(game.state,random)
    return game
end

function Game:roll(sides) return self.journal:draw(sides) end
function Game:ability(name,modifier) return Inventory.ability(self.state,tostring(name or ""):gsub("^%l",string.upper),modifier) end
function Game:set_fixed_rules(value) return Rules.set_fixed(self.state,value) end

function Game:value(v)
    if v == nil then return 0 end
    if type(v) == "number" then return v end
    local n = tonumber(v); if n then return n end
    local sign, key = v:match("^([+-]?)([%w_*.-]+)$")
    if key then
        n = self.state.variables[key]
        if n == nil and self.state.abilities[key:gsub("^%l", string.upper)]~=nil then n=self:ability(key) end
        n = n or 0
        return sign == "-" and -n or n
    end
    local dice, sides, add = v:match("^(%d+)[dD](%d+)([+-]?%d*)$")
    if dice then
        local total = tonumber(add) or 0
        for _=1,tonumber(dice) do total = total + self:roll(tonumber(sides)) end
        return total
    end
    return Expression.evaluate(v,function(key)
        local lower=key:lower()
        if lower=="stamina" then return self.state.stamina end
        if lower=="shards" then return self.state.shards end
        if lower=="rank" then return self.state.rank end
        if lower=="defence" then return self:ability("Defence") end
        if lower=="weapon" then
            local id=self.state.models.equipment.weapon
            for _,item in ipairs(self.state.items) do if item.id==id or item.equipped and item.kind=="weapon" then return tonumber(item.bonus) or 0 end end
            return 0
        end
        if lower=="armour" then
            local id=self.state.models.equipment.armour
            for _,item in ipairs(self.state.items) do if item.id==id or item.equipped and item.kind=="armour" then return tonumber(item.bonus) or 0 end end
            return 0
        end
        return self.state.variables[key] or self:ability(key) or 0
    end)
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
    if ok and a.item then ok = Inventory.count(s,a) >= (tonumber(a.multiple) or 1) end
    if ok and a.weapon then ok = Inventory.count(s,a)>0 end
    if ok and a.armour then ok = Inventory.count(s,a)>0 end
    if ok and a.tool then ok = Inventory.count(s,a)>0 end
    if ok and a.shards then
        local available=s.shards
        if a.cache then available=(s.caches[a.cache] and s.caches[a.cache].shards) or 0 end
        ok = available >= self:value(a.shards)
    end
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
    if ok and a.rule then ok = Rules.active(self.state,a.rule) end
    if ok and a.ship then
        ok=#Ships.find(s,a.ship=="*" and nil or a.ship,true)>0
    end
    if ok and a.crew then
        local active=self.state.models.fleet.active; local ship=active and self.state.models.fleet.ships[active]
        ok=ship~=nil and (tostring(ship.crew.quality)==tostring(a.crew) or ship.crew.name==a.crew)
    end
    if ok and a.docked then
        local active=self.state.models.fleet.active; local ship=active and self.state.models.fleet.ships[active]
        ok=ship~=nil and tostring(ship.docked)==tostring(a.docked)
    end
    if ok and a.cargo then
        local ship=Ships.active(s); ok=false
        if ship then for _,cargo in ipairs(ship.cargo) do if a.cargo=="*" or cargo:lower():match("^"..a.cargo:lower()) then ok=true; break end end end
    end
    if ok and a.ability then
        local score=self:ability(a.ability,a.modifier)
        if a.greaterthan then ok=score>self:value(a.greaterthan)
        elseif a.lessthan then ok=score<self:value(a.lessthan)
        elseif a.equals then ok=score==self:value(a.equals) end
    end
    if ok and a.dead then ok = (s.stamina <= 0) == truth(a.dead, false) end
    -- Do not use Lua's `condition and false_value or true_value` pseudo-ternary
    -- here: when the negated result is false, `or ok` changes it back to true.
    if truth(a["not"],false) then return not ok end
    return ok
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
    end
    if (a.shards=="*" or a.gold=="*") and direction<0 then
        s.shards=0
    end
    if direction<0 and (a.item=="*" or a.weapon=="*" or a.armour=="*" or a.tool=="*") then
        State.remove_matching_items(s,a)
    end
    local amount = self:value(a.amount or a.value or a.stamina or 1) * direction
    if a.ship then
        if direction>0 then Ships.new(s,a) else Ships.remove(s,a.ship) end
        return
    elseif a.cargo then
        local ship=Ships.active(s)
        if direction>0 then Ships.add_cargo(ship,a.cargo,a.quantity) else Ships.remove_cargo(ship,a.cargo,a.quantity or a.amount) end
        return
    elseif a.crew then
        local ship=Ships.active(s)
        if direction>0 and not ship then Ships.new(s,{ship="barque",crew=a.crew})
        elseif tonumber(a.crew) then Ships.adjust_crew(ship,tonumber(a.crew)*direction)
        elseif ship then ship.crew.quality=Ships.crew(a.crew) end
        return
    end
    local ability = a.ability and a.ability:gsub("^%l", string.upper)
    if ability == "Stamina" then s.stamina = math.max(0, math.min(s.max_stamina, s.stamina + amount))
    elseif ability == "Rank" then
        s.rank = math.max(0, s.rank + amount)
        s.max_stamina=math.max(1,s.max_stamina+amount); s.stamina=math.min(s.stamina,s.max_stamina)
    elseif ability=="All" then
        for _,name in ipairs(State.ability_names) do
            s.abilities[name]=math.max(0,math.min(12,(s.abilities[name] or 0)+amount)); s.models.stats.natural[name]=s.abilities[name]
        end
    elseif ability and ability~="?" then
        s.abilities[ability]=math.max(0,math.min(12,(s.abilities[ability] or 0)+amount)); s.models.stats.natural[ability]=s.abilities[ability]
    elseif a.shards or a.gold or name == "adjustmoney" then s.shards = math.max(0, s.shards + self:value(a.shards or a.gold or a.amount) * direction)
    elseif a.codeword then for _,v in ipairs(words(a.codeword)) do s.codewords[v] = direction > 0 or nil end
    elseif a.title then for _,v in ipairs(words(a.title)) do s.titles[v] = direction > 0 or nil end
    elseif a.god then s.gods[a.god] = direction > 0 or nil
    elseif a.flag then s.flags[a.flag] = direction > 0 or nil
    elseif a.blessing then if direction>0 then Inventory.bless(s,a) else s.blessings[a.blessing]=nil end
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
    local source=type(data)=="table" and (data.node or data.market or (data.name and data.children and data)) or nil
    local action = { label=label, kind=kind, data=data, instruction=data and data.instruction or source and source._path or self.current_node and self.current_node._path }
    self.actions[#self.actions+1] = action
    if kind=="skillcheck" or kind=="random" or kind=="fight" or kind=="training" or kind=="goto" or
            kind=="market" or kind=="return" or kind=="resurrection" then
        self.blocking_node=source or self.current_node
    end
    return action
end

function Game:choose_starting_book()
    self.text={}; self.actions={}; self.image=nil
    for _,book in ipairs(self.catalog:installed_books()) do
        self:add_action(book.title,"startbook",{book=book.key})
    end
    return {title="New adventure",text="Choose a book to start in.",actions=self.actions}
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
    if running and running==(self.active_runner or self.section_runner) then
        self.pause_serial=(self.pause_serial or 0)+1
        local node=self.blocking_node or self.current_node
        local frames=self.state.execution and self.state.execution.frames
        if frames and frames[#frames] then frames[#frames].instruction=node and node._path or nil end
        self.state.pending={schema=1,kind="interaction",book=self.state.book,section=self.state.section,
            instruction=node and node._path or nil,actions={}}
        for _,action in ipairs(self.actions) do
            self.state.pending.actions[#self.state.pending.actions+1]={kind=action.kind,label=action.label,
                instruction=action.instruction}
        end
        coroutine.yield()
    end
end

function Game:resume_section()
    local runner=self.active_runner or self.section_runner
    if not runner or coroutine.status(runner)=="dead" then return true end
    local ok,err=coroutine.resume(runner)
    if not ok then error(err) end
    local finished=coroutine.status(runner)=="dead"
    if finished and self.nested_outer_runner then
        self.active_runner=self.nested_outer_runner; self.nested_outer_runner=nil
        local frame=self.state.execution.frames[#self.state.execution.frames]
        if frame then frame.completed=true end
        self:add_action("Continue combat","combat_continue",{instruction=self.state.combat and self.state.combat.owner})
    end
    return finished
end

local function ability_key(name)
    return name and name:gsub("^%l", string.upper)
end

local function roll_dice(game, count)
    local total = 0
    for _=1,count do total = total + game:roll(6) end
    return total
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
    local fights,damage,rounds,flees,by_path,groups,flee_choices={},{},{},{},{},{},{}
    local function visit(node,parent,index,path)
        if type(node)~="table" then return end
        node._parent,node._index=parent,index
        node._path=path or "1"
        by_path[node._path]=node
        if node.name=="fight" then fights[#fights+1]=node
        elseif node.name=="fightdamage" then damage[#damage+1]=node
        elseif node.name=="fightround" then rounds[#rounds+1]=node
        elseif node.name=="flee" then flees[#flees+1]=node end
        if node.name=="choice" and node.attr.flee then flee_choices[node.attr.flee]=flee_choices[node.attr.flee] or {}; flee_choices[node.attr.flee][#flee_choices[node.attr.flee]+1]=node end
        for child_index,child in ipairs(node.children or {}) do
            if type(child)=="table" then visit(child,node,child_index,(path or "1").."."..child_index) end
        end
    end
    visit(root,nil,nil,"1")
    for i,fight in ipairs(fights) do
        fight.fightdamage=damage[i]; fight.fightround=rounds[i]; fight.flee_node=flees[i]
        if fight.attr.group then groups[fight.attr.group]=groups[fight.attr.group] or {}; groups[fight.attr.group][#groups[fight.attr.group]+1]=fight end
    end
    return by_path,groups,flee_choices
end

function Game:start_combat_hook(hook,kind,path,replacement,reuse_frame)
    local frame=reuse_frame or {kind="combat_hook",hook_kind=kind,enemy=path,hook_path=hook._path,replacement=replacement}
    if not reuse_frame then self.state.execution.frames[#self.state.execution.frames+1]=frame end
    self.nested_outer_runner=self.active_runner or self.section_runner
    self.actions={}
    local runner=coroutine.create(function()
        for _,child in ipairs(hook.children or {}) do
            local action_count,pause_serial=#self.actions,self.pause_serial or 0
            self:walk(child,true)
            -- A blocker directly owned by a hook has no enclosing SectionNode
            -- to perform the deferred pause used by ordinary section prose.
            if #self.actions>action_count and (self.pause_serial or 0)==pause_serial then self:pause_section() end
        end
    end)
    self.active_runner=runner
    local ok,error_message=coroutine.resume(runner); if not ok then error(error_message) end
    if coroutine.status(runner)=="dead" then
        self.active_runner=self.nested_outer_runner; self.nested_outer_runner=nil
        table.remove(self.state.execution.frames)
        return false
    end
    return true
end

function Game:combat_hook(kind,path)
    local node=self.nodes_by_path[path]; if not node then return end
    local hook=kind=="damage" and node.fightdamage or kind=="round" and node.fightround or node.flee_node
    if not hook then return false,false end
    local replacement=kind=="damage" and tostring(hook.attr.type or ""):match("^repl")~=nil
    return self:start_combat_hook(hook,kind,path,replacement),replacement
end

function Game:preview_after(node)
    local original=self.text
    local rendered={}
    for i,value in ipairs(original) do rendered[i]=value end
    self.text=rendered
    local start=#rendered
    local current=node
    while current and current._parent do
        local parent=current._parent
        for i=(current._index or 0)+1,#(parent.children or {}) do self:render_node(parent.children[i]) end
        if parent.name=="p" or parent.name=="header" or parent.name:match("^h%d$") then
            self.text[#self.text+1]="\n\n"
        end
        current=parent
        if current.name=="section" then break end
    end
    local tail={}
    for i=start+1,#rendered do tail[#tail+1]=rendered[i] end
    self.text=original
    self.preview_text=table.concat(tail)
end

function Game:visible_text()
    return table.concat(self.text)..(self.preview_text or "")
end

function Game:route_death()
    if self.state.profession=="" or self.state.stamina>0 or #self.actions>0 then return end
    if self.state.resurrection then
        self:add_action("Use arranged resurrection","resurrect",self.state.resurrection)
        return
    end
    local death=self.catalog.books[self.state.book].properties.Death
    if death and tostring(death)~=self.state.section then return self:load(self.state.book,death) end
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

    local label = self:node_text(node)

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
    return label
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
                elseif child.name=="trade" then
                    if a.buy then self:add_action("Buy "..(a.ship or a.cargo or a.item or plain(child)).." ("..self:value(a.buy).." shards)","ship_trade",{node=child,market=node,direction=1,cost=self:value(a.buy)}) end
                    if a.sell then self:add_action("Sell "..(a.ship or a.cargo or a.item or plain(child)).." ("..self:value(a.sell).." shards)","ship_trade",{node=child,market=node,direction=-1,cost=self:value(a.sell)}) end
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

function Game:open_cache(node,message)
    local a=node.attr; local key=a.name or "cache"; local cache=Inventory.cache(self.state,key,a,node)
    self.actions={}; self.text={message or (a.text or "Manage stored possessions.")}
    self:add_action("Leave cache","leave_cache",{node=node,key=key})
    local unit=cache.rules.multiples or 1
    if self.state.shards>=unit and (not cache.rules.maximum or cache.shards+unit<=cache.rules.maximum) then
        self:add_action("Deposit "..unit.." Shards","cache_money",{node=node,key=key,amount=unit})
    end
    local charge=cache.rules.withdraw_charge or 0
    if cache.shards>=unit+charge then self:add_action("Withdraw "..unit.." Shards","cache_money",{node=node,key=key,amount=-unit}) end
    if not cache.rules.item_limit or #cache.items<cache.rules.item_limit then
        for index,item in ipairs(self.state.items) do if Inventory.cache_accepts(cache,item) then
            self:add_action("Deposit "..item.name,"cache_item",{node=node,key=key,index=index,direction=1})
        end end
    end
    for index,item in ipairs(cache.items) do
        self:add_action("Withdraw "..item.name,"cache_item",{node=node,key=key,index=index,direction=-1})
    end
end

function Game:apply_affliction(kind, node)
    Inventory.afflict(self.state,kind,node)
end

function Game:resume_pending_check_children()
    local pending=self.pending_check_children or {}
    self.pending_check_children=nil
    for _,child in ipairs(pending) do
        if type(child)=="table" and (child.name=="success" or child.name=="failure") then self:walk(child,true) end
    end
end

function Game:is_new_sentence()
    local text=table.concat(self.text):gsub("%s+$","")
    while text~="" do
        if text:sub(-1)=="'" or text:sub(-1)==")" then text=text:sub(1,-2):gsub("%s+$","")
        elseif text:sub(-3)=="’" then text=text:sub(1,-4):gsub("%s+$","")
        else break end
    end
    if text=="" then return true end
    return text:sub(-1):match("[%.%!%?%d]")~=nil
end

local number_words={"zero","one","two","three","four","five","six"}
local function numbered_dice(count)
    count=tonumber(count) or 1
    local amount=number_words[count+1] or tostring(count)
    return amount..(count==1 and " die" or " dice")
end
local function random_dice(count)
    count=tonumber(count) or 2
    if count==1 then return "one die" end
    if count==2 then return "two dice" end
    return tostring(count).." dice"
end

function Game:default_node_text(node)
    local n,a=node.name,node.attr or {}
    local lead=self:is_new_sentence()
    if n=="goto" then return self:goto_label(node) end
    if n=="random" then return (lead and "Roll " or "roll ")..random_dice(a.dice or 2) end
    if n=="difficulty" then
        local abilities=words(a.ability)
        local name=#abilities==1 and abilities[1]:upper() or ""
        return (lead and "Make a " or "make a ")..name.." roll at Difficulty "..tostring(a.level or "MISSING")
    end
    if n=="rankcheck" then
        local dice=tonumber(a.dice) or 1
        local text=(lead and "Roll " or "roll ")..numbered_dice(dice)
        local add=tonumber(a.add) or 0
        if add>0 then text=text.." and add "..(number_words[add+1] or tostring(add))
        elseif add<0 then text=text.." and subtract "..(number_words[-add+1] or tostring(-add)) end
        return text
    end
    if n=="reroll" then return lead and "Roll again" or "roll again" end
    if n=="training" then return (lead and "Roll " or "roll ")..numbered_dice(a.dice or 2) end
    if n=="lose" then
        if a.codeword then return (lead and "Erase" or "erase").." the codeword "..a.codeword end
        if a.stamina then
            local amount=tostring(a.stamina)
            return (lead and "Lose " or "lose ")..amount.." Stamina point"..((tonumber(amount)~=1) and "s" or "")
        end
        if a.item or a.weapon or a.armour or a.tool then return a.item or a.weapon or a.armour or a.tool end
        if a.shards then local value=tonumber(a.shards); return value==1 and "1 Shard" or tostring(a.shards).." Shards" end
        return a.curse or a.title
    end
    if n=="tick" then
        if a.codeword then return (lead and "Tick" or "tick").." the codeword "..a.codeword end
        if a.shards and self:value(a.shards)>0 then return tostring(a.shards).." Shards" end
        if a.title then return a.title end
        if not a.ability and not a.god and not a.name and not a.blessing then return "put a tick there now" end
    end
    if n=="item" or n=="weapon" or n=="armour" or n=="tool" then
        local name=a.name or a.item or a[n]
        local effects={}
        for _,child in ipairs(node.children or {}) do
            if type(child)=="table" and child.name=="effect" then
                local ea=child.attr or {}
                local description=ea.text or ea.description
                if not description and ea.ability and ea.bonus then
                    local bonus=tonumber(ea.bonus)
                    description=ea.ability:upper().." "..(bonus and bonus>=0 and "+" or "")..tostring(ea.bonus)
                elseif not description and ea.ability and ea.type=="use" then
                    description=ea.ability:upper().." +1"
                end
                if description then effects[#effects+1]=description end
            end
        end
        if name and #effects>0 then name=name.." ("..table.concat(effects,", ")..")" end
        return name
    end
    if n=="image" then return "[illustration]" end
    if n=="resurrection" then return a.text end
    if n=="extrachoice" then return a.text end
    if n=="field" then return (a.label or a.text or a.name).." " end
    return nil
end

function Game:node_text(node)
    local authored=plain(node)
    if authored~="" then return authored end
    if (self.hide_default_depth or 0)>0 or truth(node.attr and node.attr.hidden,false) then return nil end
    return self:default_node_text(node)
end

function Game:goto_label(node)
    local label=plain(node)
    if label~="" then return label end
    local a=node.attr or {}
    if a.book then
        local book=self.catalog.books[tostring(a.book)]
        return ((book and book.title) or ("Book "..tostring(a.book))).." "..tostring(a.section)
    end
    return (self:is_new_sentence() and "Turn to " or "turn to ")..tostring(a.section)
end

-- Render already-authored content after a blocking inline action without
-- executing its state changes or exposing later actions. Java builds the whole
-- document before its ExecutableRunner starts; this provides the same separation.
function Game:render_node(node)
    if type(node)=="string" then
        if node:match("%S") then self.text[#self.text+1]=normalize_text(node) end
        return
    end
    if truth(node.attr and node.attr.hidden,false) then return end
    local authored=plain(node)
    local generated=authored=="" and self:node_text(node) or nil
    if generated then
        self.text[#self.text+1]=generated
        if node.name=="goto" or node.name=="random" or node.name=="difficulty" or
                node.name=="rankcheck" or node.name=="reroll" or node.name=="training" or
                node.name=="lose" or node.name=="tick" or node.name=="image" or
                node.name=="resurrection" or node.name=="extrachoice" or node.name=="field" then return end
    end
    local hides=node.name=="group" or node.name=="effect" or node.name=="tradeevent"
    if hides then self.hide_default_depth=(self.hide_default_depth or 0)+1 end
    for _,child in ipairs(node.children or {}) do self:render_node(child) end
    if hides then self.hide_default_depth=self.hide_default_depth-1 end
    if node.name=="p" or node.name=="header" or node.name:match("^h%d$") then
        self.text[#self.text+1]="\n\n"
    end
end

function Game:walk(node, enabled)
    self.steps=self.steps+1; if self.steps > 10000 then error("section execution limit exceeded") end
    if type(node)=="string" then if enabled and node:match("%S") then self.text[#self.text+1]=normalize_text(node) end return end
    self.current_node=node
    local n,a=node.name,node.attr
    local blocker=n=="goto" or n=="random" or n=="difficulty" or n=="rankcheck" or n=="reroll" or n=="fight" or
        n=="return" or n=="training" or n=="market" or n=="trade" or n=="resurrection" or n=="group"
    if blocker and self.restoring and self.state.progress.completed[node._path] then return end
    local mutation=n=="set" or n=="tick" or n=="gain" or n=="lose" or
        n=="adjustmoney" or n=="transfer" or n=="curse" or n=="disease" or n=="poison"
    if mutation and self.restoring and self.state.progress.applied[node._path] then return end
    local optional_mutation=(n=="tick" or n=="gain" or n=="lose") and not truth(a.force,true)
    if mutation and not optional_mutation then self.state.progress.applied[node._path]=true end
    if n=="if" or n=="elseif" then enabled=enabled and self:condition(a)
    elseif n=="else" then enabled=enabled -- grouped else parity is handled by authored mutually-exclusive blocks where possible
    end
    if not enabled then return end
    if n=="choice" then
        local visit_key=self.state.book..":"..self.state.section..":"..node._path
        if self.state.models.visits[visit_key] and not truth(a.revisit,false) then return end
        if self:condition(a) and destination_matches_life_state(self.state,a) and
                (not a.book or self.catalog.books[a.book] and self.catalog.books[a.book].installed) then
            self:add_action(plain(node),"goto",a)
        end
        return
    elseif n=="section" then
        local dock=a.todock or a.dock
        if dock then Ships.set_location(self.state,dock) end
        for _,choice in pairs(self.state.models.extra_choices) do
            local active=choice.activation or {}
            if (active.book==self.state.book and active.section==self.state.section) or
                    (active.tag and active.tag==a.tag) then
                self:add_action(choice.text or choice.key,"goto",choice.destination)
            end
        end
        for index,item in ipairs(self.state.items) do
            if (item.kind=="weapon" or item.kind=="armour" or item.kind=="tool") and not item.equipped then
                self:add_action("Equip "..item.name,"equip",{index=index})
            end
            for effect_index,effect in ipairs(item.effects or {}) do if effect.kind=="use" and (effect.uses==nil or effect.uses>0) then
                self:add_action(effect.text or ("Use "..item.name),"use_item",{index=index,effect=effect_index})
            end end
        end
        for index,ship in ipairs(self.state.models.fleet.ships) do if index~=self.state.models.fleet.active and Ships.here(self.state,ship) then
            self:add_action("Select "..ship.name,"select_ship",{index=index})
        end end
    elseif n=="goto" then
        local visit_key=self.state.book..":"..self.state.section..":"..node._path
        if self.state.models.visits[visit_key] and not truth(a.revisit,false) then return end
        -- GotoNode.canUse() defaults dead to false: ordinary destinations are
        -- unavailable while dead, while dead="t" destinations are death-only.
        if self:condition(a) and destination_matches_life_state(self.state,a) then
            local display_label=self:goto_label(node)
            self.text[#self.text+1]=display_label
            self:add_action(display_label,"goto",a)
            if truth(a.force,true) then
                -- Parsing and execution are separate in Java: finish presenting
                -- the containing block (or the section itself) before the forced
                -- destination suspends executable processing.
                self.deferred_block=true
            end
        end
        return
    elseif n=="set" then
        local value=a.codeword and (self.state.codewords[a.codeword] and 1 or 0) or self:value(a.value or a.amount)
        self.state.variables[a.name or a.var or "*"]=value
        if a.dock then for _,ship in ipairs(self.state.models.fleet.ships) do ship.docked=a.dock end end
    elseif n=="tick" then
        if not truth(a.force,true) then self:add_action(self:node_text(node) or "Apply gain","mutate",{node=node,direction=1}); return end
        if plain(node)=="" and not truth(a.hidden,false) then local text=self:node_text(node); if text then self.text[#self.text+1]=text end end
        self.state.ticks=self.state.ticks+self:value(a.count or a.amount or 1); self:mutate(n,a,1)
        if a.god then Inventory.attach_god_effects(self.state,a.god,node) end
    elseif n=="gain" then
        if a.ability=="?" then
            for _,ability in ipairs(State.ability_names) do self:add_action((self:node_text(node) or "Choose ability").." ("..ability..")","mutate",{node=node,direction=1,ability=ability}) end
            self:pause_section(); return
        end
        if not truth(a.force,true) then self:add_action(self:node_text(node) or "Take gain","mutate",{node=node,direction=1}); return end
        self:mutate(n,a,1)
    elseif n=="lose" then
        if a.flag and not self.state.flags[a.flag] then return end
        if a.ability=="?" then
            for _,ability in ipairs(State.ability_names) do self:add_action((self:node_text(node) or "Choose ability").." ("..ability..")","mutate",{node=node,direction=-1,ability=ability}) end
            self:pause_section(); return
        end
        if not truth(a.force,true) then self:add_action(self:node_text(node) or "Pay cost","mutate",{node=node,direction=-1}); return end
        if plain(node)=="" and not truth(a.hidden,false) then local text=self:node_text(node); if text then self.text[#self.text+1]=text end end
        self:mutate(n,a,-1)
    elseif n=="adjust" then return
    elseif n=="price" then
        local cost=self:value(a.shards or a.gold or a.amount or 0)
        if self.state.shards>=cost then self:add_action(plain(node)~="" and plain(node) or ("Pay "..cost.." Shards"),"pay_price",{node=node,cost=cost}) end
        return
    elseif n=="adjustmoney" then
        local multiplier=self:value(a.multiply or 1); local cache=a.cache or a.name
        if cache then local target=self.state.caches[cache] or State.new_cache(); self.state.caches[cache]=target; target.shards=math.max(0,target.shards*multiplier)
        else self.state.shards=math.max(0,self.state.shards*multiplier) end
    elseif n=="rest" then
        if self.state.stamina<self.state.max_stamina and self.state.shards>=self:value(a.shards or 0) then
            self:add_action(self:node_text(node) or "Rest","rest",node)
        end
        return
    elseif n=="random" then
        if not a.flag or self.state.flags[a.flag] then
            local label=self:node_text(node)
            self.text[#self.text+1]=label
            self:add_action(label,"random",node)
            if truth(a.force,true) then
                if (self.paragraph_depth or 0)>0 then self.pause_after_paragraph=true
                else self.pause_before_outcomes=true end
            end
        end
        return
    elseif n=="difficulty" or n=="rankcheck" then
        local label=self:add_check(node)
        if label then self.text[#self.text+1]=label end
        if truth(a.force,true) then
            if (self.paragraph_depth or 0)>0 then
                self.pause_after_paragraph=true
                self.pending_check_children=node.children
            else
                -- A check may be inline in a section without a <p> wrapper (for
                -- example 2.499). Render its following text, then stop immediately
                -- before the outcomes that depend on the unresolved roll.
                self.pause_before_outcomes=true
                self.pending_check_children=node.children
            end
        end
        return
    elseif n=="reroll" then
        local label=self:node_text(node)
        self.text[#self.text+1]=label
        self:add_action(label,"reroll",node)
        self:preview_after(node); self:pause_section(); return
    elseif n=="success" or n=="failure" then
        local result=self.state.variables[a.var or "*difficulty*"]
        if result==nil then
            self:attach_check_branch(node)
            return
        end
        if (n=="success")~=(result>0) then return end
        if a.section then
            local fallback=(n=="success" and "Successful roll" or "Failed roll")
            local label=plain(node)~="" and plain(node) or fallback
            self.text[#self.text+1]=label
            self:add_action(label,"goto",a)
            self.deferred_block=true
        else
            for _,child in ipairs(node.children or {}) do self:walk(child,true) end
        end
        return
    elseif n=="outcomes" then
        if self.pause_before_outcomes then
            self.pause_before_outcomes=false
            self:pause_section()
            self:resume_pending_check_children()
        end
        local has_check_branch=false
        for _,child in ipairs(node.children or {}) do
            if type(child)=="table" and (child.name=="success" or child.name=="failure") then
                has_check_branch=true; break
            end
        end
        local default_var=has_check_branch and "*difficulty*" or "*random*"
        local value=self.state.variables[a.var or default_var]
        if value==nil and not has_check_branch then value=self.last_roll end
        if value==nil then
            -- A conditional/optional check may never have been offered. Java
            -- still executes ordinary ChoiceNodes in the outcomes container
            -- (for example the "No parchment" exit in 2.543), while leaving
            -- success/failure destinations dormant until a result exists.
            for _,child in ipairs(node.children or {}) do
                if type(child)=="table" and child.name=="choice" then self:walk(child,true)
                elseif type(child)=="table" and (child.name=="success" or child.name=="failure") then
                    self:attach_check_branch(child)
                end
            end
            return
        end
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
        if a.section and destination_matches_life_state(self.state,a) then
            local label=plain(node)~="" and plain(node) or ("Turn to "..tostring(a.section))
            self.text[#self.text+1]=label
            self:add_action(label,"goto",a)
            self.deferred_block=true
        else
            for _,child in ipairs(node.children or {}) do self:walk(child,true) end
        end
        return
    elseif n=="fightdamage" or n=="fightround" or n=="flee" then
        -- Parsed up front and owned by the corresponding fight, as in FightNode.hookupNodes().
        return
    elseif n=="fight" then
        self:add_action("Fight "..(a.name or "enemy"),"fight",node)
        self:preview_after(node); self:pause_section()
        return
    elseif n=="return" then
        local label=plain(node)~="" and plain(node) or "Return"
        self.text[#self.text+1]=label
        if #self.state.history>0 then self:add_action(label,"return",a) end
        if truth(a.force,true) then self:preview_after(node); self:pause_section() end
        return
    elseif n=="training" then
        local label=self:node_text(node)
        self.text[#self.text+1]=label
        if a.ability=="?" then
            for _,ability in ipairs(State.ability_names) do self:add_action(label.." ("..ability..")","training",{node=node,ability=ability}) end
        else self:add_action(label,"training",node) end
        self:preview_after(node); self:pause_section(); return
    elseif n=="resurrection" then
        local label=self:node_text(node) or (a.section and "Arrange resurrection" or "Use resurrection")
        if plain(node)=="" and label then self.text[#self.text+1]=label end
        if a.section then self:add_action(label,"resurrection",a)
        elseif self.state.stamina<=0 and self.state.resurrection then self:add_action(label,"resurrect",self.state.resurrection) end
        return
    elseif n=="itemcache" or n=="moneycache" then
        local key=a.name; Inventory.cache(self.state,key,a,node)
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
        while self.state.variables[a.var]==nil and guard<100 do
            guard=guard+1
            for _,child in ipairs(node.children or {}) do self:walk(child,true) end
        end
        return
    elseif n=="extrachoice" then
        local list=self.state.models.extra_choices
        if a.remove then list[a.remove]=nil
        elseif a.key then list[a.key]=State.new_extra_choice(a) end
        return
    elseif n=="field" then
        local label=a.label or a.text or a.name or "Value"
        local value=self.state.variables[a.name]
        if value==nil then value=self.state.codewords[a.name] and 1 or 0 end
        self.text[#self.text+1]=label..": "..tostring(value)
        return
    elseif n=="sectionview" then
        self.text[#self.text+1]=plain(node).." [Section preview is available in the Java desktop reader only.]"
        return
    elseif n=="group" and not truth(a.force,true) then
        self:add_action(self:node_text(node) or "Apply grouped action","group",node)
        return
    elseif n=="market" or n=="trade" then
        self:add_action(plain(node)~="" and plain(node) or "Open market","market",node)
        self:preview_after(node); self:pause_section()
        return
    elseif n=="buy" or n=="sell" then
        local cost=self:value(a.price or a.shards or a.amount or 0)
        local label=(n=="buy" and "Buy " or "Sell ")..(a.name or a.item or plain(node)).." ("..cost.." shards)"
        self:add_action(label,n,{attr=a,node=node,cost=cost}); return
    elseif n=="image" then
        local label=self:node_text(node)
        if label then self.text[#self.text+1]=label end
        self.image=self.catalog:asset_path(a.book or self.state.book,a.file or a.name); return
    end
    if (n=="item" or n=="weapon" or n=="armour" or n=="tool" or n=="extrachoice" or n=="field") and plain(node)=="" then
        local label=self:node_text(node); if label then self.text[#self.text+1]=label end
    end
    local is_paragraph=n=="p"
    local is_conditional=n=="if" or n=="elseif" or n=="else"
    local hides_child_defaults=n=="group" or n=="effect" or n=="tradeevent"
    if is_paragraph then self.paragraph_depth=(self.paragraph_depth or 0)+1 end
    if is_conditional then self.conditional_depth=(self.conditional_depth or 0)+1 end
    if hides_child_defaults then self.hide_default_depth=(self.hide_default_depth or 0)+1 end
    local branch_taken=false
    local in_chain=false
    for _,child in ipairs(node.children or {}) do
        if self.deferred_block then
            self:render_node(child)
        elseif type(child)=="table" and child.name=="if" then
            local matched=self:condition(child.attr); branch_taken=matched; in_chain=true
            if matched then self:walk(child,true) else self:render_node(child) end
        elseif type(child)=="table" and child.name=="elseif" and in_chain then
            local matched=not branch_taken and self:condition(child.attr); branch_taken=branch_taken or matched
            if matched then self:walk(child,true) else self:render_node(child) end
        elseif type(child)=="table" and child.name=="else" and in_chain then
            if not branch_taken then self:walk(child,true) else self:render_node(child) end
            in_chain=false; branch_taken=false
        elseif type(child)=="string" and not child:match("%S") then
            self:walk(child,enabled)
        else
            in_chain=false; branch_taken=false; self:walk(child,enabled)
        end
    end
    if hides_child_defaults then self.hide_default_depth=self.hide_default_depth-1 end
    if n=="p" or n=="header" or n:match("^h%d$") then self.text[#self.text+1]="\n\n" end
    if is_paragraph then
        self.paragraph_depth=self.paragraph_depth-1
        if self.paragraph_depth==0 and self.deferred_block then
            self.deferred_block=false
            self:pause_section()
        end
        if self.paragraph_depth==0 and self.pause_after_paragraph then
            self.pause_after_paragraph=false
            self:pause_section()
            self:resume_pending_check_children()
        end
    end
    if is_conditional then
        self.conditional_depth=self.conditional_depth-1
        if self.conditional_depth==0 and self.deferred_block and self.paragraph_depth==0 then
            self.deferred_block=false
            self:pause_section()
        end
    end
    if n=="section" and self.pause_before_outcomes then
        self.pause_before_outcomes=false
        self:pause_section()
        self:resume_pending_check_children()
    end
    if n=="section" and self.deferred_block then
        self.deferred_block=false
        self:pause_section()
    end
end

function Game:load(book, section)
    local path,err=self.catalog:section_path(book,section); if not path then return nil,err end
    local root,xerr=XML.read(path); if not root then return nil,xerr end
    local declared,compatibility_error=pcall(Compatibility.assert_declared,root,tostring(book).."/"..tostring(section))
    if not declared then return nil,compatibility_error end
    local pending=self.state.pending
    self.restoring=pending and pending.kind=="interaction" and pending.book==tostring(book) and pending.section==tostring(section) and self.state.progress~=nil
    if not self.restoring then
        self.state.progress={schema=1,book=tostring(book),section=tostring(section),applied={},completed={}}
        self.state.pending=nil
    end
    self.state.book,self.state.section=tostring(book),tostring(section); self.text={}; self.preview_text=nil; self.actions={}; self.steps=0; self.image=nil
    Rules.enter_book(self.state,self.catalog.books[self.state.book].properties)
    self.paragraph_depth=0; self.conditional_depth=0; self.hide_default_depth=0; self.deferred_block=false; self.pause_after_paragraph=false; self.pause_before_outcomes=false; self.pending_check_children=nil; self.blocking_node=nil
    if not self.restoring then self.state.variables["*difficulty*"]=nil; self.state.variables["*random*"]=nil end
    self.pending_checks={}; self.checks_by_var={}
    self.nodes_by_path,self.fight_groups,self.flee_choices=pair_fight_nodes(root)
    self.section_runner=coroutine.create(function() self:walk(root,true) end); self.active_runner=self.section_runner
    local ok,msg=pcall(function() self:resume_section() end); if not ok then return nil,msg end
    if self.state.combat and self.state.combat.book==self.state.book and self.state.combat.section==self.state.section then
        local frame=self.state.execution.frames[#self.state.execution.frames]
        if frame and frame.kind=="combat_hook" then
            self.actions={}
            if frame.completed then self:add_action("Continue combat","combat_continue",{instruction=self.state.combat.owner})
            else
                local hook=self.nodes_by_path[frame.hook_path]
                if hook then self:start_combat_hook(hook,frame.hook_kind,frame.enemy,frame.replacement,frame) end
            end
        else
            self.actions={}; self:add_action("Attack","combat_attack",{instruction=self.state.combat.owner})
            if Combat.stalemate(self) then self:add_action("Skip stalemated combat","combat_skip",{instruction=self.state.combat.owner}) end
            for _,choice in ipairs(self.flee_choices[self.state.combat.group] or {}) do self:add_action(plain(choice),"combat_flee",{instruction=self.state.combat.owner,destination=choice.attr}) end
        end
    end
    if self.restoring and pending and (pending.resume_kind=="market" or pending.resume_kind=="buy" or pending.resume_kind=="sell") then
        for _,action in ipairs(self.actions) do
            if action.kind=="market" then self:open_market(action.data); break end
        end
    end
    local death_result=self:route_death(); if death_result then return death_result end
    if not self.state.pending then
        self.state.pending={schema=1,kind="interaction",book=self.state.book,section=self.state.section,instruction=nil,actions={}}
    end
    return { title=(self.catalog.books[self.state.book].title or "").." — "..self.state.section,
        text=self:visible_text():gsub("[ \t]+\n","\n"):match("^%s*(.-)%s*$"), actions=self.actions, image=self.image }
end

function Game:_choose(index)
    local action=self.actions[index]; if not action then return nil,"Invalid choice" end
    self.preview_text=nil
    if action.kind=="startbook" then
        self.state.book=tostring(action.data.book); self.state.section="New"
        return self:load(self.state.book,self.state.section)
    elseif action.kind=="select_ship" then
        local ship=self.state.models.fleet.ships[action.data.index]; if not ship then return nil,"Ship is no longer available." end
        self.state.models.fleet.active=action.data.index
        return {title="Ship selected",text="Selected "..ship.name..".",actions=self.actions,image=self.image}
    elseif action.kind=="equip" then
        local item=self.state.items[action.data.index]; if not item then return nil,"Item is no longer available." end
        Inventory.equip(self.state,item)
        for i,candidate in ipairs(self.actions) do if candidate==action then table.remove(self.actions,i); break end end
        return {title="Equipment",text="Equipped "..item.name..".",actions=self.actions,image=self.image}
    elseif action.kind=="use_item" then
        local item=self.state.items[action.data.index]; local effect=item and item.effects[action.data.effect]
        if not effect or effect.uses==0 then return nil,"That effect is no longer available." end
        local ability=effect.ability and ability_key(effect.ability)
        if ability and ability~="*" then
            local value=tonumber(effect.value) or 0
            if effect.operation=="target" then self.state.abilities[ability]=value
            elseif effect.operation=="divide" then self.state.abilities[ability]=math.floor((self.state.abilities[ability] or 0)/math.max(1,value))
            else self.state.abilities[ability]=math.max(0,(self.state.abilities[ability] or 0)+value) end
        end
        if effect.uses then effect.uses=effect.uses-1 end
        if effect.uses==0 then for i,candidate in ipairs(self.actions) do if candidate==action then table.remove(self.actions,i); break end end end
        return {title="Item used",text=effect.text or ("Used "..item.name.."."),actions=self.actions,image=self.image}
    elseif action.kind=="mutate" then
        local node=action.data.node
        local attributes=State.copy(node.attr); if action.data.ability then attributes.ability=action.data.ability end
        self:mutate(node.name,attributes,action.data.direction)
        if action.data.direction>0 and node.attr.god then Inventory.attach_god_effects(self.state,node.attr.god,node) end
        if node.name=="tick" then self.state.ticks=self.state.ticks+self:value(node.attr.count or node.attr.amount or 1) end
        self.state.progress.applied[node._path]=true
        for i,candidate in ipairs(self.actions) do if candidate==action then table.remove(self.actions,i); break end end
        return {title="Action applied",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="pay_price" then
        local data=action.data
        if self.state.shards<data.cost then return nil,"You cannot afford that." end
        self.state.shards=self.state.shards-data.cost
        if data.node.attr.flag then self.state.flags[data.node.attr.flag]=true end
        for index,candidate in ipairs(self.actions) do if candidate==action then table.remove(self.actions,index); break end end
        return {title="Payment made",text="Paid "..data.cost.." Shards.",actions=self.actions,image=self.image}
    elseif action.kind=="rest" then
        local node,a=action.data,action.data.attr
        local cost=self:value(a.shards or 0)
        if self.state.shards<cost then return nil,"You cannot afford to rest." end
        self.state.shards=self.state.shards-cost
        local amount=a.stamina and self:value(a.stamina) or (self.state.max_stamina-self.state.stamina)
        self.state.stamina=math.min(self.state.max_stamina,self.state.stamina+amount)
        self.state.progress.applied[node._path]=true
        for i,candidate in ipairs(self.actions) do if candidate==action then table.remove(self.actions,i); break end end
        return {title="Rested",text=table.concat(self.text).."\n\nRestored "..amount.." Stamina.",actions=self.actions,image=self.image}
    elseif action.kind=="group" then
        self.actions={}
        for _,child in ipairs(action.data.children or {}) do self:walk(child,true) end
        return {title="Action applied",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="reroll" then
        local record,error_message=self.journal:undo(); if not record then return nil,error_message end
        local meta=record.metadata or {}; local a=meta.attr or {}
        if meta.kind=="random" then
            local source=self.nodes_by_path and self.nodes_by_path[meta.instruction]
            local roll=roll_dice(self,tonumber(a.dice) or 2)+(source and self:check_adjustment(source) or 0)
            self.state.variables[a.var or "*random*"]=roll
            return {title="Reroll result",text="Rolled "..roll..".",actions=self.actions,image=self.image}
        elseif meta.kind=="skillcheck" then
            local ability=meta.ability or words(a.ability)[1]; local score=self:ability(ability)
            local source=self.nodes_by_path and self.nodes_by_path[meta.instruction]
            local adjustment=source and self:check_adjustment(source) or 0
            local roll
            if meta.node_name=="rankcheck" then
                roll=roll_dice(self,tonumber(a.dice) or 1)+self:value(a.add or 0)+adjustment
                self.state.variables[a.var or "*difficulty*"]=self.state.rank-roll+1
            else
                roll=self:roll(6)+self:roll(6)+score+adjustment
                self.state.variables[a.var or "*difficulty*"]=roll-self:value(a.level)
            end
            return {title="Reroll result",text=ability_key(ability).." reroll: "..roll..".",actions=self.actions,image=self.image}
        elseif meta.kind=="training" then
            local ability=ability_key(meta.ability or a.ability); local roll=roll_dice(self,tonumber(a.dice) or 2)+self:value(a.add or 0)
            if ability and roll>(self.state.abilities[ability] or 0) then self.state.abilities[ability]=math.min(12,(self.state.abilities[ability] or 0)+1) end
            if ability then self.state.models.stats.natural[ability]=self.state.abilities[ability] end
            return {title="Reroll result",text="Training reroll: "..roll..".",actions=self.actions,image=self.image}
        elseif meta.kind=="combat_attack" and self.state.combat then
            local status=Combat.attack(self,function(kind,path,amount) return self:combat_hook(kind,path,amount) end)
            local log=table.concat(self.state.combat.log,"\n")
            if status=="blocked" then
                return {title="Combat event",text=table.concat(self.text).."\n\n"..log,actions=self.actions,image=self.image}
            elseif status=="ongoing" then
                self.actions={}; self:add_action("Attack","combat_attack",{instruction=self.state.combat.owner})
                if Combat.stalemate(self) then self:add_action("Skip stalemated combat","combat_skip",{instruction=self.state.combat.owner}) end
                for _,choice in ipairs(self.flee_choices[self.state.combat.group] or {}) do self:add_action(plain(choice),"combat_flee",{instruction=self.state.combat.owner,destination=choice.attr}) end
                return {title="Combat reroll",text=log,actions=self.actions,image=self.image}
            end
            local opponents=self.state.combat.opponents; self.state.combat=nil; self.actions={}
            if self.state.progress then for _,enemy in ipairs(opponents) do self.state.progress.completed[enemy.path]=true end end; self:resume_section()
            local death_result=self:route_death(); if death_result then return death_result end
            return {title="Combat reroll",text=log.."\n\n"..(status=="won" and "You win the fight." or "You have been defeated."),actions=self.actions,image=self.image}
        end
        return nil,"The preceding action cannot be rerolled."
    elseif action.kind=="skillcheck" then
        local node,a=action.data.node,action.data.node.attr
        local adjustment=self:check_adjustment(node)
        local roll,score,success,description
        if node.name=="rankcheck" then
            local dice=tonumber(a.dice) or 1
            roll=self:value(a.add or 0)+adjustment
            for _=1,dice do roll=roll+self:roll(6) end
            score=self.state.rank
            success=roll<=score
            description=string.format("Rank check: rolled %d against Rank %d — %s.",roll,score,success and "success" or "failure")
            self.state.variables["*ability*"]="Rank"
        else
            local chosen=action.data.ability or words(a.ability)[1]
            score=self:ability(chosen)+adjustment
            roll=self:roll(6)+self:roll(6)+score
            success=roll>self:value(a.level)
            description=string.format("%s check: rolled %d against Difficulty %d — %s.",
                ability_key(chosen),roll,self:value(a.level),success and "success" or "failure")
            self.state.variables["*ability*"]=ability_key(chosen)
        end
        local result = node.name=="rankcheck" and (score-roll+1) or (roll-self:value(a.level))
        self.state.variables[a.var or "*difficulty*"]=result
        if a.flag then self.state.flags[a.flag]=nil end
        local remaining={}
        if not truth(a.force,true) then
            local group=action.data.group or action.data
            for _,candidate in ipairs(self.actions) do
                if (candidate.data.group or candidate.data)~=group then remaining[#remaining+1]=candidate end
            end
            self.actions=remaining
            for _,branch in ipairs(group.branches or {}) do
                local matched=branch.name=="success" and result>0 or branch.name=="failure" and result<=0
                if matched then
                    if branch.attr.section then
                        local fallback=branch.name=="success" and "Successful roll" or "Failed roll"
                        self:add_action(plain(branch)~="" and plain(branch) or fallback,"goto",branch.attr)
                    else
                        for _,child in ipairs(branch.children or {}) do self:walk(child,true) end
                    end
                    break
                end
            end
        end
        if truth(a.force,true) then self.actions=remaining end
        if truth(a.force,true) then self:resume_section() end
        self.text[#self.text+1]="\n\n"..description
        return {title="Check result",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="random" then
        local node,a=action.data,action.data.attr
        local roll=roll_dice(self,tonumber(a.dice) or 2)+self:check_adjustment(node)
        self.last_roll=roll; self.state.variables[a.var or "*random*"]=roll
        if a.flag then self.state.flags[a.flag]=nil end
        self.actions={}
        if truth(a.force,true) then self:resume_section() end
        self.text[#self.text+1]="\n\nRolled "..tostring(roll).."."
        return {title="Roll result",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="goto" then
        local a=action.data
        if truth(a.pay,a.shards~=nil) then self.state.shards=math.max(0,self.state.shards-self:value(a.shards or 0)); if a.item then State.remove_item(self.state,a.item,1) end end
        if a.sail then self.state.at_sea=true; Ships.set_location(self.state,"*sea*") end
        if self.state.profession=="" then
            local template,template_error=Character.load(self.catalog,self.state.book)
            local adventurer=template and Character.find(template,a.section)
            if adventurer then Character.apply(self.state,template,adventurer)
            elseif template_error then return nil,template_error end
        end
        if a.visit then table.insert(self.state.history,{book=self.state.book,section=self.state.section}) end
        if action.instruction then
            local key=self.state.book..":"..self.state.section..":"..action.instruction
            self.state.models.visits[key]=(self.state.models.visits[key] or 0)+1
        end
        if self.state.execution and #self.state.execution.frames>0 then
            self.state.execution.frames={}; self.state.combat=nil; self.nested_outer_runner=nil
        end
        return self:load(a.book or self.state.book,a.section)
    elseif action.kind=="return" then
        local destination=table.remove(self.state.history)
        if not destination then return nil,"There is no previous section." end
        return self:load(destination.book,destination.section)
    elseif action.kind=="training" then
        local node=action.data.node or action.data; local a=node.attr
        local ability=ability_key(action.data.ability or a.ability)
        local roll=roll_dice(self,tonumber(a.dice) or 2)+self:value(a.add or 0)
        local old_score=ability and self:ability(ability) or 0
        if ability and ability~="?" and roll>(self.state.abilities[ability] or 0) then
            self.state.abilities[ability]=math.min(12,(self.state.abilities[ability] or 0)+1)
            self.state.models.stats.natural[ability]=self.state.abilities[ability]
        end
        self.state.variables.exp=roll-old_score
        if a.var then self.state.variables[a.var]=roll end
        self.actions={}; self:resume_section()
        self.text[#self.text+1]="\n\nTraining roll: "..roll.."."
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
        self:open_cache(action.data.node)
        return {title=action.data.key,text=table.concat(self.text,"\n"),actions=self.actions,image=self.image}
    elseif action.kind=="cache_money" then
        local data=action.data; local cache=self.state.caches[data.key]
        if data.amount>0 then self.state.shards=self.state.shards-data.amount; cache.shards=cache.shards+data.amount
        else local unit=-data.amount; cache.shards=cache.shards-unit-(cache.rules.withdraw_charge or 0); self.state.shards=self.state.shards+unit end
        self:open_cache(data.node,"Cache balance updated.")
        return {title=data.key,text=table.concat(self.text,"\n"),actions=self.actions,image=self.image}
    elseif action.kind=="cache_item" then
        local data=action.data; local cache=self.state.caches[data.key]
        if data.direction>0 then local item=self.state.items[data.index]; Inventory.unequip(self.state,item); table.insert(cache.items,table.remove(self.state.items,data.index))
        else table.insert(self.state.items,table.remove(cache.items,data.index)) end
        self:open_cache(data.node,"Possessions updated.")
        return {title=data.key,text=table.concat(self.text,"\n"),actions=self.actions,image=self.image}
    elseif action.kind=="leave_cache" then
        return {title="Cache",text=table.concat(self.text,"\n"),actions={},image=self.image}
    elseif action.kind=="ship_trade" then
        local data,node=action.data,action.data.node; local a=node.attr; local ship=Ships.active(self.state)
        if data.direction>0 then
            if self.state.shards<data.cost then return nil,"You cannot afford that." end
            if a.ship then Ships.new(self.state,a)
            elseif a.cargo then if not Ships.add_cargo(ship,a.cargo,a.quantity) then return nil,"The selected ship has no cargo space." end
            elseif a.crew then if not ship then return nil,"There is no ship here." end; ship.crew.quality=Ships.crew(a.crew)
            else State.add_item(self.state,item_from(a,node)) end
            self.state.shards=self.state.shards-data.cost
        else
            local sold=a.ship and Ships.remove(self.state,a.ship) or a.cargo and Ships.remove_cargo(ship,a.cargo,a.quantity) or State.remove_item(self.state,a.item or a.name,tonumber(a.quantity) or 1)
            if not sold then return nil,"There is nothing matching that sale here." end
            self.state.shards=self.state.shards+data.cost
        end
        for _,child in ipairs(node.children or {}) do
            if type(child)=="table" and ((data.direction<0 and child.name=="sold") or (data.direction>0 and child.name=="bought")) then
                for _,effect in ipairs(child.children or {}) do self:walk(effect,true) end
            end
        end
        self:open_market(data.market,(data.direction>0 and "Purchase completed." or "Sale completed."))
        return {title="Market",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="fight" then
        local node=action.data
        local opponents=node.attr.group and self.fight_groups[node.attr.group] or {node}
        local combat=Combat.start(self,node,opponents)
        combat.book,combat.section=self.state.book,self.state.section
        self.actions={}; self:add_action("Attack","combat_attack",{instruction=node._path})
        if Combat.stalemate(self) then self:add_action("Skip stalemated combat","combat_skip",{instruction=node._path}) end
        for _,choice in ipairs(self.flee_choices[node.attr.group] or {}) do self:add_action(plain(choice),"combat_flee",{instruction=node._path,destination=choice.attr}) end
        return {title="Combat",text=table.concat(combat.log,"\n"),actions=self.actions,image=self.image}
    elseif action.kind=="combat_attack" then
        local status=Combat.attack(self,function(kind,path,amount) return self:combat_hook(kind,path,amount) end)
        local combat=self.state.combat; local log=table.concat(combat.log,"\n")
        if status=="blocked" then
            return {title="Combat event",text=table.concat(self.text).."\n\n"..log,actions=self.actions,image=self.image}
        end
        if status=="ongoing" then
            self.actions={}; self:add_action("Attack","combat_attack",action.data)
            if Combat.stalemate(self) then self:add_action("Skip stalemated combat","combat_skip",action.data) end
            for _,choice in ipairs(self.flee_choices[combat.group] or {}) do self:add_action(plain(choice),"combat_flee",{instruction=combat.owner,destination=choice.attr}) end
            return {title="Combat — round "..combat.round,text=log,actions=self.actions,image=self.image}
        end
        if self.state.progress then for _,enemy in ipairs(combat.opponents) do self.state.progress.completed[enemy.path]=true end end
        self.state.combat=nil; self.actions={}
        self:resume_section()
        local death_result=self:route_death(); if death_result then return death_result end
        self.text[#self.text+1]="\n\n"..log.."\n\n"..(status=="won" and "You win the fight." or "You have been defeated.")
        return {title="Combat result",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="combat_continue" then
        self.actions={}
        local frame=self.state.execution.frames[#self.state.execution.frames]
        if frame and frame.kind=="combat_hook" and frame.completed then table.remove(self.state.execution.frames) end
        local status=Combat.continue(self,function(kind,path,amount) return self:combat_hook(kind,path,amount) end)
        local combat=self.state.combat; local log=table.concat(combat.log,"\n")
        if status=="blocked" then return {title="Combat event",text=table.concat(self.text).."\n\n"..log,actions=self.actions,image=self.image} end
        if status=="ongoing" then
            self:add_action("Attack","combat_attack",{instruction=combat.owner})
            if Combat.stalemate(self) then self:add_action("Skip stalemated combat","combat_skip",{instruction=combat.owner}) end
            for _,choice in ipairs(self.flee_choices[combat.group] or {}) do self:add_action(plain(choice),"combat_flee",{instruction=combat.owner,destination=choice.attr}) end
            return {title="Combat",text=log,actions=self.actions,image=self.image}
        end
        if self.state.progress then for _,enemy in ipairs(combat.opponents) do self.state.progress.completed[enemy.path]=true end end
        self.state.combat=nil; self:resume_section()
        local death_result=self:route_death(); if death_result then return death_result end
        return {title="Combat result",text=table.concat(self.text).."\n\n"..log,actions=self.actions,image=self.image}
    elseif action.kind=="combat_skip" then
        local combat=self.state.combat
        if not combat or not Combat.stalemate(self) then return nil,"Combat is not stalemated." end
        if self.state.progress then for _,enemy in ipairs(combat.opponents) do self.state.progress.completed[enemy.path]=true end end
        self.state.combat=nil; self.actions={}; self:resume_section()
        local death_result=self:route_death(); if death_result then return death_result end
        self.text[#self.text+1]="\n\nNeither side can harm the other; combat is skipped."
        return {title="Combat skipped",text=table.concat(self.text),actions=self.actions,image=self.image}
    elseif action.kind=="combat_flee" then
        local combat=self.state.combat; Combat.flee(self)
        self.actions={}; if self.state.progress then for _,enemy in ipairs(combat.opponents) do self.state.progress.completed[enemy.path]=true end end
        if action.data.destination then return self:load(action.data.destination.book or self.state.book,action.data.destination.section) end
        self:resume_section(); return {title="Fled combat",text=table.concat(self.text),actions=self.actions,image=self.image}
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
            self.state.shards=self.state.shards-cost; State.add_item(self.state,item_from(a,action.data.node))
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

function Game:choose(index)
    local action=self.actions[index]
    if not action then return nil,"Invalid choice" end
    self.preview_text=nil
    local metadata={kind=action.kind,instruction=action.instruction}
    local node=type(action.data)=="table" and (action.data.node or (action.data.attr and action.data)) or nil
    if node and node.attr then metadata.attr=State.copy(node.attr); metadata.ability=action.data.ability; metadata.node_name=node.name end
    if action.kind=="random" or action.kind=="fight" then metadata.attr=State.copy(action.data.attr or {}) end
    self.journal:begin(action.kind,metadata)
    local progress=self.state.progress
    local resolves={skillcheck=true,random=true,fight=true,training=true,["return"]=true,rest=true,mutate=true,group=true,
        resurrection=true,resurrect=true,leave_market=true,["goto"]=true}
    -- Starting a round-based fight is not resolution; its grouped instructions
    -- are marked only after victory, defeat, flee, or an explicit stalemate skip.
    if resolves[action.kind] and action.kind~="fight" and progress and action.instruction then progress.completed[action.instruction]=true end
    self.state.pending=nil
    local ok,result,err=pcall(self._choose,self,index)
    if not ok or not result then
        self.journal:rollback()
        return nil,ok and err or result
    end
    if not self.state.pending then
        self.state.pending={schema=1,kind="interaction",book=self.state.book,section=self.state.section,
            instruction=action.instruction,resume_kind=action.kind,actions={}}
    end
    self.journal:commit()
    return result,err
end

return Game

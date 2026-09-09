local root=assert(arg[1],"repository root argument required")
package.path=root.."/plugins/jafl.koplugin/?.lua;"..root.."/plugins/jafl.koplugin/?/init.lua;"..root.."/tests/lua/?.lua;"..package.path

local Game=require("core/game")
local Inventory=require("core/inventory")
local State=require("core/state")
local oracle=require("java_oracle")

local function equal(actual,expected,label)
    if actual~=expected then error(string.format("%s: expected %s, got %s",label,tostring(expected),tostring(actual)),2) end
end

local function action_index(game,kind)
    for index,action in ipairs(game.actions) do if action.kind==kind then return index end end
    error("missing action "..kind)
end

local function catalog(fixture)
    local path=root.."/tests/lua/fixtures/"..fixture
    return {
        books={ ["1"]={title="Oracle",installed=true,properties={Death="dead"}} },
        section_path=function(_,book,section)
            if tostring(book)~="1" or section~="test" then return nil,"unknown oracle section" end
            return path
        end,
        asset_path=function() return nil end,
    }
end

local function ready_state()
    local state=State.new(); state.book="1"; state.section="test"; state.profession="Wayfarer"
    state.abilities={Charisma=1,Combat=0,Magic=1,Sanctity=1,Scouting=2,Thievery=1}
    state.models.stats.natural=State.copy(state.abilities)
    state.stamina=20; state.max_stamina=20; state.rank=1
    return state
end

local function forced_random()
    local expected=oracle.forced_random; local state=ready_state()
    local game=Game.new(catalog(expected.fixture),state,function() return 4 end)
    assert(game:load("1","test")); equal(state.variables.marker,expected.before.marker,"random pre-state")
    equal(game.actions[1].kind,expected.before.action,"random blocker")

    local restored=State.copy(state); local resumed=Game.new(catalog(expected.fixture),restored,function() return 4 end)
    assert(resumed:load("1","test")); equal(restored.variables.marker,expected.restored.marker,"random restored marker")
    equal(resumed.actions[1].kind,expected.restored.action,"random restored blocker")
    assert(resumed:choose(action_index(resumed,"random")))
    equal(restored.variables.roll,expected.after.roll,"random result")
    equal(restored.variables.marker,expected.after.marker,"random continuation")
end

local function blocking_combat_hook()
    local expected=oracle.blocking_combat_hook; local state=ready_state()
    local game=Game.new(catalog(expected.fixture),state,function() return 1 end)
    assert(game:load("1","test")); assert(game:choose(action_index(game,"fight")))
    assert(game:choose(action_index(game,"combat_attack")))
    equal(game.actions[1].kind,expected.blocked_action,"hook blocker")
    equal(state.execution.frames[1].kind,expected.frame_kind,"serialized hook frame")
    equal(state.combat.phase,expected.frame_phase,"serialized combat phase")

    local blocked=State.copy(state); local restored=Game.new(catalog(expected.fixture),blocked,function() return 1 end)
    assert(restored:load("1","test")); equal(restored.actions[1].kind,expected.blocked_action,"restored hook blocker")
    assert(restored:choose(action_index(restored,"skillcheck")))
    equal(restored.actions[#restored.actions].kind,expected.completed_action,"completed hook continuation")

    local completed=State.copy(blocked); local again=Game.new(catalog(expected.fixture),completed,function() return 1 end)
    assert(again:load("1","test")); equal(again.actions[1].kind,expected.completed_action,"restored completed hook")
    assert(again:choose(action_index(again,"combat_continue")))
    equal(again.actions[1].kind,expected.resumed_action,"resumed combat action")
end

forced_random()
blocking_combat_hook()

local function effects_and_afflictions()
    local state=ready_state(); state.abilities.Combat=6; state.models.stats.natural.Combat=6
    state.items={State.new_item{id="ordered",name="ordered charm",effects={
        State.new_effect{kind="aura",ability="Combat",operation="add",value=2},
        State.new_effect{kind="aura",ability="Combat",operation="divide",value=2},
        State.new_effect{kind="aura",ability="Combat",operation="target",value=10},
    }}}
    equal(Inventory.ability(state,"Combat"),7,"Java target/divide/add ordering")
    Inventory.bless(state,{blessing="disease"})
    local node={attr={name="ague"},children={}}
    local applied=Inventory.afflict(state,"disease",node)
    equal(applied,false,"disease blessing prevents affliction")
    equal(state.blessings.disease,nil,"non-permanent immunity is consumed")
    assert(Inventory.afflict(state,"disease",node)); assert(state.diseases.ague)
    assert(Inventory.lift(state,"disease","ague")); equal(state.diseases.ague,nil,"structured affliction lift")
end

local function embedded_use_program()
    local state=ready_state()
    state.items={State.new_item{id="potion",name="oracle draught",effects={State.new_effect{
        kind="use",ability="Combat",uses=1,program={{name="set",_path="use.1",attr={var="used",value="9"},children={}}},
    }}}}
    local game=Game.new(catalog("forced_random.xml"),state,function() return 4 end)
    assert(game:load("1","test")); assert(game:choose(action_index(game,"use_item")))
    equal(state.variables.used,9,"embedded use program")
    equal(#state.items,0,"disposable exhausted use item")
    equal(state.models.potions.Combat,1,"ability potion bonus queued")
end

effects_and_afflictions()
embedded_use_program()
io.write("Lua Java-oracle scenarios passed\n")

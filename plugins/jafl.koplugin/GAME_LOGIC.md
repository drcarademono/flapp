# KOReader game-logic implementation

The Java application remains the reference implementation. The KOReader engine
uses the same three-stage model:

1. Parse section XML while preserving mixed-content order.
2. Execute XML nodes in document order until a blocking action is reached.
3. Resume immediately after that action when the player resolves it.

`core/game.lua` implements stage 2 with a coroutine. This is the Lua equivalent
of Java's `ExecutableRunner`: it prevents text, state changes, and destinations
after a fight or forced destination from being processed too early.

The pause check compares the currently running coroutine directly with the
section runner. It deliberately does not interpret the optional second return
value of `coroutine.running()`, because that value differs between KOReader's
LuaJIT compatibility modes. This guarantees that a forced `goto` actually
suspends section execution on supported KOReader builds.

## Ordered section execution

- A fight pauses the section at its exact XML position.
- Winning or losing resumes at the node immediately following the fight.
- A normal `goto` is usable only while the adventurer is alive. A `dead="t"`
  destination is usable only while dead, matching `GotoNode.canUse()`.
- A usable forced destination pauses execution. Therefore, in section 570, an
  adventurer who wins stops at section 148. An adventurer who dies cannot use
  section 148, continues through the authored recovery effects, and then stops
  at section 195.
- State changes following an unresolved fight are not applied in advance.

## Combat rules

The following behavior is taken from `FightNode.java`:

- Player attack: roll `attackDice` six-sided dice (two by default), add COMBAT,
  and subtract enemy Defence. A positive remainder is the damage inflicted.
- Enemy attack: roll two six-sided dice, add enemy COMBAT, and subtract player
  Defence. A positive remainder is the damage inflicted.
- The enemy makes `attacks` attacks after each player attack (one by default).
- `playerFirst="f"` gives the enemy the opening attack.
- `flee` is an enemy-Stamina victory threshold. Zero is always a victory
  threshold when no explicit value is supplied.
- `playerDefence` can name a section variable or an ability used in place of
  normal Defence.
- `attackDice`, `preDamage`, `staminaLost`, and `abilityDamaged` are honored.
- The XML reader normalizes attribute keys to lower case. Combat therefore reads
  those properties internally as `attackdice`, `predamage`, `staminalost`, and
  `abilitydamaged` (and similarly for `playerFirst`/`playerDefence`).
- Rolls, Defence targets, damage, misses, and remaining enemy Stamina are shown
  in the result log.

## State effects used by combat continuations

- `lose staminato="N"` sets current Stamina to `N`, bounded by zero and maximum
  Stamina. This is distinct from losing N Stamina.
- `lose shards="*"` and `lose gold="*"` remove all money.
- Symbolic numeric values first resolve against section variables and then
  character abilities. A leading minus sign negates the resolved value.

## User-interface flow

Combat results and the continuation are rendered together. The engine resumes
the section before returning the result to `GameView`, so the button table
contains only the destination or interaction which is valid for the resulting
alive/dead state. There is no intermediate, context-free “Adventure continues”
screen and no display of mutually exclusive win and loss destinations.

The plugin autosaves after rendering the resulting screen, including all combat
damage and post-combat recovery effects which executed before the next blocking
action.

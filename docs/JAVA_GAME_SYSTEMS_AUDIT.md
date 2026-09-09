# Java game systems audit and KOReader parity plan

- **Audit date:** 2026-09-09
- **Reference implementation:** the Java sources under `flands/`
- **Port reviewed:** `plugins/jafl.koplugin/`

## 1. Scope and method

This is a static audit of the game rules, state model, XML interpreter, and
player-visible game facilities in the Java application. Swing layout and other
pure presentation code are mentioned only where they expose a game system. The
audit compared:

1. the model classes (`Adventurer`, items, ships, blessings, curses, effects,
   codewords, flags, rules, and addresses);
2. every Java `*Node` implementation and the node factory in `Node.java`;
3. execution, navigation, undo, save/load, and death handling;
4. the tags and attributes actually used by books 1–6; and
5. the Lua state, interpreter, save layer, catalog, and UI, plus the existing
   plugin tests and documentation.

The corpus contains **4,446 `<section>` roots and 69 distinct element names**.
The most important executable counts are 4,276 choices, 3,460 gotos, 1,544
losses, 1,424 conditions, 867 ticks, 795 outcome tables, 595 random rolls, 488
difficulty checks, 212 fights, 178 trades, 148 rests, 93 markets, 62 training
actions, 56 caches, 25 transfers, 16 returns, 9 rerolls, 7 persistent extra
choices, and 2 loops. Counts indicate exposure, not correctness: a single rare
construct can gate a valid route.

### Status terminology

| Status | Meaning |
| --- | --- |
| **Implemented** | The core Java behavior is represented in Lua; remaining differences are mainly presentation. |
| **Partial** | A useful subset exists, but reachable Java behavior or attributes are missing or materially different. |
| **Missing** | State may have a placeholder, but the Java system cannot actually be used with equivalent semantics. |
| **Different by design** | The port intentionally substitutes a KOReader-native interaction without changing the rule result. |

This audit does **not** treat the broad feature list in
`plugins/jafl.koplugin/GAME_LOGIC.md` as proof of parity. Several listed systems
have only a simplified implementation.

## 2. Java execution model

The Java content engine is a small stateful programming language, not simply a
hypertext reader:

- SAX parsing creates a specialized `Node` tree and a styled document.
- Executable nodes register with an `ExecutableGrouper` in document order.
- `ExecutableRunner` advances until an action blocks. Activating that action
  calls `continueExecution`, so later mutations do not occur early.
- `GroupNode`, `IfNode`, `WhileNode`, outcome nodes, and fight hook nodes nest or
  redirect execution while preserving that continuation contract.
- Action nodes listen to changing character state and enable/disable themselves.
- Many roll actions create undo records. A reroll undoes the prior mutation and
  repeats the actual preceding roll, rather than making a fresh generic roll.
- The document and executable state are saved so a game can resume within a
  section, including unresolved interactions and combats.

Lua's ordered coroutine runner is a sound equivalent for the basic pause/resume
contract. Its render-ahead pass also preserves prose around blockers. It is not
yet an equivalent implementation of nested groups, roll undo, or serialized
continuations.

## 3. System-by-system comparison

### 3.1 Character creation, statistics, and derived values — **Partial**

**Java behavior**

- Six professions and six base abilities: CHARISMA, COMBAT, MAGIC, SANCTITY,
  SCOUTING, and THIEVERY.
- Rank, current/maximum Stamina, and Defence are additional abilities. Defence
  is derived from COMBAT, Rank, armour, blessings, and effects rather than being
  a permanently initialized scalar.
- Profession templates are loaded from each book's `Adventurers.xml` and named
  adventurer XML, with gender and authored starting possessions.
- Abilities support natural/current values, caps, temporary adjustments,
  dividers, fixed targets, and effect ordering.
- Character sheet fields can be edited through `<field>` nodes.

**KOReader now**

- Holds all six base abilities, Rank, Stamina, a Defence field, profession,
  name, and gender.
- Offers installed books and reads each `New.xml`, but recognizes six hard-coded
  destination names to construct a character. It assigns hard-coded scores,
  Stamina, Shards, armour, weapon, and map.
- Applies simple bounded numeric changes and training increases.
- Renders `<field>` text but does not implement editable character fields.

**Still needed**

- Load character templates and starting equipment from book data; remove the
  dependency on the six English section names.
- Implement derived Defence and recalculate it whenever COMBAT, Rank, armour,
  blessings, curses, or effects change.
- Model natural versus modified ability values and the full Java ability-effect
  pipeline. The current cached `state.defence` becomes stale after advancement
  or equipment changes.
- Implement field editing/selection where the authored new-character documents
  require it.
- Confirm Java's rank/Stamina progression. Lua currently increases maximum
  Stamina by the same amount as every Rank gain, which is only one narrow path
  through Java's adjustment code.

### 3.2 Conditions, expressions, variables, and flow control — **Partial**

**Java behavior**

- Conditions cover codeword AND/OR expressions, titles, god, profession,
  gender, items and item types, quantity, bonus and tags, money/cache balance,
  ticks, variables and comparisons, flags, blessings, curses/disease/poison,
  resurrection, installed books, abilities, death, rules, and negation.
- `Expression`/`DiceExpression` resolve literals, variables, abilities, dice,
  and arithmetic used by node attributes.
- `<set>` supports modifiers and item-derived values; `<adjust>` can operate on
  abilities, crew, ships, codewords, gods, profession, items, titles, and values.
- `<while>` repeatedly executes its child executable sequence. `<group>` is a
  resumable compound action and can be forced or optional.

**KOReader now**

- Implements the common boolean predicates, simple symbolic values, `NdS+K`,
  numeric variables, comparisons, negation, and ordered if/elseif/else chains.
- Implements simple set, numeric adjustment, and a guarded variable loop.

**Still needed**

- Full expression grammar and Java resolution/rounding rules. Lua accepts only
  one symbol or one dice expression; unsupported expressions silently become
  zero.
- Rule-extension predicates (`ActiveRuleset`), item-group/filter semantics, and
  exact wildcard/list comparison behavior for every condition type.
- `<set modifier>`, item/tag/cache/dock setters, and the non-numeric `<adjust>`
  variants. These attributes occur hundreds of times (especially crew).
- Real `<group>` semantics. Lua currently treats it as a presentation container,
  so forced grouped payments/actions do not block or resume as one unit.
- Java-compatible `<while>` execution and continuation. Lua only tests a
  nonzero variable, caps at 100 iterations, and cannot correctly suspend and
  resume arbitrary blocking children.
- Report unsupported expressions and attributes instead of defaulting to a
  plausible but incorrect result.

### 3.3 Navigation, history, books, and rules — **Partial**

**Java behavior**

- Optional/forced gotos support cross-book addresses, living/dead routes,
  payments, visits/revisits, sailing/docking side effects, and book availability.
- Return nodes use section history. Books contribute temporary rules, map and
  death-section metadata. Section tags activate persistent extra choices.
- `SectionViewNode` supports random or sequential section browsing (primarily a
  debugging/game-book utility).

**KOReader now**

- Supports local/cross-book goto, dead-state gating, basic Shard/item payment,
  a history stack, return, installed-book checks, and a boolean `at_sea` marker.
- Catalogs maps and illustrations.

**Still needed**

- Visit/revisit rules and correct history semantics (including destinations
  that should not be revisited or returned through).
- Complete `price`, `currency`, `pay`, `item`, `tags`, sail, dock, and ship
  transition semantics. Current goto payment removes at most one named item and
  money, regardless of the Java action rules.
- Book fixed/temporary rules and rule-dependent mechanics.
- Death menu routing to each book's configured death section when no authored
  dead goto is present.
- Persistent `<extrachoice>` acquisition/removal and activation by `atbook` /
  `atsection` or section tag. Lua only renders its default text.
- `<sectionview>` behavior, if that Java utility is in product scope.

### 3.4 Items, equipment, item groups, and effects — **Partial**

**Java behavior**

- Items have quantity, value, type (ordinary item/weapon/armour/tool), bonus,
  tags, group, equipped/used state, and chained effects.
- Weapon and armour selection changes combat statistics. Tools modify the named
  ability. Item groups, include/exclude filters, replacements, buy tags, add/remove
  tags, `using`, and `itemat` affect matching and loss choices.
- Effects may be aura, wielded, tool, or limited-use effects; they add, divide,
  or target abilities. `UseEffect` executes embedded gain/loss/tick logic and
  tracks uses.
- Some losses require the player to choose among eligible possessions rather
  than deleting an arbitrary match.

**KOReader now**

- Stores name, quantity, bonus, a few type booleans, and tags; supports basic
  existence checks and add/remove operations.
- Reads effect children only to build display labels. Affliction effects apply
  a small direct ability subset.

**Still needed**

- Equipped weapon/armour state, derived weapon/armour/tool effects, item-use
  actions and use counts, aura/wielded/tool ordering, division and fixed-target
  effects.
- Structured tags and exact group/include/exclude matching. Current substring
  matching can give false positives.
- `replace`, `buytags`, `addtag`, `removetag`, `effect`, `using`, `itemat`,
  `quantity`, and group semantics.
- Interactive choice for ambiguous loss/transfer; preservation of `kept` items;
  chance-based and fatal loss rules.
- Consistent quantity merging/splitting. Lua generally appends duplicate item
  rows and direct sale removes by name only.

### 3.5 Money and caches — **Partial**

**Java behavior**

- Carried Shards and named money caches can be tested and adjusted.
- Money caches enforce maximums, allowed withdrawal multiples, and withdrawal
  charges, and permit interactive deposit/withdrawal.
- Item caches enforce item filters/limits, freeze while unavailable, and permit
  interactive deposit/withdrawal.
- `AdjustMoneyNode` supports named caches and multiplication.
- Transfers move selected/all money or matching possessions between character,
  caches, and null destinations, with limits and blocking choice where needed.

**KOReader now**

- Stores caches, tests cached money in a condition, supports narrow all-money
  and broad item transfer paths, and displays cache contents.
- Cache actions do not offer deposits or withdrawals.

**Still needed**

- Interactive cache operations and all maximum, multiple, charge, freeze,
  filter, and item-limit constraints.
- Correct unnamed-cache behavior used by Java, and exact cache lifetime/scope.
- `adjustmoney` cache targeting and multiplication (all 89 corpus uses specify
  `multiply`; most also specify a cache name).
- Attribute-complete, directional transfer with filtering, price, limit, and
  continuation semantics. Current source-cache transfer moves every item even
  when a filter is authored.

### 3.6 Ships, crew, cargo, sailing, and maritime trade — **Missing**

**Java behavior**

- `Ship` models type, capacity, crew quality, cargo types/units, location, and
  combat-relevant properties. `ShipList` manages multiple ships and the active
  ship.
- Tick/lose/adjust/set/trade nodes buy, sell, select, upgrade, damage, and move
  ships; change crew; and buy/sell/load/unload cargo.
- Trade prices and availability respond to ship capacity, cargo, crew, flags,
  quantities, and authored trade events.

**KOReader now**

- Has an unused `ships = {}` state slot and sets `at_sea` for a sailing goto.
- Generic market handling incorrectly treats ship/cargo/crew transactions as
  ordinary named items or empty names.

**Still needed**

- The entire ship model and sheet, active-ship selection/swap, capacity and
  location rules, crew quality, cargo inventory, sailing/docking state, and
  ship persistence.
- All `ship`, `crew`, `cargo`, `initialcrew`, `dock`, and related set/adjust/
  tick/lose/buy/sell semantics. This is high priority: the corpus contains 178
  `<trade>` nodes, 119 trade cargo attributes, 59 trade ship attributes, and
  hundreds of crew adjustments.

### 3.7 Markets and trade events — **Partial**

**Java behavior**

- `<market>` builds a repeatable live table. Entries re-enable as money,
  inventory, flags, and capacity change. Buying/selling respects quantity,
  filters, tags, replacements, and item effects.
- `<trade>` handles ships, cargo, items, crew upgrades, initial crew, quantities,
  and distinct buy/sell pricing.
- `<tradeevent>` automatically triggers the matching transaction-side children.
  `<sold>` participates in transaction results.

**KOReader now**

- Provides a separate market screen, repeatable basic item purchases/sales, an
  affordability/ownership check, and a correct explicit “Leave market” resume
  action. The separate screen is a reasonable design adaptation.

**Still needed**

- Do not expose unusable entries as actionable errors; recompute availability
  from all Java flags and conditions.
- Correct prices: corpus item nodes use `buy`/`sell`, while trade children mostly
  use `shards`; transaction direction and quantity need exact handling.
- Ship/cargo/crew trade, multi-quantity transactions, replacements, tags,
  effects, flags, and conditional price adjustments.
- Execute `<tradeevent>` and `<sold>` hooks. Lua currently hides default child
  text but otherwise walks trade-event children as ordinary section logic,
  potentially applying transaction effects without a transaction.

### 3.8 Gain, loss, ticks, rest, and payment — **Partial**

**Java behavior**

- Gain/tick/loss nodes cover abilities (including all/single), Stamina and
  maximum Stamina, Rank, Shards/caches, codewords, titles, gods, flags,
  blessings, curses/disease/poison, resurrection, items/equipment, effects,
  ships, crew, and cargo.
- They can be hidden, forced/optional, priced, grouped, chance-based, conditional
  on flags/items/tags, and undoable after a roll. `staminato` sets rather than
  subtracts. Fatal damage and injury blessings interact with death.
- Rest permits full or fixed healing, optionally charging Shards; missing
  Stamina or Shards attributes have meaningful “complete/free” defaults.

**KOReader now**

- Implements common scalar/set mutations, wildcard money/item loss, and bounded
  current Stamina. `staminato` is correctly distinct from Stamina loss.
- Rest is immediate fixed healing and payment.

**Still needed**

- Optional and forced action semantics. Lua applies nearly every tick/gain/loss
  immediately and ignores most `force`, `price`, `chance`, `fatal`, `special`,
  `permanent`, `addbonus`, title-pattern/value/adjustment, cache, and selection
  behavior.
- Maximum-Stamina and Defence mutations, all/single ability choice, blessing
  consumption/prevention, injury/death rules, and undo integration.
- Ship/crew/cargo forms and effect/tag/equipped-item forms.
- Java rest defaults, affordability gating, full-heal behavior, action blocking,
  and undo. In Lua `<rest stamina="...">` with no `shards` works, but an empty
  Stamina attribute path does not mean full healing.

### 3.9 Blessings, gods, curses, diseases, and poisons — **Partial**

**Java behavior**

- Blessings are typed: ability, storm, Defence, injury, disease/poison immunity,
  luck, travel, and divine wrath. They may be permanent or consumed when used.
- Gods and items can contribute chained effects.
- Curses/diseases/poisons have type, name, cumulative behavior, a lift prompt,
  attached item, and one or more effects. Duplicate non-cumulative afflictions
  and lifting/removal are handled distinctly.

**KOReader now**

- Stores names in maps and can add/remove them. Afflictions apply direct add or
  target effects once at acquisition.

**Still needed**

- Typed blessing behavior in rolls, combat, travel, injury, and affliction
  prevention, including consumption/permanence and wildcard matching.
- Active/reversible effects. Removing a Lua curse does not undo the ability
  modification made when it was acquired.
- Cumulative afflictions, attached items, lift questions/actions, divide effects,
  duplicate rules, and serialization of full objects.
- God/item effects and their ordering with curses and blessings.

### 3.10 Dice, random tables, difficulty/Rank checks, training, and reroll — **Partial**

**Java behavior**

- Random nodes support dice count/type, variables, one-use flags, adjustments,
  optional versus forced interaction, and undo.
- Difficulty checks use two dice plus an ability and adjustments against a
  difficulty. Multiple abilities give a choice. Rank checks have their own
  dice/add comparison. Success/failure and numeric outcomes may contain
  executable continuations or destinations.
- Training raises the chosen/authored ability under its roll rule and supports
  variable/add/dice attributes and undo.
- `<reroll>` targets the prior `Roller`: undo the effects caused by that roll and
  invoke the same action again.

**KOReader now**

- Implements the main dice formulas, ranges, stored values, outcomes, multiple
  ability buttons, optional/forced checks, adjustments, flags, and training.
- Preserves execution order around rolls.

**Still needed**

- Roll type/modifier variants and precise adjustment eligibility. Lua only
  executes `<adjust>` children with a condition and adds `amount`/`value`.
- Correct success boundary and result-value parity should be locked down with
  Java fixtures, especially Rank and difficulty result variables.
- Training ability choice (`ability="?"`), adjustment/effect/blessing rules,
  caps, and undo.
- A real last-roll/undo record. Lua maps reroll to the generic `random` handler
  with the `<reroll>` node, so it rolls two dice, does not repeat a difficulty,
  Rank, training, combat attack, or loss roll, and does not undo prior effects.
- Serialize pending rolls and branches so reload does not replay or skip logic.

### 3.11 Combat — **Partial**

**Java behavior**

- Combat is interactive by round: player attack, one or more enemy attacks,
  undo/reroll, and authored flee/skip choices.
- Supports grouped/multiple opponents, attack dice, player-first control,
  alternate player Defence, alternate damaged ability, pre-damage, enemy flee
  threshold, Stamina-lost variables, global/modifier attack bonuses, cached
  combat values, and inability to win/lose edge cases.
- Paired `<fightround>`, `<fightdamage>`, and `<flee>` subprograms execute at
  precise pre-fight/round/damage/flee points and can themselves block. Damage
  hooks may replace normal damage, not merely supplement it.
- Blessings (Defence, injury, luck, wrath), effects, equipment, and undo interact
  with attack/defence rolls and damage.

**KOReader now**

- Resolves a whole fight in one action using the core attack/damage formulas.
  It supports common attack count/dice/first/Defence/damaged-ability/pre-damage/
  flee attributes, logs rolls, and resumes post-fight execution correctly.
- Pairs hook nodes by ordinal position and implements a narrow subset of hook
  mutations.

**Still needed**

- Round-by-round UI and saved combat state, player flee/skip choices, reroll and
  undo, and fights that cannot progress. The current 100-round cutoff silently
  declares defeat even if both sides are unable to damage each other.
- Grouped fights (12 corpus fight nodes), opponent switching, and the Java
  group-wide combat lifecycle.
- Execute arbitrary hook subprograms with correct timing, conditions, blockers,
  pre-fight status, and replacement semantics. Ordinal global pairing is not
  sufficient when ownership/group structure differs.
- `usecache`, `modifiers`, attack bonus, effects/equipment, and all blessing
  interactions.
- Exact death/fatal/injury behavior and post-combat undo state.

### 3.12 Resurrection and death — **Partial**

**Java behavior**

- A resurrection arrangement stores destination, book, price, god, flags, and
  supplemental rules. On death it is conditionally offered/consumed and routes
  the character appropriately; books also define a default death section.
- Death-aware destinations and loss nodes coordinate to avoid continuing a
  living-only path after fatal damage.

**KOReader now**

- Stores one resurrection attribute table, offers arrange/use actions, clears it,
  raises Stamina to at least one, charges Shards, and navigates.
- Implements alive/dead gating for gotos and choices.

**Still needed**

- God/flag/supplemental eligibility, exact payment and restoration rules,
  replacement/selection of arrangements, default book death route, and death
  menu behavior.
- Correct interaction with fatal losses, injury blessings, curses, ships, and
  pending combat.

### 3.13 Persistent extra choices — **Missing**

Java lets a section grant or remove a keyed destination that later appears only
at a configured address or in sections with a matching tag. The list is saved.
KOReader has no extra-choice collection, activation check, removal, menu action,
or persistence. All seven corpus nodes need this system; treating the tag as
ordinary text is not equivalent.

### 3.14 Save/load, autosave, continuation, and hardcore mode — **Partial**

**Java behavior**

- Saves the character and related collections, current section/node execution
  properties, extra choices, ships, caches, roll/fight state, and other active
  interaction data. Loading rehydrates listeners/effects and resumes the exact
  actionable state.
- Undo state protects roll-driven changes. Hardcore/rule settings affect play.

**KOReader now**

- Uses `LuaSettings` with a schema check and atomicity delegated to KOReader.
  The UI autosaves after screens. Base state collections are serializable.
- `state.pending` records only `{kind="section", book, section}`. Loading a save
  reloads the section from its beginning; the coroutine, action, roll, market,
  cache, and combat state are not serialized. A reload can therefore repeat
  mutations or lose an unresolved interaction.
- `hardcore` exists only as an unused boolean.

**Still needed**

- A versioned continuation/checkpoint model that safely restores the exact
  pending interaction without replaying earlier effects.
- Persist full ships, item/effect state, afflictions, resurrection, extra choices,
  cache constraints, visited state, active rules, derived-stat inputs, last-roll
  undo data, and in-progress combat.
- Schema migrations, save corruption/recovery behavior, and Java import decision.
- Implement or remove exposed hardcore/rule controls until semantics exist.

### 3.15 Presentation-linked game facilities — **Partial**

- **Character sheet:** KOReader displays core stats/inventory, but not complete
  effects, typed blessings/afflictions, equipped items, persistent choices, or
  editing/use actions.
- **Ship sheet:** missing.
- **Maps and illustrations:** paths and display exist; Java opens illustrations
  separately while KOReader embeds them, an acceptable design difference.
- **Rules/help:** content exists, but active optional rules are not connected to
  game state.
- **Action pagination:** implemented as a KOReader-native accommodation.
- **Styled text/tables/boxes:** simplified intentionally; see the separate text
  parsing audit. These are not game-rule blockers unless styling communicates
  enabled/disabled state or hides a transaction choice.

## 4. XML vocabulary coverage summary

| Area | Java elements | KOReader status |
| --- | --- | --- |
| Containers/presentation | `section`, `p`, `h1`–`h4`, `b`, `i`, `table`, `tr`, `td`, `header`, `text`, `box`, `choices`, `abilities`, `items` | Parsed/rendered in simplified form. |
| Branching/navigation | `if`, `elseif`, `else`, `choice`, `goto`, `return`, `while`, `group`, `sectionview` | Common branches/gotos/return work; group/while partial; sectionview missing. |
| Rolls | `random`, `difficulty`, `rankcheck`, `outcomes`, `outcome`, `success`, `failure`, `adjust`, `reroll`, `training` | Main checks work; modifiers, undo/reroll, and some continuation cases remain. |
| State changes | `set`, `tick`, `gain`, `lose`, `rest`, `price` | Common scalar changes only; optional/interactive and many attribute forms missing. |
| Items/effects | `item`, `weapon`, `armour`, `tool`, `effect`, `include`, `exclude`, `itemcache`, `moneycache`, `transfer` | Basic inventory and narrow transfer only; equipment/effects/filter/cache UI missing. |
| Afflictions/death | `curse`, `disease`, `poison`, `resurrection` | Name storage/basic resurrection only. |
| Combat | `fight`, `fightround`, `fightdamage`, `flee` | Automated basic fight; grouped/interactive/hooks/blessings/undo partial. |
| Commerce/ships | `market`, `trade`, `buy`, `sell`, `sold`, `tradeevent`, `adjustmoney` | Basic item market only; ship/cargo/crew/events/cache money math missing. |
| Persistent/UI actions | `extrachoice`, `field`, `image` | Image works; extra choice and field behavior missing. |
| Character templates | `adventurers`, `adventurer`, `profession`, `rank`, `stamina`, `gold` | Bypassed by hard-coded starter construction. |

`exclude`, `include`, `sold`, `price`, `sectionview`, `field`, and character
template elements deserve explicit handlers even though generic recursion makes
them appear “accepted.” Silently walking an element is not proof its Java
semantics have been implemented.

## 5. Priority plan for parity work

No implementation is part of this audit. The recommended order minimizes the
risk of building more rules on an inadequate state/save model.

### Phase 0 — executable compatibility inventory

1. Generate a checked-in machine-readable tag/attribute census for books 1–6.
2. Make the interpreter fail loudly (in a future implementation change) for
   executable tags/attributes not in a declared support matrix.
3. Build small Java-oracle fixtures for each executable node, including blocked
   continuation and save/reload points.

### Phase 1 — state and persistence foundation

1. Define structured models for abilities/derived stats, item instances/effects,
   typed blessings/afflictions, ships/cargo, rules, visits, extra choices, and
   caches.
2. Design versioned serialization and migrations.
3. Replace coroutine-only progress with serializable instruction/checkpoint
   identity; add exact resume tests after every blocker.
4. Add deterministic RNG/roll records and reversible mutation transactions.

### Phase 2 — expressions and generic actions

1. Port `Expression`, condition/flag matching, and all set/adjust attributes.
2. Port the generic gain/tick/lose/payment engine, including optional choices,
   grouping, filters, selection, fatality, blessings, and undo.
3. Implement resumable group and loop semantics.
4. Implement Java rest rules and persistent extra choices.

### Phase 3 — inventory, effects, afflictions, and caches

1. Port item groups/tags/equipping and `EffectSet` ordering.
2. Port use effects and item/curse/god effect activation/deactivation.
3. Port typed blessings and cumulative afflictions.
4. Add full item/money cache screens, limits, charges, and transfers.

### Phase 4 — ships and economy

1. Implement ship/crew/cargo models and ship sheet.
2. Port ship-aware set/adjust/tick/lose/transfer actions.
3. Port trade buy/sell, capacity, pricing, trade events, and sold hooks.
4. Test every maritime transition across books.

### Phase 5 — dice and combat parity

1. Finish check modifiers, training selection, last-roll undo, and true reroll.
2. Replace whole-fight simulation with a serializable round state machine.
3. Add grouped fights, flee/skip, hook subprograms, effects/equipment/blessings,
   inability-to-progress handling, and exact death routing.

### Phase 6 — data-driven creation, rules, and completeness gate

1. Parse the book character templates and remove hard-coded starters.
2. Activate fixed/temporary optional rules and finish visit/revisit semantics.
3. Decide whether section browsing and editable fields are player scope or
   documented Java-only tools.
4. Run automated reachability/parity coverage over all six books. Do not claim
   full playability while any reachable executable construct falls through a
   generic container path.

## 6. Highest-risk current mismatches

These should be treated as correctness defects rather than polish:

1. **Save replay:** reloading restarts the section and can duplicate earlier
   state changes.
2. **Ships/trade absent:** a major cross-book progression system has no model.
3. **Effects absent:** displayed ability/Defence and rule checks can differ after
   acquiring equipment, blessings, gods, or afflictions.
4. **Generic mutation is too narrow:** common crew/cache/title/item variants are
   ignored while execution continues.
5. **Reroll is not reroll:** it neither repeats nor undoes the prior roll.
6. **Combat hooks/groups are approximated:** rare authored fight mechanics can
   resolve to a different outcome.
7. **Extra choices absent:** acquired routes never become available later.
8. **Silent fallback:** unknown executable semantics are frequently recursed or
   ignored rather than surfaced.

## 7. Java-reference caveats

The Java source itself contains acknowledged TODOs and ambiguous edge cases
(notably selected equipment, magic armour effects, some ship loss/death paths,
tick undo, grouped undo, and ability-all undo). Parity work should therefore:

- reproduce clear, observable Java behavior;
- preserve known content-required special cases;
- write a decision record where Java is incomplete or obviously defective; and
- avoid accidentally presenting a Lua simplification as confirmed Java parity.

The target should be **content-compatible and explicitly specified**, with the
Java runtime serving as an oracle until a fixture documents an intentional fix.

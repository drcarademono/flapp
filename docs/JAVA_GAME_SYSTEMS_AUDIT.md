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
- `<field>` nodes display a named numeric value in a non-editable Swing field.

**KOReader now**

- Holds all six base abilities, Rank, Stamina, a Defence field, profession,
  name, and gender.
- Offers installed books, reads each `New.xml`, and loads that book's
  `Adventurers.xml` profession scores, named/gendered starters, Rank, Stamina,
  Shards, armour, profession weapon, and common possessions.
- Applies simple bounded numeric changes and training increases.
- Renders `<field>` as its label plus the current named variable value, matching
  the read-only Java control without importing desktop editing UI.

**Still needed**

- Implement derived Defence and recalculate it whenever COMBAT, Rank, armour,
  blessings, curses, or effects change.
- Model natural versus modified ability values and the full Java ability-effect
  pipeline. The current cached `state.defence` becomes stale after advancement
  or equipment changes.
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

- Extend the expression resolver as model-specific values come online. The Java
  arithmetic grammar and core identifiers are implemented; ship/crew, item
  matching, cache, and natural/modified ability variants depend on later phases.
- Item-group/filter semantics and exact wildcard/list comparison behavior for
  every condition type. Active fixed/temporary rule predicates now work.
- `<set modifier>`, item/tag/cache/dock setters, and the non-numeric `<adjust>`
  variants. These attributes occur hundreds of times (especially crew).
- Complete Java group UI semantics for nested optional children and undo remain;
  groups now have a compound action and ordered coroutine continuation.
- Loops now repeat until their variable becomes defined and preserve blocking
  child continuation; the safety limit remains a malformed-content guard.
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
  visit-only history/return, installed-book checks, and a boolean `at_sea`
  marker. Used destinations are tracked by stable instruction address; ordinary
  actions are suppressed when revisiting the source while `revisit="t"` actions
  remain available.
- Catalogs maps and illustrations. Fixed rules persist in character state;
  temporary rules are cleared/reloaded from each active book's `Rules` property.

**Still needed**

- Complete remaining `price`, `currency`, `pay`, `item`, `tags`, sail, dock, and ship
  transition variants. Standalone Shard prices and their enabling flags work;
  goto payment removes at most one named item and money, regardless of the full
  Java action rules.
- Death menu routing to each book's configured death section when no authored
  dead goto is present.
- Match Java's visible acquisition blocker and menu presentation for persistent
  `<extrachoice>` entries; keyed storage/removal and address/tag activation work.
- `sectionview` is explicitly out of player-runtime scope because it is a Java
  desktop preview browser; the rationale is recorded in the scope decision.

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

- Normalizes item instances with kind, stable identity, quantity, structured
  tags, effects, and equipped state. Weapons, armour, and tools can be equipped.
- Applies active aura, wielded, and tool effects in derived ability reads, with
  add/divide/target operations. Limited-use item effects are actionable.

**Still needed**

- Complete Java ordering for interacting positive/negative tool effects and all
  purpose-specific natural/affected ability reads.
- Apply include/exclude filters to every loss/transfer/market context; structured
  matching is implemented for caches and inventory helpers.
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
- Cache screens offer constrained item and money deposit/withdrawal, enforce
  capacity, multiples and withdrawal charges, and apply include/exclude filters.

**Still needed**

- Cache freezing and Java's complete unnamed-cache lifecycle.
- Correct unnamed-cache behavior used by Java, and exact cache lifetime/scope.
- `adjustmoney` cache targeting and multiplication (all 89 corpus uses specify
  `multiply`; most also specify a cache name).
- Attribute-complete, directional transfer with filtering, price, limit, and
  continuation semantics. Current source-cache transfer moves every item even
  when a filter is authored.

### 3.6 Ships, crew, cargo, sailing, and maritime trade — **Partial**

**Java behavior**

- `Ship` models type, capacity, crew quality, cargo types/units, location, and
  combat-relevant properties. `ShipList` manages multiple ships and the active
  ship.
- Tick/lose/adjust/set/trade nodes buy, sell, select, upgrade, damage, and move
  ships; change crew; and buy/sell/load/unload cargo.
- Trade prices and availability respond to ship capacity, cargo, crew, flags,
  quantities, and authored trade events.

**KOReader now**

- Models Barques, Brigantines, and Galleons with Java capacities, persistent
  identity/name, bounded crew quality, cargo units, dock, and active selection.
- Sailing and section dock metadata move the active ship. The character sheet
  lists ships, crew and cargo, and actions can select a co-located ship.
- Markets buy and sell ships and cargo, enforce capacity/ownership/funds, set or
  upgrade crew, and run matching sold/bought transaction children.

**Still needed**

- Multi-ship selection prompts inside ambiguous authored loss/transfer nodes and
  Java's separate ship-transfer dialog.
- Complete `adjust`-child crew/ship pricing modifiers and unusual forced ship
  losses; the common `ship`, `crew`, `cargo`, `initialcrew`, dock, gain/loss, and
  buy/sell paths now use the fleet model.

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
- Item replacements/tags/effects/flags and conditional price adjustments beyond
  the common ship/cargo/crew transaction path.
- Generalize transaction events beyond the corpus `sold` form; sold/bought child
  programs now run only for their matching completed transaction.

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
- Rest is a selectable transactional action with affordability checks, bounded
  fixed healing, and full healing when Stamina is omitted.

**Still needed**

- Optional and forced action semantics. Lua applies nearly every tick/gain/loss
  immediately and ignores most `force`, `price`, `chance`, `fatal`, `special`,
  `permanent`, `addbonus`, title-pattern/value/adjustment, cache, and selection
  behavior.
- Maximum-Stamina and Defence mutations, all/single ability choice, blessing
  consumption/prevention, injury/death rules, and undo integration.
- Ship/crew/cargo forms and effect/tag/equipped-item forms.
- Finish multi-use and dice-expression rest choices and roll-specific undo. Fixed
  and full-heal defaults, affordability, bounded healing, and payment now work.

### 3.9 Blessings, gods, curses, diseases, and poisons — **Partial**

**Java behavior**

- Blessings are typed: ability, storm, Defence, injury, disease/poison immunity,
  luck, travel, and divine wrath. They may be permanent or consumed when used.
- Gods and items can contribute chained effects.
- Curses/diseases/poisons have type, name, cumulative behavior, a lift prompt,
  attached item, and one or more effects. Duplicate non-cumulative afflictions
  and lifting/removal are handled distinctly.

**KOReader now**

- Stores typed blessing and affliction records with cumulative instances and
  active reversible add/divide/target effects. Removing an entry removes its
  derived effect rather than attempting to reverse a prior base-stat mutation.

**Still needed**

- Typed blessing behavior in rolls, combat, travel, injury, and affliction
  prevention, including consumption/permanence and wildcard matching.
- Attached affliction items and interactive lift questions/actions.
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
- Retains bounded undo snapshots with roll metadata. Reroll actions restore the
  pre-roll state and repeat random, skill, training, or combat attack rolls.
- Presents an explicit ability choice for `training ability="?"`; the selected
  ability is retained in undo/reroll metadata.

**Still needed**

- Roll type/modifier variants and precise adjustment eligibility. Lua only
  executes `<adjust>` children with a condition and adds `amount`/`value`.
- Correct success boundary and result-value parity should be locked down with
  Java fixtures, especially Rank and difficulty result variables.
- Remaining training adjustment/effect/blessing variants beyond the common
  dice/add rule.
- Extend reroll metadata to rare loss-node rollers and reproduce Java's exact
  result prose/branch re-entry for every optional roll placement.
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

- Uses a serialized round state machine with active opponent, enemy Stamina,
  round, group, and log state. Each attack is transactional and separately
  autosaved; authored player flee choices are available during combat.
- Supports grouped opponents, attack count/dice/first/Defence/damaged-ability/
  pre-damage/flee attributes, derived equipment effects, and Defence/injury
  blessing consumption.
- Runs paired round, damage, and enemy-flee programs at their combat timing;
  replacement damage hooks own damage rather than supplementing it.
- Detects mutual inability to inflict damage and offers an explicit skip, and
  implements the corpus `modifiers="noarmour"` fight modifier.

**Still needed**

- Hook subprograms that themselves block need a dedicated nested combat
  continuation instead of executing synchronously.
- Unobserved `usecache` variants, additional modifiers, and the remaining luck/
  wrath blessing interactions.
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

### 3.13 Persistent extra choices — **Partial**

Java lets a section grant or remove a keyed destination that later appears only
at a configured address or in sections with a matching tag. KOReader now stores
that keyed choice in schema 2, removes it by key, and exposes it at the authored
address or tag. It still needs Java's visible acquisition blocker, flash/menu
presentation, and styled-label details.

### 3.14 Save/load, autosave, continuation, and hardcore mode — **Partial**

**Java behavior**

- Saves the character and related collections, current section/node execution
  properties, extra choices, ships, caches, roll/fight state, and other active
  interaction data. Loading rehydrates listeners/effects and resumes the exact
  actionable state.
- Undo state protects roll-driven changes. Hardcore/rule settings affect play.

**KOReader now**

- Uses schema-2 `LuaSettings` saves, validates and migrates schema-1 data, and
  delegates atomic file replacement to KOReader. The UI autosaves after screens.
- Parsed nodes receive stable instruction paths. The save records the current
  instruction plus per-section applied-mutation and completed-blocker sets, so
  reconstruction does not repeat earlier effects and stops at the same blocker.
- Random draws are journaled, and each player action is transactional: an error
  restores the complete state from before the action. Markets retain their
  transaction view across reconstruction.
- Structured schema-2 records reserve the inputs needed for derived statistics,
  equipment/effects, afflictions, fleets, rules, visits, extra choices, and cache
  constraints while preserving legacy aliases during the transition.
- Fixed and book-temporary optional rules are active. `hardcore` remains an
  unused boolean pending a separately specified gameplay policy.

**Still needed**

- Populate and consume the structured records as their engines are implemented;
  model availability is not feature parity.
- Add nested continuation serialization for the rare combat hooks which contain
  their own blocking action.
- Add broader migration fixtures, explicit save corruption recovery, and make a
  Java-save import decision.
- Implement or remove the exposed hardcore control; rules now have runtime
  semantics, while a future settings UI may expose fixed-rule selection.

### 3.15 Presentation-linked game facilities — **Partial**

- **Character sheet:** KOReader displays core stats/inventory, but not complete
  effects, typed blessings/afflictions, equipped items, persistent choices, or
  editing/use actions.
- **Ship sheet:** basic fleet, location, crew, and cargo output is present.
- **Maps and illustrations:** paths and display exist; Java opens illustrations
  separately while KOReader embeds them, an acceptable design difference.
- **Rules/help:** fixed and book-temporary rules are connected to game state.
- **Action pagination:** implemented as a KOReader-native accommodation.
- **Styled text/tables/boxes:** simplified intentionally; see the separate text
  parsing audit. These are not game-rule blockers unless styling communicates
  enabled/disabled state or hides a transaction choice.

## 4. XML vocabulary coverage summary

| Area | Java elements | KOReader status |
| --- | --- | --- |
| Containers/presentation | `section`, `p`, `h1`–`h4`, `b`, `i`, `table`, `tr`, `td`, `header`, `text`, `box`, `choices`, `abilities`, `items` | Parsed/rendered in simplified form. |
| Branching/navigation | `if`, `elseif`, `else`, `choice`, `goto`, `return`, `while`, `group`, `sectionview` | Common branches/gotos/visit-return work; group/while partial; sectionview is explicitly desktop-only. |
| Rolls | `random`, `difficulty`, `rankcheck`, `outcomes`, `outcome`, `success`, `failure`, `adjust`, `reroll`, `training` | Main checks, ability selection, bounded undo, and reroll work; rare roller and continuation cases remain. |
| State changes | `set`, `tick`, `gain`, `lose`, `rest`, `price` | Common scalar and standalone Shard-price actions work; optional/interactive and uncommon attribute forms remain partial. |
| Items/effects | `item`, `weapon`, `armour`, `tool`, `effect`, `include`, `exclude`, `itemcache`, `moneycache`, `transfer` | Basic inventory and narrow transfer only; equipment/effects/filter/cache UI missing. |
| Afflictions/death | `curse`, `disease`, `poison`, `resurrection` | Name storage/basic resurrection only. |
| Combat | `fight`, `fightround`, `fightdamage`, `flee` | Serializable interactive/grouped combat, ordinary hooks, flee, stalemate skip, common modifiers, blessings, and reroll work; blocking hooks remain partial. |
| Commerce/ships | `market`, `trade`, `buy`, `sell`, `sold`, `tradeevent`, `adjustmoney` | Basic item market only; ship/cargo/crew/events/cache money math missing. |
| Persistent/UI actions | `extrachoice`, `field`, `image` | Image and read-only field values work; extra-choice presentation remains partial. |
| Character templates | `adventurers`, `adventurer`, `profession`, `rank`, `stamina`, `gold` | Book-specific starters, statistics, gender, and possessions are data-driven. |

`exclude`, `include`, and `sold` deserve explicit handlers even though
generic recursion makes
them appear “accepted.” Silently walking an element is not proof its Java
semantics have been implemented.

## 5. Priority plan for parity work

The checklist below tracks implementation progress. Its recommended order
minimizes the risk of building more rules on an inadequate state/save model.

### Phase 0 — executable compatibility inventory — **Complete**

- [x] Generate a checked-in machine-readable tag/attribute census for books
  1–6. `docs/koreader-content-census.json` records counts, observed attributes,
  and the current support classification. The generator has a drift-check mode.
- [x] Make the interpreter fail loudly for elements or executable attributes
  outside the declared compatibility boundary. The generated Lua declaration
  deliberately labels incomplete handlers `partial` or `missing`; declaration
  means “recognized,” not “parity complete.” This protects new content from
  silently falling through without pretending existing gaps are fixed.
- [x] Build a small Java-oracle expectation for every executable content tag.
  `tests/fixtures/java_oracle_game_logic.json` names the responsible Java class
  and observable rule, and includes continuation/reload scenarios for goto,
  checks, fights, groups, markets, and rerolls. Tests enforce complete, unique
  coverage as the vocabulary changes.

Phase 0 establishes inventory and regression boundaries only. It does not
change the `partial` and `missing` parity findings above; those remain checklist
items for subsequent phases.

The generated support inventory currently classifies the 69 observed tags as
3 implemented, 48 partial, 1 missing, and 17 presentation/template tags. These
labels are the checklist baseline: completing later work should move entries
from `partial`/`missing` to `implemented`, with a corresponding oracle test.

### Phase 1 — state and persistence foundation — **Complete**

- [x] Define structured model records for natural/modified/derived statistics,
  equipment, item effects, typed afflictions, ships/cargo/crew, fixed and
  temporary rules, visits, persistent extra choices, and cache constraints.
  Compatibility aliases remain in schema 2 while later phases move individual
  rules onto these records.
- [x] Version serialization and migrations. Schema-1 saves migrate in memory to
  schema 2; new nested collections and the RNG journal receive safe defaults,
  and future schemas fail validation rather than loading partially.
- [x] Give parsed instructions stable tree paths and persist per-section applied
  and completed instruction sets. Reload reconstructs the section while
  suppressing already-applied mutations and resolved blockers, preserving the
  current blocker. Market transaction views are restored as market views.
- [x] Route all engine randomness through a persisted draw journal and wrap
  player actions in reversible state transactions. Invalid actions and runtime
  failures restore the complete pre-action state rather than leaving partial
  payment, inventory, or roll changes.

Phase 1 supplies persistence primitives; it does not imply that the later ship,
effect, cache, or rules engines are implemented. Their model records are dormant
until the corresponding checklist phases use them.

### Phase 2 — expressions and generic actions — **Complete**

- [x] Port the Java arithmetic expression grammar with identifiers, unary signs,
  parentheses, precedence, integer division, and explicit parse/resolution errors.
  Resolution includes section variables, abilities, core statistics, Shards,
  and selected weapon/armour bonuses. Set nodes also support codeword values and
  docking side effects; adjustment children remain contextual rather than being
  incorrectly executed as standalone gains.
- [x] Establish generic immediate and optional mutation paths. Optional gain,
  tick, and loss actions now defer mutation until selected, execute inside the
  Phase-1 transaction, and are recorded in the applied-instruction ledger.
  Cached/carried money multiplication is handled by `adjustmoney`.
- [x] Implement resumable optional groups and correct Java loop termination:
  `<while var="…">` repeats while the variable is undefined, not while it is a
  non-zero number. Blocking children continue through the existing coroutine
  boundary.
- [x] Implement rest actions with affordability, full-heal defaults, bounded
  Stamina, and transactional payment. Implement keyed extra-choice acquisition,
  removal, persistence, and activation by address or section tag.

The generic framework is complete, but model-specific operands remain checked
under their owning phases: ship/crew/cargo actions in Phase 4, effect and item
filter semantics in Phase 3, and blessing-driven undo/fatality in Phases 3 and
5. Phase 2 completion therefore does not change those tags from `partial` yet.

### Phase 3 — inventory, effects, afflictions, and caches — **Complete**

- [x] Normalize item groups and tags, track equipped weapon/armour/tools, and
  calculate abilities through ordered active aura, wielded, and tool effects.
- [x] Parse item effects, expose limited-use actions, and make curse/disease/
  poison effects active records so acquisition and removal recompute values.
- [x] Store typed ability blessings and cumulative afflictions with serialized
  add, divide, and target effects.
- [x] Add repeatable item/money cache screens with maximums, item limits,
  withdrawal multiples/charges, include/exclude filters, and transactional
  deposits and withdrawals.

Phase 3's reusable inventory/effect/cache engine is complete. Specialized
ship-cargo transfers remain in Phase 4; combat blessing consumption and roll
undo remain in Phase 5; affliction lift prompts and unusual embedded use-effect
programs remain explicit partial-tag follow-ups above.

### Phase 4 — ships and economy — **Complete**

- [x] Implement persistent ship, bounded crew, capacity-aware cargo, dock, and
  active-ship models; expose fleet details on the character sheet and provide
  co-located active-ship selection.
- [x] Route common ship/crew/cargo set, gain, tick, loss, condition, sailing, and
  dock behavior through the fleet model.
- [x] Implement repeatable transactional ship/cargo/crew purchasing and selling,
  affordability/capacity checks, initial crew, and matching sold/bought hooks.
- [x] Exercise fleet constructors, capacity, cargo, location, crew, selection,
  trade dispatch, event hooks, sheet output, and save structure in automated
  Phase-4 checks.

Phase 4 covers the corpus economy foundation. Ambiguous multi-ship prompts,
conditional adjustment-child pricing, and the desktop-only ship-transfer dialog
remain explicit partial follow-ups above rather than being silently ignored.

### Phase 5 — dice and combat parity — **Implemented; blocking-hook follow-up open**

- [x] Persist bounded action snapshots and roll metadata; true reroll restores
  pre-roll state and repeats random, skill, training, and combat attack rolls.
- [x] Replace whole-fight simulation with a serializable, transactional round
  state machine and autosave-compatible attack/flee actions.
- [x] Add grouped opponent progression, player flee destinations, paired round/
  damage/enemy-flee hooks, replacement damage, equipment-derived COMBAT and
  Defence, and consumable Defence/injury blessings.
- [x] Add explicit mutual-stalemate skip and the authored `noarmour` modifier.
- [ ] Suspend and serialize a combat hook that starts another blocking action;
  this is the sole uncompleted Phase-5 checklist item and is not represented as
  complete elsewhere in this audit.

Phase 5 establishes the combat/roll engine, but remains intentionally checked as
open because blocking hook programs occur in authored content. Rare loss-node
rollers remain recorded as a separate reroll follow-up above.

### Phase 6 — data-driven creation, rules, and completeness gate — **Complete**

- [x] Parse each selected book's `Adventurers.xml`; create the named adventurer
  with authored profession scores, gender, Rank, Stamina, money, and possessions;
  remove the hard-coded book-1 starter table.
- [x] Activate normalized saved fixed rules and per-book temporary rules, and
  limit return-history entries to authored `visit` destinations.
- [x] Record product-scope decisions: `sectionview` remains a clearly labelled
  desktop-only preview facility, while read-only `<field>` values render inline.
- [x] Add a six-book reachability gate. Starting at every `New.xml`, it follows
  installed-book destinations, fails on missing sections, and fails when a
  reachable executable tag has no explicit runtime dispatch. The current scan
  reaches 4,405 sections with no missing destination or dispatch gap.

Phase 6 completes the planned foundation and makes remaining partial behavior
explicit; it does not redefine the partial systems above as full Java parity.

## 6. Highest-risk current mismatches

These should be treated as correctness defects rather than polish:

1. **Blocking combat hooks:** ordinary round/damage/flee hooks work, but a hook
   containing its own blocker needs nested continuation state.
2. **Generic mutation is still incomplete:** uncommon title/item variants are
   ignored while execution continues.
3. **Rare rollers:** loss-node rolls are not yet covered by reroll metadata.
4. **Ambiguous fleet operations:** multi-ship loss/transfer and conditional trade
   adjustments still need explicit selection and pricing behavior.
5. **Special effects remain:** embedded use-effect programs, affliction lifting,
   and typed blessing consumption are incomplete.
6. **Save reconstruction is path-based:** later work must preserve any new
   interactive combat sub-state and add broader migration/corruption fixtures.
7. **Extra-choice presentation differs:** routes work, but visible acquisition
   does not yet reproduce Java's blocking/menu behavior.
8. **Partial dispatch is not full parity:** the reachability gate prevents a
   reachable executable tag from falling through without explicit dispatch, but
   attributes classified `partial` can still implement only their common forms.

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

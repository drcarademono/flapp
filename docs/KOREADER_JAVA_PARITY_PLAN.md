# KOReader–Java full gameplay parity plan

- **Goal:** make `plugins/jafl.koplugin` behaviorally equivalent to the Java
  gameplay runtime in `flands/` for every game system used by books 1–6.
- **Source of truth:** Java behavior, not the existing Lua implementation, tag
  counts, audit checkbox history, or a preferred redesign.
- **Status:** active; parity has **not** been achieved.
- **Supersedes:** the phase ordering in `JAVA_GAME_SYSTEMS_AUDIT.md` and the
  implementation checklist in `JAVA_GAME_SYSTEMS_REAUDIT.md`. Those documents
  remain evidence and issue inventories; this document is the delivery plan.

## 1. Non-negotiable definition of parity

A feature is complete only when all of the following are true:

1. **Parsing parity:** every Java-recognized gameplay attribute used by books
   1–6 is parsed with the same default, normalization, wildcard, and invalid
   value behavior.
2. **Availability parity:** the same actions are enabled or disabled after every
   state transition. KOReader buttons may replace Swing controls, but the player
   must receive the same choices at the same point.
3. **State parity:** choosing an action produces the same character, inventory,
   effect, ship, cache, flag, codeword, title, resurrection, rule, and location
   state.
4. **Execution parity:** child actions run in the same order and stop/resume at
   the same blocking boundary, including nested groups, loops, results, fight
   hooks, item-use programs, and trade events.
5. **Roll parity:** equivalent dice expressions, adjustments, result variables,
   potion/blessing handling, outcomes, undo ownership, and rerolls are used.
6. **Persistence parity:** saving and reloading at every blocking boundary
   restores the same visible actions and continuation without repeating or
   skipping mutations or random draws.
7. **Lifecycle parity:** death, resurrection, combat completion, navigation,
   book changes, temporary rules, and hardcore policy occur in the same order.
8. **Corpus parity:** every reachable gameplay construct and attribute
   combination in books 1–6 has an executable test, not merely a dispatch match.
9. **Intentional differences:** only presentation changes may be accepted
   without Java equivalence. Each exception needs a written acceptance test and
   explicit approval. `sectionview` is included until such a waiver is approved.

A module name, state field, handler branch, compatibility declaration, or static
source assertion is **not** proof of parity.

## 2. Required parity evidence

### 2.1 Java oracle

Create a headless Java oracle that loads small XML fixtures through the real
Java classes and emits canonical JSON after every action:

- visible action identities and enabled state;
- current address and continuation owner;
- all character and collection state;
- current roll owner, dice, adjustment, result, and undo chain;
- execution-frame/container position;
- combat phase and enemy state; and
- RNG input/output sequence.

Swing prompts must be driven through an injectable decision adapter rather than
rewriting the underlying game rule. If isolating a class is impossible, run the
existing Java application headlessly and capture its model state.

### 2.2 Lua behavioral runner

Replace source-text assertions as parity evidence with executable Lua tests.
The runner must:

- run under LuaJIT/Lua 5.1, matching KOReader;
- consume the same fixture and deterministic decisions as the Java oracle;
- canonicalize Lua state into the same JSON schema;
- compare every checkpoint, not only final state;
- save, construct a new `Game`, reload, and compare again at each blocker; and
- exercise accept, decline, cancel, unavailable, failure, success, and undo
  branches where Java exposes them.

Source-text tests may remain as architecture guards, but cannot close a parity
item.

### 2.3 Attribute contract

Replace the current observed-vocabulary declaration with a generated contract:

```text
(tag, normalized attributes, parent context, relevant child shape)
    -> handler capability id + executable oracle scenario id
```

Loading must fail for an observed combination which has no capability entry.
The contract must distinguish, for example, `lose item` from `lose stamina
fatal`, and an ordinary `effect` from an embedded `type=use` program.

### 2.4 Completion gate

The parity claim is allowed only when:

- every work item below is checked;
- Java and Lua oracle output matches for every fixture;
- every reachable corpus signature maps to a passing oracle scenario;
- all blocking scenarios pass uninterrupted, save/reload, undo, and reroll
  variants as applicable;
- no gameplay tag is `partial` or `missing` in the runtime contract;
- no approved-difference entry is missing acceptance criteria; and
- a final audit against the then-current commit finds no unexplained gameplay
  difference.

## 3. Delivery order and dependency graph

Work must proceed in this order. Later systems must not add more special-case
continuations while the shared execution engine is unfinished.

1. **Foundation A:** executable Java/Lua oracle and corpus signature inventory.
2. **Foundation B:** serializable execution machine and action availability.
3. **Foundation C:** owned transactions, rolls, undo, and reroll.
4. **Models:** abilities/effects, collections, mutations, inventory, ships.
5. **Interpreters:** conditions, navigation, outcomes, caches, trade, combat,
   death, resurrection, persistent choices, and rules.
6. **Rules-relevant UI:** every Java decision represented in KOReader.
7. **Closure:** exhaustive corpus execution, approved differences, and final
   independent audit.

## 4. Workstream A — parity harness and inventory

### A1. Java oracle adapter

- [ ] Add a Java test entrypoint which accepts fixture XML, initial state, RNG
  sequence, and player decisions.
- [ ] Serialize canonical checkpoints without Swing document objects.
- [ ] Provide adapters for choice, item, money, ability, blessing, ship, flee,
  resurrection, and confirmation prompts.
- [ ] Record action availability changes caused by flags/listeners.
- [ ] Prove the oracle itself with direct assertions against representative Java
  methods before comparing Lua.

**Acceptance:** one command produces stable JSON for navigation, a difficulty
roll, an item loss selection, a market transaction, and one fight round.

### A2. Lua runner

- [ ] Vendor or provision a Lua 5.1/LuaJIT interpreter in CI.
- [ ] Add canonical state/action serialization matching A1.
- [ ] Compare Java and Lua checkpoint JSON with readable structural diffs.
- [ ] Support save/reload at a named checkpoint.
- [ ] Support undo/reroll and alternate decisions from the same checkpoint.
- [ ] Make `check-koreader-lua` mandatory for `koreader-plugin` and CI rather
  than silently optional.

**Acceptance:** existing forced-random, blessing, embedded-use, and combat-hook
fixtures run in CI and compare to output generated by Java, not handwritten
expected constants.

### A3. Corpus signature census

- [ ] Generate normalized signatures for every executable element, its parent
  context, relevant siblings/children, and attribute combination.
- [ ] Record reachability separately from raw occurrence.
- [ ] Map every reachable signature to a capability and oracle fixture.
- [ ] Fail CI when a content or runtime change creates an unmapped signature.

**Acceptance:** the report answers “which test proves this exact XML form?” for
all reachable executable elements in books 1–6.

## 5. Workstream B — serializable execution machine

Replace the coroutine/path hybrid with a deterministic stepper whose complete
state is serializable. A frame contains:

- frame kind and owner node path;
- current child index;
- parent frame id;
- local conditional branch, loop, or result state;
- pending action/decision descriptor;
- transaction and roller owner ids; and
- completion/cancellation disposition.

### B1. Core stepper

- [ ] Implement `push`, `step`, `block`, `resume`, `complete`, and `abort`.
- [ ] Ensure all executable mutation happens through `step`.
- [ ] Serialize frames without Lua closures, node tables, or coroutines.
- [ ] Resolve paths against freshly parsed XML on load and validate frame shape.
- [ ] Remove `progress.applied`/`progress.completed` replay as the primary
  continuation mechanism after migration.
- [ ] Migrate schema-2 saves or reject unsupported in-flight legacy states with
  an actionable error.

### B2. Every executable container

- [ ] Section root and paragraph-owned blockers.
- [ ] `if`/`elseif`/`else` selected branch.
- [ ] `group` current child and optional/forced decision.
- [ ] `while` condition and current iteration/child.
- [ ] `outcomes`, `outcome`, `success`, and `failure` branch.
- [ ] `fightround`, `fightdamage`, and `flee` hook.
- [ ] Embedded `UseEffect` program.
- [ ] `bought`/`sold` trade event.
- [ ] Resurrection and death routing.

**Acceptance:** for each container, a blocker nested at least three levels deep
has identical Java/Lua checkpoints before the blocker, after reload, after
resolution, and after the parent completes.

### B3. Action lifecycle

- [ ] Represent actions as serializable descriptors, not snapshots of Lua node
  tables.
- [ ] Re-evaluate availability after every relevant state change.
- [ ] Match Java flag/listener enablement and disablement.
- [ ] Preserve cancel/no-selection semantics where Java keeps a prompt open.
- [ ] Ensure an action cannot execute twice because of reload or stale UI.

## 6. Workstream C — rolls, transactions, undo, and reroll

### C1. Roller model

- [ ] Create a serializable roller record: owner, dice expression, adjustment,
  purpose, consumed effects, flag, destination variable, and completion phase.
- [ ] Cover `RandomNode`, `DifficultyNode`, `RankCheckNode`, `TrainingNode`,
  `LoseNode` rollers, combat attacks/defence/wrath, and rest variants.
- [ ] Match Java result sign and boundary rules exactly.
- [ ] Consume and restore potion/blessing effects at Java-equivalent points.

### C2. Owned undo chain

- [ ] Port Java `UndoManager.Creator` ownership rather than action-wide snapshots.
- [ ] Link roll, result variable, flag, outcome, and downstream mutations into
  one reversible chain.
- [ ] Restore execution position and available actions on undo.
- [ ] Restore consumed blessings, potions, combat bonuses, item charges, and RNG
  state when Java does.
- [ ] Define bounded persistence without recursive snapshot growth.

### C3. Reroll

- [ ] Reinvoke the original serialized roller after undo.
- [ ] Use a fresh random suffix while retaining earlier committed draws.
- [ ] Re-run flags, outcome selection, result branches, and continuation.
- [ ] Cover ability, Luck, Travel, authored `<reroll>`, combat, training, and
  loss-related rerolls.
- [ ] Save/reload both before deciding to reroll and after the reroll result.

**Acceptance:** Java and Lua match at every checkpoint for two consecutive
rerolls, accepted failure, accepted success, permanent blessing, consumable
blessing, potion, and nested-result mutation cases.

## 7. Workstream D — character, abilities, effects, and rules

### D1. Adventurer model

- [ ] Establish one source for natural ability, affected ability, testing value,
  Rank, current/max Stamina, and derived Defence.
- [ ] Remove or formally migrate the legacy scalar Defence field.
- [ ] Match caps, minimums, fatal behavior, Rank advancement, and max-Stamina
  advancement in every mutation path.
- [ ] Match profession and gender changes.
- [ ] Apply fixed and per-book temporary rules at Java-equivalent lifecycle
  boundaries.

### D2. EffectSet parity

- [ ] Oracle-test target/divide/add order, equal-effect ordering, wildcard scope,
  negative rounding, and cumulative sources.
- [ ] Match aura, wielded, armour, tool, god, curse, potion, and active blessing
  lifetimes.
- [ ] Match `natural`, `noarmour`, `notool`, combat, testing, and display purpose.
- [ ] Recalculate dependent values when equipment or an effect changes.
- [ ] Cover duplicate sources and effect removal/undo.

### D3. Character creation

- [ ] Compare every starter in every `Adventurers.xml` against Java.
- [ ] Match starting equipment selection and initial wield/wear behavior.
- [ ] Implement player-facing fixed-rule selection.
- [ ] Test new-game start in each installed-book combination.

## 8. Workstream E — conditions, navigation, and control nodes

### E1. Conditions

- [ ] Port every Java condition attribute and modifier, including natural versus
  affected abilities, `safeaddgod`, `using`, numeric titles/codewords, caches,
  resurrection, ships, crew, cargo, groups, filters, wildcards, and negation.
- [ ] Stop treating unknown identifiers as zero when Java reports or rejects an
  invalid expression.
- [ ] Match combined predicates and listener-driven changes.

### E2. Navigation

- [ ] Complete `ChoiceNode`, `GotoNode`, and `ReturnNode` flags, payments,
  codewords, empty variables, installed-book gates, dead gates, docks, sailing,
  visit/revisit, and history behavior.
- [ ] Make compound payment atomic and validate affordability before mutation.
- [ ] Match cross-book temporary-rule and map/location transitions.
- [ ] Test forced and optional goto inside every container type.

### E3. Control/data nodes

- [ ] Complete `SetVarNode` modifier/cache/item/dock forms.
- [ ] Complete `AdjustNode` thresholds, defaults, title values, professions,
  abilities, items, ships, cargo, and crew.
- [ ] Implement general `WhileNode` semantics on B1 frames.
- [ ] Match outcome range parsing, flags, owner association, and fall-through.

## 9. Workstream F — gain, loss, tick, rest, and price

### F1. Tick/gain/adjust

- [ ] Implement every observed `tick`/`gain` attribute and Java default.
- [ ] Complete ability choice, profession choice, god compatibility, permanent
  blessing, special/bonus/effect, cache, price, title counters/patterns, item
  tag/bonus operations, and fleet forms.
- [ ] Present a KOReader selector whenever Java opens a chooser.

### F2. Loss

- [ ] Implement chance-per-item loss with journaled dice.
- [ ] Implement fatal versus nonfatal ability/Stamina loss.
- [ ] Implement exact `itemat`, `using`, `kept`, group, tags, bonus, quantity,
  wildcard, and multiple matching.
- [ ] Select among ambiguous eligible items rather than choosing the first.
- [ ] Complete cache, blessing, resurrection, ship, cargo, and crew loss.
- [ ] Match cancel/retry behavior and linked undo.

### F3. Price and rest

- [ ] Port complete `PriceNode` currencies, items, filters, flags, grouped
  payment, availability listeners, rollback, and continuation.
- [ ] Port all rest formulas, repeatability, dice, payment, availability, and
  undo behavior.

**Acceptance:** every normalized `set`, `adjust`, `tick`, `gain`, `lose`,
`adjustmoney`, `price`, and `rest` corpus signature has a Java/Lua oracle test.

## 10. Workstream G — inventory, caches, and transfer

### G1. Item identity and equipment

- [ ] Match item types, groups, quantities, tags, bonuses, descriptions, effects,
  kept state, and identity.
- [ ] Match automatic/default wielding, armour selection, tool selection, locks,
  replacement, and recalculation.
- [ ] Implement `buytags`, `replace`, and complete embedded effects in all item
  creation paths.
- [ ] Make split/merge/remove behavior identical across inventory, cache, trade,
  and loss.

### G2. Caches

- [ ] Match named and unnamed identity, freeze lifecycle, item limit, maximum
  money, multiples, withdrawal charge, include/exclude, and availability.
- [ ] Persist an in-progress cache chooser and restore it exactly.

### G3. Transfers

- [ ] Implement all from/to/null endpoints.
- [ ] Apply include/exclude and `x*` filters exactly.
- [ ] Implement limits, price, shards, forced/optional behavior, and selection.
- [ ] Preserve equipped-state restrictions and transaction atomicity.
- [ ] Run nested transfer continuations through B1.

## 11. Workstream H — markets, ships, crew, and cargo

### H1. Markets/trade

- [ ] Match live availability, flags, conditional price, currency, finite
  quantity, buy/sell tags, replacement, and effects.
- [ ] Match item, ship, cargo, and crew transaction variants.
- [ ] Run `bought`/`sold` programs through serializable frames and return to the
  same market entry state.
- [ ] Save/reload before confirmation, inside event, and after transaction.

### H2. Fleet model

- [ ] Port Java ship type/capacity/cargo-unit/crew-quality representation.
- [ ] Match active ship and location rules.
- [ ] Implement ambiguous ship selection and loss.
- [ ] Implement ship swap and cargo redistribution with Java constraints.
- [ ] Match partial cargo and crew changes, initial crew, and vessel replacement.
- [ ] Ensure every fleet decision has a KOReader chooser and reload checkpoint.

## 12. Workstream I — combat

### I1. Fight construction and caching

- [ ] Pair hooks by Java structural ownership, not global ordinal assumption.
- [ ] Match `useCache`, cached combat/defence values, every modifier, pre-damage,
  alternative damaged ability, attacks, dice, player-first, and group setup.
- [ ] Match potion lifetime and Defence/Wrath prompt timing under undo/reload.

### I2. Round machine

- [ ] Match player and enemy roll order for every `playerfirst`/multi-attack case.
- [ ] Match damage, replacement damage hooks, round hooks, pre-fight hooks, and
  flee hooks.
- [ ] Match enemy flee thresholds, player flee choices, and grouped continuation.
- [ ] Match cannot-win, cannot-lose, and skip/stalemate states exactly.
- [ ] Preserve all phases through save/reload and owned undo.

### I3. Combat lifecycle

- [ ] Match victory, defeat, flee, death, resurrection, and following-section
  continuation order.
- [ ] Add the reachable book 5/689 end-to-end save/reload oracle.
- [ ] Add grouped fights, multiple attacks, hook destination, hook death, wrath
  kill, Defence blessing, Luck reroll, potion, and stalemate oracles.

## 13. Workstream J — blessings, gods, afflictions, death, resurrection

### J1. Blessings and gods

- [ ] Reconfirm ability, Luck, Travel, Defence, disease immunity, and Wrath
  behavior against executable Java output, including permanence and undo.
- [ ] Preserve declared storm/injury types even where Java has no activation
  path; do not invent behavior.
- [ ] Complete god compatibility, exclusion, replacement, effects, and loss.

### J2. Curses/diseases/poisons

- [ ] Match duplicate and cumulative rules.
- [ ] Match attached effects/items and their removal.
- [ ] Match disease/poison prevention and permanent blessing behavior.
- [ ] Implement named, wildcard, selected, and prompted lifting, including `lift`
  text and cancellation.
- [ ] Persist and migrate every structured affliction.

### J3. Death/resurrection/hardcore

- [ ] Centralize the Java death transition and remove routes which leave invalid
  living-player actions available while dead.
- [ ] Match fatal loss, combat death, cleanup/retention, ship consequences, death
  section, and resurrection offer order.
- [ ] Match supplemental/replacement resurrection, gods, flags, cost, selection,
  destination, and restored state.
- [ ] Implement Java-equivalent hardcore save/death policy and tests.

## 14. Workstream K — persistent facilities and rules-relevant UI

### K1. Extra choices

- [ ] Match visible/blocking acquisition, styled label content, activation by
  address/tag, replacement/removal, persistence, and action availability.

### K2. Character and fleet UI

- [ ] Display natural/affected abilities, derived Defence, Rank, current/max
  Stamina, money, equipment, quantities, effects, blessings, afflictions,
  codewords, numeric titles, gods, resurrection, extra choices, and ships.
- [ ] Provide equipment, item use, cache transfer, ship selection/swap, and all
  Java rules-relevant chooser interactions.
- [ ] Ensure pagination never changes action identity or stale-index behavior.

### K3. Section view and save management

- [ ] Implement `SectionViewNode` sequential/random browsing, or obtain and
  record an explicit non-gameplay waiver with acceptance criteria.
- [ ] Decide whether Java multi-save selection, preview, backup, and recovery are
  required for product parity; gameplay-state restoration itself is mandatory.
- [ ] Implement whichever facilities are accepted into scope and test them.

## 15. Java class/node closure matrix

Each row closes only when its attributes, state effects, choices, blocking,
reload, and undo behavior pass Java/Lua oracle comparison.

| Family | Java source-of-truth classes | Owning workstream | Status |
| --- | --- | --- | --- |
| Parser/model construction | `Node`, `LoadableNode`, parser/loader classes | A3, B1 | [ ] |
| Execution | `Executable`, `ExecutableGrouper`, `ExecutableRunner`, `ActionNode`, `Flag` | B, C | [ ] |
| Conditions/control | `IfNode`, `GroupNode`, `WhileNode` | B2, E | [ ] |
| Navigation | `Address`, `Books`, `ChoiceNode`, `GotoNode`, `ReturnNode`, `SectionNode` | E2 | [ ] |
| Variables/mutations | `SetVarNode`, `AdjustNode`, `TickNode`, `LoseNode` | E3, F | [ ] |
| Prices/rest | `PriceNode`, `RestNode`, cache `AdjustMoneyNode` | F3 | [ ] |
| Rolls/results | `Roller`, `RandomNode`, `DifficultyNode`, `RankCheckNode`, `TrainingNode`, `RerollNode`, `OutcomeNode`, `OutcomesTableNode`, `DifficultyResultNode` | C, E3 | [ ] |
| Adventurer/rules | `Adventurer`, `ActiveRuleset` | D | [ ] |
| Items/effects | `Item`, `ItemList`, `ItemNode`, `ItemGroupNode`, `ItemFilterNode`, `Effect`, `AbilityEffect`, `EffectSet`, `EffectNode`, `UseEffect` | D2, G | [ ] |
| Caches/transfers | `CacheNode`, `TransferNode`, money/item cache models | G | [ ] |
| Markets/trade | `MarketNode`, `TradeNode`, `TradeEventNode` | H1 | [ ] |
| Ships | `Ship`, `ShipList`, `ShipSwapDialog` | H2 | [ ] |
| Combat | `FightNode` and nested attack/defend/round/damage/flee actions | I | [ ] |
| Blessings/gods | `Blessing`, `BlessingList`, god-related effects | J1 | [ ] |
| Afflictions | `Curse`, `CurseList`, `CurseNode` | J2 | [ ] |
| Death/resurrection | `Resurrection`, `ResurrectionNode`, FLApp death orchestration | J3 | [ ] |
| Persistent choices | `ExtraChoice` and `extrachoice` node behavior | K1 | [ ] |
| Rules-relevant UI | `AdventurerFrame`, `ShipFrame`, choosers | K2 | [ ] |
| Section browser | `SectionViewNode` | K3 | [ ] |
| Persistence | load/save classes, `UndoManager` | B1, C2, J3, K3 | [ ] |

Presentation-only nodes (`ParagraphNode`, `HeadingNode`, `TextNode`, `StyleNode`,
`BoxNode`, `TableNode`, and `RowNode`) remain covered by the separate text audit,
but any presentation property that communicates action state belongs in K2.

## 16. Pull-request discipline

Each parity PR must contain:

1. the Java classes/methods used as source of truth;
2. Java-generated oracle output;
3. the Lua implementation;
4. uninterrupted, reload, and undo/reroll comparisons where applicable;
5. updated capability/signature mappings;
6. only the checklist boxes proven by those tests; and
7. no broad “parity complete” claim based on structural tests.

Recommended PR slices are one behavior family, not one XML tag. For example,
“ambiguous filtered item selection across loss/cache/transfer” is preferable to
three inconsistent tag-specific implementations.

## 17. Final sign-off checklist

- [ ] A1–A3 complete.
- [ ] B1–B3 complete; no special-purpose continuation bypass remains.
- [ ] C1–C3 complete; every roller has owned undo/reroll tests.
- [ ] D1–D3 complete.
- [ ] E1–E3 complete.
- [ ] F1–F3 complete.
- [ ] G1–G3 complete.
- [ ] H1–H2 complete.
- [ ] I1–I3 complete, including book 5/689.
- [ ] J1–J3 complete.
- [ ] K1–K3 complete or explicitly waived where allowed.
- [ ] Every reachable corpus signature maps to a passing Java/Lua scenario.
- [ ] Runtime compatibility contains no gameplay `partial` or `missing` status.
- [ ] Full test suite passes under the KOReader Lua runtime version.
- [ ] Fresh independent Java-versus-Lua audit reports no unexplained difference.
- [ ] Audit documents are reconciled with current code and commit ids.
- [ ] Maintainer signs off on the full-parity claim.

Until every applicable item above is checked with executable evidence, the
project status is **not full Java gameplay parity**.

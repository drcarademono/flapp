# Java game systems second-pass audit

- **Re-audit date:** 2026-09-09
- **Reference:** `flands/*.java`, books 1–6, and their `Adventurers.xml` files
- **Port checked:** `plugins/jafl.koplugin/` at commit `b77cabc`
- **Purpose:** independently challenge the earlier parity claims after Phases 0–6

## 1. Executive conclusion and feature-parity verdict

The KOReader plugin does **not** yet implement all Java game systems. It now has
useful foundations for most major domains, but the second pass confirms that
nearly every rules-heavy domain remains partial. The largest risks are not
unknown XML tag names. They are incomplete semantics behind recognized tags,
and blocking actions executed outside the one coroutine that can suspend.

The most important conclusion is therefore:

> Passing the compatibility and reachability scripts is not evidence of full
> playability or Java parity.

**Feature-parity verdict: NO.** This verdict covers the entire Java gameplay
runtime, not only Phase 6 and not only the 69 book-content tags. The ledger in
section 5 accounts for the Java execution framework, every node family created
by `Node.createChild`, character collections and effects, ships, undo/RNG,
persistence, and rules-relevant UI facilities. Pure Swing painting and window
geometry are explicitly listed as non-gameplay rather than silently omitted.

The compatibility generator records observed names and attributes. It does not
prove that a handler consumes each declared attribute. The reachability script
checks that a destination file exists and that a tag name appears in a Lua
dispatch comparison. It does not execute conditions, validate action results,
or prove that the dispatch implements the Java contract. Existing tests are
predominantly source-text assertions and do not run Lua game scenarios.

### Re-audit totals

| Classification | Systems |
| --- | --- |
| Substantially implemented | XML parsing/declaration boundary; basic section navigation; book-specific starting templates; basic scalar state; basic save envelope; maps/images |
| Partial, with reachable correctness gaps | execution/continuations; conditions; mutations; items/effects; caches/transfers; ships/trade; afflictions/blessings; rolls/rerolls; combat; resurrection/death; visits; extra choices; rules; save restoration; character sheet |
| Missing or intentionally excluded | nested blocking continuations; Java-style loss/transfer selection; full death lifecycle; hardcore behavior; `sectionview` browser; Java save import |

## 2. Re-audit method

This pass did not accept module names, state fields, compatibility statuses, or
checklist marks as proof. It instead:

1. enumerated the Java model, executable node, runner, undo, and save classes;
2. compared every rules-bearing Java node's parsed attributes and action flow to
   the corresponding Lua dispatch;
3. traced whether Lua actions execute in the section coroutine or directly from
   `Game:_choose`;
4. compared state mutations, effect ordering, undo records, and reload paths;
5. checked actual books 1–6 uses, including rare fight hooks, `price`, `visit`,
   `revisit`, `field`, `sectionview`, and book-specific starter data; and
6. reviewed what the automated tests and audit tools actually establish.

Pure Swing layout was excluded except where the UI supplies a rules-relevant
choice, such as selecting an item to lose, choosing an ability, using a
blessing, selecting a ship, or resuming a blocked executable.

## 3. Confirmed cross-cutting defects

### 3.1 Nested blocking execution — **Partial; combat hooks implemented**

Java's `ExecutableRunner` and nested `ExecutableGrouper` objects allow a group,
while-loop, fight hook, use effect, transaction event, or result branch to stop
at an inner action and later resume at the exact child.

Lua now persists an execution-frame stack and runs combat-hook programs in a
dedicated resumable coroutine. Round and damage hooks record their combat phase,
pending damage, owner path, and next enemy attack, and reload reconstructs the
hook before combat continues. Other nested programs are still invoked from
`Game:_choose` without an equivalent frame:

- optional `group` children;
- market `sold`/bought programs;
- some outcome/check children; and
- embedded effect programs.

Combat hooks can now suspend for an inner difficulty check or destination and
resume through a `combat_continue` action; leaving through a hook destination
terminates the combat frame. The same guarantee is not yet available to groups,
trade events, outcomes, or embedded use effects.

**Required plan:** replace the single coroutine/path reconstruction hybrid with
a serializable frame stack. Each frame needs owner path, child index, local
branch/loop state, and a parent continuation. All executable containers and
combat hooks must use the same stepping API.

### 3.2 Declared attributes are frequently ignored — **critical**

`Compatibility.assert_declared` rejects an attribute only if it never appeared
on that tag in the corpus. It does not reject an observed attribute that the Lua
handler ignores. Consequently `partial` declarations permit silent semantic
fall-through. Major examples include:

- `set`: `modifier`, `cache`, several item-derived forms, and optional action
  behavior;
- `adjust`: profession, title values/defaults, ship, crew, ability modifier,
  and threshold variants;
- `tick`/`gain`: title patterns/values, price, special, bonus/tag operations,
  caches, effects, and several fleet forms;
- `lose`: chance, fatal, `itemat`, selection, price, cache, blessing,
  resurrection, and exact ship/cargo/crew behavior;
- conditions: `safeaddgod`, `using`, group semantics, some wildcard/filter
  forms, and Java's natural/affected modifiers; and
- trade/item nodes: replacement, buy tags, quantity limits, flags, filters, and
  effect programs.

**Required plan:** define per-handler consumed attributes, fail when an
executable node reaches an unimplemented observed form, and add a fixture before
moving each attribute from partial to supported.

### 3.3 The automated parity gate is structural, not behavioral — **high**

`audit-koreader-reachability.py` follows literal `section` destinations from
six `New.xml` roots and checks tag names against regular-expression matches in
`game.lua`. It does not model conditions, variables, payment, death, random
outcomes, return history, extra choices, or dynamically enabled actions. A
handler containing only a message and `return` satisfies the dispatch test.

The current 4,405-section result also does not mean 4,405 sections are playable;
it means their files are connected by a syntactic destination graph. The test
suite now includes an executable Lua harness for forced-random and blocking
combat-hook save/reload scenarios. Coverage is not yet broad enough to validate
all state transitions, continuation ordering, saves, or Java-derived outcomes.

**Required plan:** retain the structural gate, but add a Lua test harness and
table-driven Java-oracle scenarios with deterministic dice. Add authored
end-to-end paths for every rare construct and compare state plus available
actions after every step and reload.

## 4. System-by-system second-pass findings

### 4.1 Character creation and derived statistics — **Partial**

**Confirmed implemented:** the plugin reads the selected book's profession
scores, named starter, gender, Rank, Stamina, money, and top-level starting
items. This removes the previous hard-coded book-1 character table.

**Still incomplete:**

- Runtime Defence reads are now derived from natural COMBAT, Rank, selected
  armour, and active effects. The legacy saved scalar and sheet presentation
  still need removal, and rule-specific derivation needs oracle coverage.
- General item construction now preserves whether the XML node was a weapon,
  armour, or tool and removal clears selected equipment slots.
- Natural, affected, testing, and value-purpose ability reads are not equivalent
  to Java. Lua has a natural-stat table but most mutations and consumers bypass
  its intended distinction.
- Positive divided effects now use Java's upward rounding. Target/divide/add
  ordering and cumulative multipliers still differ.
- Rank advancement, maximum-Stamina advancement, and caps need oracle coverage.

### 4.2 Conditions, variables, expressions, and control flow — **Partial**

**Confirmed implemented:** common codeword/title/god/profession/gender/item/
money/variable/ability predicates, arithmetic expressions, negation, and common
if/outcome forms exist.

**Still incomplete or unsafe:**

- Unknown identifiers commonly resolve to zero, which can turn unsupported
  model expressions into plausible but incorrect decisions.
- Natural/affected ability modifiers, `safeaddgod`, `using`, title-value, cache,
  ship/crew/cargo, and item-filter edge cases do not match Java completely.
- `set` and `adjust` implement only subsets of their Java multi-model behavior.
- Optional groups execute their children outside the resumable coroutine.
- While loops have no serializable child frame and use a variable-defined loop
  approximation rather than a general Java runner state.
- Conditional chain correctness is not tested under nested blockers and reload.

### 4.3 Navigation, visits, payments, books, and rules — **Partial**

**Confirmed implemented:** local/cross-book destinations, installed-book checks,
basic alive/dead gating, basic sailing state, fixed/temporary rule lookup, and a
visit history record exist.

**Still incomplete or incorrect:**

- Java `GotoNode` supports flags, prices, codeword gating, empty variables,
  dock transitions, `visit`, `revisit`, sailing, and continuation state. Lua's
  goto handler implements only a subset.
- The global persistent `models.visits` suppression is not an established
  equivalent of Java's action-instance `keepEnabled` behavior and can hide an
  action after reloading a section when Java would reconstruct it differently.
- Payment validates neither the complete item/tag/currency price nor atomic
  affordability in all goto paths; some paths clamp money to zero.
- Fixed rules have an API but no player-facing new-game selection. No current
  book declares temporary rules, so that path lacks authored verification.
- A fallback now offers an arranged resurrection or loads the configured book
  death section when no action remains; exact Java death-menu timing is untested.
- `sectionview` is intentionally excluded; this is documented rather than
  parity.

### 4.4 Items, equipment, effects, and use actions — **Partial**

**Confirmed implemented:** structured item records, basic matching, equipment
slots, simple aura/wielded/tool effects, and limited-use actions exist.

**Still incomplete or incorrect:**

- Item type is now retained by the common constructor and selected slot IDs are
  cleared on common removals; unusual chained/replacement paths still need tests.
- Java automatically chooses or recalculates relevant equipment under rules
  which Lua does not reproduce.
- Effect chains, cumulative multipliers, ordering, potion consumption, wildcard
  abilities, and purpose-specific application remain incomplete.
- `UseEffect` can execute nested XML. Lua's use action only applies one direct
  ability mutation and does not run a resumable embedded program.
- `replace`, `buytags`, add/remove tags, `using`, `itemat`, groups, `kept`, and
  interactive ambiguous loss are not complete.
- Quantities are inconsistently merged, split, filtered, sold, and transferred.

### 4.5 Blessings, gods, curses, diseases, and poisons — **Partial**

**Confirmed implemented:** records exist, simple affliction effects participate
in ability reads, cumulative entries are represented, and Defence/injury
blessings have narrow combat handling.

**Still incomplete or incorrect:**

- Java blessing types include ability reroll, luck, storm, travel, Defence,
  injury, disease/poison prevention, and wrath, with optional consumption and
  confirmation. Most are absent.
- Ability-check failure does not offer the Java ability-blessing reroll choice.
- Affliction immunity/prevention, attached items, duplicate rules, named versus
  wildcard lifting, lift prompts, and restoration are incomplete.
- Some mutation paths store boolean afflictions rather than structured records,
  bypassing effects and cumulative behavior.
- God effects and compatibility/exclusion rules are incomplete.

### 4.6 Gain, loss, tick, rest, price, and undoable mutation — **Partial**

**Confirmed implemented:** common scalar mutations, simple optional actions,
Stamina-to, wildcard money/item loss, full/fixed rest, and a narrow Shard price
action exist.

**Still incomplete or incorrect:**

- `ability="?"` and all-ability selection are not implemented for general
  gain/loss nodes; an unsupported key can be mutated instead.
- Chance-based item loss, fatal damage, injury protection, selection among
  eligible items, `itemat`, cache targets, title values/patterns, and effect/tag
  operations are missing.
- Ship/crew/cargo mutation support is split across shortcuts and does not cover
  all Java forms or ambiguous selection.
- Price flags and dependent actions are only approximated; full PriceNode
  enablement, payment grouping, rollback, and continuation are not reproduced.
- Undo snapshots are action-wide, not Java's linked roller/mutation undo chain;
  nested changes cannot be attributed and replayed accurately.

### 4.7 Random, checks, outcomes, training, and reroll — **Partial**

**Confirmed implemented:** common dice formulas, stored signed results,
multi-ability buttons, common adjustments, outcome ranges, training selection,
and snapshot-based reroll paths exist.

**Still incomplete or incorrect:**

- Java consumes purpose-specific ability effects/potions and offers an ability
  blessing after a failed check. Lua does neither completely.
- Rank, random, difficulty, and training reload/undo behavior is not exercised
  by executable tests.
- A reroll restores state but does not reconstruct the action/continuation tree;
  random and training rerolls do not reproduce all original flag, result prose,
  outcome execution, `exp`, variable, blessing, or continuation behavior.
- Loss-node rollers and other roll-linked mutations are not rerollable with
  Java ownership semantics.
- Pending check branches are reconstructed from paths, not serialized as a
  nested executable frame.

### 4.8 Combat — **Partial; high-risk**

**Confirmed implemented:** serializable enemy Stamina/round/group state, basic
attack and defence rolls, grouped opponents, player-first, multiple enemy
attacks, pre-damage, alternative damaged ability, flee thresholds, player flee,
common damage logs, `noarmour`, and narrow Defence/injury blessings exist.

**Still incomplete or incorrect:**

- Blocking fight hooks cannot suspend and resume. This breaks reachable combat
  content, including book 5 section 689.
- Hook ownership is paired globally by ordinal position rather than a proven
  Java-equivalent structural relationship.
- `useCache`, cached combat values, general modifiers, attack/Defence bonuses,
  luck/wrath, exact skip/cannot-win/cannot-lose rules, and complete undo are
  absent or approximated.
- Stalemate detection uses maximum rolls only and offers skip solely when both
  sides cannot damage; Java distinguishes more states and hook effects can
  change whether progress is possible.
- Death, fatal damage, resurrection, and post-fight route ordering do not have
  behavioral parity tests.

### 4.9 Caches and transfers — **Partial**

**Confirmed implemented:** persistent named caches, basic limits and filters,
money multiples/charges, and direct item/money actions exist.

**Still incomplete or incorrect:**

- Freeze/availability lifecycle and unnamed cache behavior differ.
- Transfer direction, limit, price, include/exclude filters, null endpoints,
  forced/optional blocking, and item selection are incomplete.
- Some transfer paths move all source items regardless of authored filters.
- Cache actions and nested continuations lack behavioral save/reload tests.

### 4.10 Ships, crew, cargo, markets, and trade events — **Partial**

**Confirmed implemented:** basic ship types/capacities, active ship, dock, cargo,
crew quality, simple selection, and common ship/cargo/crew transactions exist.

**Still incomplete or incorrect:**

- Ambiguous multi-ship loss/transfer and the ship swap workflow are missing.
- Cargo is stored as repeated strings rather than Java-equivalent typed units;
  matching, quantities, and partial transactions are simplified.
- Conditional price adjustments, flags, finite quantities, initial-crew forms,
  buy tags, replacements, item effects, and live re-enablement are incomplete.
- Market entries are often shown even when unusable and fail only after being
  chosen; Java action availability responds live to state.
- Transaction hooks that block cannot preserve their continuation.

### 4.11 Resurrection and death lifecycle — **Partial; high-risk**

**Confirmed implemented:** a basic resurrection record can be arranged,
consumed, charged, and routed; dead/alive destinations have basic gating.

**Still incomplete or incorrect:**

- Supplemental and replacement arrangements, god/flag eligibility, exact cost,
  restoration, and selection are incomplete.
- A centralized fallback now uses the active book's configured `Death` section
  when no action remains, but it is not yet the complete Java death transition.
- Fatal loss, injury blessing, combat death, curse/effect cleanup, ship loss,
  resurrection offer, and route order are not integrated as one lifecycle.
- A player can remain in a dead state with inappropriate actions because action
  availability is not listener-driven as it is in Java.

### 4.12 Save/load, RNG, undo, and hardcore — **Partial; high-risk**

**Confirmed implemented:** schema validation/migration scaffolding, stable XML
paths, per-section applied/completed sets, combat records, transactional rollback,
and KOReader autosave calls exist.

**Still incomplete or incorrect:**

- The RNG journal now replays an existing saved suffix when its cursor is behind
  the draw list. Complete deterministic restoration still needs behavioral
  coverage for every mid-interaction and reroll boundary.
- Reload reconstructs state by rewalking XML instead of restoring an executable
  frame stack. Nested interactions and dynamically generated action context can
  be lost or replayed.
- Saved pending actions contain summaries which are not used to restore most
  action-specific data.
- Invalid/corrupt saves are now reported instead of being replaced silently;
  backup selection and repair/recovery UI remain absent.
- Migration coverage is narrow; no Java save import exists.
- Hardcore is an unused boolean and has no gameplay or save-policy behavior.

### 4.13 Persistent choices and presentation-linked rules — **Partial**

**Confirmed implemented:** keyed extra-choice storage/address activation, maps,
images, action pagination, a basic character sheet, and a basic ship listing.

**Still incomplete or different:**

- Extra-choice acquisition is not the Java visible/blocking interaction and its
  styled content is not preserved.
- The sheet omits derived Defence, current/max Stamina detail, equipment state,
  effects, typed afflictions/blessings, codewords, titles, gods, resurrection,
  persistent choices, and item-use/equipment management.
- `field` inline read-only rendering is a reasonable KOReader adaptation.
- `sectionview` is intentionally excluded, so strict Java feature parity is not
  achieved even though the difference is documented.

## 5. Exhaustive Java gameplay coverage ledger

This section is the completeness cross-check. **Partial** means that at least
one Java behavior is absent or materially different, even when a Lua module or
tag handler exists. “N/A presentation” is reserved for code with no game-state,
choice, availability, navigation, save, or rules consequence.

### 5.1 Execution, parsing, navigation, and persistence classes

| Java source of truth | Responsibility | KOReader status | Remaining parity gap |
| --- | --- | --- | --- |
| `Node`, `ParserHandler`, `DynamicSectionLoader` | Build typed node tree and resolve models | **Partial** | Lua parses a generic tree; type-specific validation and ownership are deferred to one large dispatcher. |
| `Executable`, `ExecutableGrouper`, `ExecutableRunner` | Ordered, nested, resumable execution | **Partial — critical** | No serializable nested frame stack; only the section coroutine can truly suspend. |
| `ActionNode`, `Flag` | Live action availability and flag listeners | **Partial** | Actions are snapshots and do not generally re-enable/disable from state listeners. |
| `GroupNode`, `IfNode`, `WhileNode` | Compound actions and nested control flow | **Partial — critical** | Nested blockers, child index, loop state, undo, and reload are not equivalent. |
| `Address`, `Books`, `GotoNode`, `ReturnNode` | Addresses, book metadata, travel, visit, return | **Partial** | Payment, flags, history/revisit, dock/sail side effects, and saved execution state differ. |
| `SectionNode`, `LoadableSection`, `XMLPool` | Section lifecycle, loading, saved executable properties | **Partial** | Lua reconstructs from paths and applied/completed sets rather than restoring node execution properties. |
| `Loadable`, `LoadableHandler`, `LoadableNode`, `XMLOutput` | Java XML save/load protocol | **Missing by format** | Lua has its own schema; Java save import/export and equivalent rehydration do not exist. |
| `UndoManager`, `Roller`, `DiceExpression`, `Expression` | Roll ownership, undo chain, dice, arithmetic | **Partial — high** | Snapshot undo is not Java's owned chain; saved RNG is not replayed; some resolver semantics differ. |
| `ActiveRuleset` | Fixed and per-book rules | **Partial** | Storage/lookup exists, but selection UI and rule-specific effects such as exact Defence behavior are incomplete. |

### 5.2 Complete executable/content-node ledger

| Java node class | XML element(s) | KOReader status | Missing or different behavior |
| --- | --- | --- | --- |
| `ChoiceNode` | `choice` | **Partial** | Full conditions, payment, listener-driven availability, and revisit behavior. |
| `GotoNode` | `goto` | **Partial** | Flags/codewords/emptyvar, full prices, visit/revisit lifecycle, dock/sail, continuation. |
| `ReturnNode` | `return` | **Partial** | Exact eligible-history semantics and nested continuation. |
| `IfNode` | `if`, `elseif`, `else` | **Partial** | Attribute completeness, listener updates, nested blocker/reload behavior. |
| `GroupNode` | `group` | **Partial — critical** | Inner blockers and saved current-child/undo state. |
| `WhileNode` | `while` | **Partial — critical** | General runner semantics and serializable inner continuation. |
| `SetVarNode` | `set` | **Partial** | Modifier/cache/item/dock expressions and optional execution variants. |
| `AdjustNode` | `adjust` | **Partial** | Title values/defaults, models, thresholds, modifiers, ship/crew/item variants. |
| `TickNode` | `tick`, `gain` | **Partial** | Prices, choices, titles, effects, tags, bonuses, caches, fleet forms, linked undo. |
| `LoseNode` | `lose` | **Partial — high** | Selection, chance, fatal/injury, itemat, caches, blessing/resurrection, fleet forms. |
| `PriceNode` | `price` | **Partial** | Full live enablement, grouped payment, rollback, currency/item forms, continuation. |
| `RestNode` | `rest` | **Partial** | Dice/multi-use variants, exact listener behavior, and roll-linked undo. |
| `RandomNode` | `random` | **Partial** | Full flag/effect/undo/reload semantics and deterministic replay. |
| `DifficultyNode` | `difficulty` | **Partial** | Ability-purpose effects, potion use, failed-roll blessing choice, exact undo/reload. |
| `RankCheckNode` | `rankcheck` | **Partial** | Owned reroll/continuation and executable reload verification. |
| `TrainingNode` | `training` | **Partial** | Natural-stat semantics, exact undo/reload, effects, and all continuation cases. |
| `RerollNode` | `reroll` | **Partial — high** | Does not reinvoke the complete original Roller plus owned mutation chain. |
| `OutcomeNode`, `OutcomesTableNode` | `outcome`, `outcomes` | **Partial** | Complete flags/branches and nested blocking continuation. |
| `DifficultyResultNode` | `success`, `failure` | **Partial** | Exact owner association and nested continuation across reload. |
| `ItemNode`, `ItemGroupNode` | `item`, `weapon`, `armour`, `tool`, `items` | **Partial — high** | Common kind preservation works; replace, quantity, flags, selection, groups, effects, and tags remain. |
| `EffectNode` | `effect` | **Partial** | Full chains, ordering, cumulative behavior, purposes, embedded use programs. |
| `ItemFilterNode` | `include`, `exclude` | **Partial** | Not applied consistently to every item loss/transfer/trade context. |
| `CacheNode` | `itemcache`, `moneycache` | **Partial** | Freeze/lifecycle, unnamed caches, exact availability, saved blocking selection. |
| `CacheNode.AdjustMoneyNode` | `adjustmoney` | **Partial** | Exact target/group/undo/continuation behavior. |
| `TransferNode` | `transfer` | **Partial — high** | Filters, endpoints, limit, price, forced/optional selection, continuation. |
| `MarketNode` | `market` | **Partial** | Live entry state, exact nonblocking outer execution, transaction availability. |
| `TradeNode`, `BuyNode`, `SellNode` | `trade`, `buy`, `sell` | **Partial — high** | Quantity, conditional price, flags, tags, replacement, effects, all fleet cases. |
| `TradeEventNode` | `sold`/Java `bought` | **Partial** | Blocking child programs cannot preserve parent transaction continuation. |
| `FightNode` and action cells | `fight` | **Partial — high** | Cache/modifiers/blessings, exact skip states, death, and owned undo remain. |
| `FightNode.RoundNode` | `fightround` | **Partial** | Blocking programs now suspend/resume through a serialized frame; exact pre/round ordering still needs behavioral oracle coverage. |
| `FightNode.DamageNode` | `fightdamage` | **Partial** | Blocking/replacement phases now serialize; complete Java-owned undo still differs. |
| `FightNode.FleeNode` | `flee` | **Partial** | Full enemy/player flee program and nested continuation semantics. |
| `CurseNode` | `curse`, `disease`, `poison` | **Partial — high** | Immunity, lifting choice, items/effects, cumulative rules, continuation. |
| `ResurrectionNode` | `resurrection` | **Partial — high** | Eligibility, supplemental/replacement, payment, death lifecycle, choice. |
| `ExtraChoice` | `extrachoice` | **Partial** | Visible blocking acquisition, styled text, full activation lifecycle. |
| `ImageNode` | `image` | **Implemented / platform-adapted** | KOReader embeds/views the image instead of opening the Java window. |
| `FieldNode` | `field` | **Implemented / platform-adapted** | Inline read-only value replaces Swing's read-only field. |
| `SectionViewNode` | `sectionview` | **Not implemented by decision** | Java sequential/random section browser is excluded from player runtime. |
| `ParagraphNode`, `HeadingNode`, `TextNode`, `TableNode`, `RowNode`, `StyleNode`, `BoxNode` | presentation tags | **Partial presentation** | Simplified layout can still matter where style indicates action state; covered by text audit. |

The factory also knows Java save-only or legacy elements not present in the
books 1–6 content census (for example `saved`, `curses`, style `caps`/`u`, and
Java's `bought` transaction form). They are not evidence of current reachable
book failure, but strict engine/file-format parity would require a deliberate
support or exclusion decision.

### 5.3 Character, collection, effect, economy, and combat models

| Java model | KOReader status | Remaining parity gap |
| --- | --- | --- |
| `Adventurer` | **Partial — high** | Natural/affected/current stats, derived Defence, caps, purposes, death/hardcore, complete save state. |
| `Codewords`, `Flag`, `Title` | **Partial** | Numeric codeword values/listeners, transient flags, patterned/value titles, full serialization. |
| `Item`, `ItemList`, `ItemGroupNode`, `IndexSet` | **Partial — high** | Selection, grouping, identity/quantity, equipped/kept state, filters, listeners, replacement. |
| `Effect`, `AbilityEffect`, `EffectSet`, `UseEffect` | **Partial — high** | Basic division rounding now matches; ordering, chains, cumulative multipliers, use programs, potion purpose/consumption remain. |
| `Blessing`, `BlessingList` | **Partial — high** | Ability/luck/storm/travel/wrath/immunity types, prompt/consumption/permanence. |
| `Curse`, `CurseList` | **Partial — high** | Typed/cumulative instances, attached items/effects, prevention and interactive lifting. |
| `Resurrection` | **Partial — high** | Full eligibility, supplemental/replacement state, integrated death handling. |
| `Ship`, `ShipList` | **Partial — high** | Exact cargo units, multi-ship operations, listeners, loss/swap/selection, complete serialization. |
| Money and named caches | **Partial** | Exact cache identity/lifecycle/freeze, interactive transfer and all adjustment semantics. |
| Extra-choice collection | **Partial** | Acquisition interaction, styled label persistence, exact activation/removal lifecycle. |

### 5.4 Rules-relevant application and UI facilities

| Java facility | Gameplay relevance | KOReader status |
| --- | --- | --- |
| `FLApp` navigation/death/rules orchestration | Chooses active book/section, temporary rules, death and save lifecycle | **Partial — high** |
| `AdventurerFrame` | Selects equipment and exposes complete mutable character state | **Partial** via minimal sheet/actions |
| `ShipFrame`, `ShipSwapDialog` | Multi-ship inspection, active selection, transfer/swap | **Partial / swap missing** |
| `MoneyChooser`, `DocumentChooser` | Rules-relevant money/item/ability selection | **Partial** through action buttons; many call sites missing |
| `SectionBrowser`, `SectionViewNode` | Random/sequential preview | **Excluded by documented decision** |
| `CodewordWindow` | Inspect codeword state | **Missing UI** |
| `SavedGamePreview`, start/load flow | Save selection, corruption feedback, preview | **Partial**; corruption is reported, but only one save exists and preview/recovery are absent |
| `ImageWindow` and map facilities | Reference media only | **Implemented / adapted** |

The following classes are presentation infrastructure and were reviewed but do
not independently define game logic: `AboutDialog`, `AdvancedParagraphView`,
`BasicDebugPane`, `BookEditorKit`, `BoxView`, `CommandButtons`, `ComponentView`,
`DocumentCellRenderer`, `FontChooser`, `ImageView`, `RestrictedFileSystemView`,
`SectionDocument`, `SectionDocumentViewer`, `StartPanel`, `StyledText`,
`StyledTextList`, `TableView`, `WindowProperties`, and ordinary event/listener
interfaces. Their visual differences are tracked in `TEXT_PARSING_AUDIT.md` when
they affect authored text or action presentation.

### 5.5 Feature-parity decision by subsystem

| Subsystem | At Java feature parity? |
| --- | --- |
| Parser/declaration boundary | **No** — declared does not mean semantically consumed |
| Nested execution and continuation | **No** |
| Character creation | **Mostly for current templates; broader character model no** |
| Abilities, Rank, Stamina, Defence | **No** |
| Conditions, expressions, variables | **No** |
| Navigation, visits, rules, death routes | **No** |
| Items, equipment, effects, use actions | **No** |
| Money, prices, caches, transfers | **No** |
| Ships, crew, cargo | **No** |
| Markets and trade events | **No** |
| Gain/loss/tick/rest | **No** |
| Blessings, gods, afflictions | **No** |
| Random/checks/training/outcomes/reroll | **No** |
| Combat | **No** |
| Resurrection and death lifecycle | **No** |
| Saves, reload, RNG, undo, hardcore | **No** |
| Extra choices and rules-relevant sheet/UI | **No** |
| Images/maps and basic book text | **Yes, with KOReader presentation adaptations** |
| `sectionview` desktop browser | **No, intentionally excluded** |

## 6. Revised implementation checklist

The earlier phase checklist describes foundation milestones, not completion of
all game logic. Use this second-pass list for remaining parity work.

### P0 — prevent state corruption and unreachable content

- [ ] Build a serializable executable frame stack for every nested container and
  replace out-of-coroutine `walk` calls.
- [x] Implement serialized blocking round/damage combat hooks, pending-damage
  phases, reload reconstruction, and explicit combat continuation.
- [ ] Add book 5/689 as an executable end-to-end save/reload fixture once the Lua
  behavioral harness is available.
- [ ] Complete centralized death/resurrection routing. A fallback now offers an
  arranged resurrection or the active book's configured death section when no
  authored action remains, but the integrated lifecycle is still incomplete.
- [x] Preserve and report corrupt-save errors instead of silently starting over.

### P1 — behavioral test foundation

- [x] Add a Lua 5.1-compatible executable harness and Java-derived forced-random
  and blocking combat-hook save/reload scenarios.
- [ ] Port deterministic Java-oracle fixtures for every remaining executable node and
  compare state, text-independent action identity, and continuation position.
- [ ] Add save/reload and undo/reroll checkpoints to every blocking scenario.
- [ ] Extend compatibility declarations from “observed” to “consumed by this
  handler,” failing loudly on unsupported attribute combinations.

### P2 — statistics, items, and mutations

- [ ] Complete derived-stat parity. Defence is now derived from natural COMBAT,
  Rank, selected armour, and active effects; XML equipment kind is preserved
  and slots clear on removal, but rule- and purpose-specific behavior remains.
- [x] Apply selected weapon and best matching equipped-tool bonuses, and match
  Java's upward rounding for positive divided ability effects.
- [x] Implement Java effect ordering and upward division rounding, purpose-specific
  `natural`/`noarmour`/`notool` reads, best-tool selection, one-roll potion
  bonuses, disposable charge handling, and serializable embedded use-effect
  programs. Executable Lua scenarios now cover ordering and program execution.
- [ ] Complete set/adjust/tick/gain/lose/price attributes, including interactive
  selections, chance/fatal behavior, tags, titles, caches, and fleet forms.
  Item `addtag`, `removetag`, and `addbonus`, and counter-style title mutation
  attributes are now implemented; the remaining selection/chance/fatal and
  price variants keep this item open.
- [ ] Implement the full blessing/affliction lifecycle. Disease/poison immunity,
  permanent-versus-consumable storage, structured cumulative afflictions, and
  named/all lifting are now implemented and behavior-tested. Ability/luck/travel
  reroll prompts, combat defence/divine-wrath activation, and injury prevention
  remain open.

### P3 — rolls and combat

- [ ] Rebuild reroll around the original serialized roller and its owned undo
  chain, including outcomes, flags, variables, blessings, and nested mutations.
- [ ] Complete combat caches/modifiers/blessings/skip states and hook ownership.
- [ ] Add deterministic grouped-combat, flee, death, resurrection, and reload
  parity scenarios.

### P4 — economy, ships, and persistent facilities

- [ ] Complete transfer filters, endpoints, limits, prices, and selection.
- [ ] Complete live market availability, quantities, tags/replacements/effects,
  conditional pricing, and blocking transaction events.
- [ ] Implement ambiguous ship selection/loss/swap and exact cargo/crew rules.
- [ ] Complete extra-choice acquisition and player sheet/game-state facilities.

### P5 — final verification

- [ ] Exercise every reachable observed attribute combination, not just tag
  dispatch, across books 1–6.
- [ ] Record intentional differences with behavioral acceptance criteria.
- [ ] Re-run this audit and claim full playability only when no reachable
  correctness gaps remain.

## 7. Final assessment

The Phase 0–6 work produced a useful architecture and reduced the amount of
missing infrastructure. It did **not** complete all Java systems. The next work
should focus on execution frames and behavioral tests before adding more
one-off handlers. Without that change, apparently local fixes to combat hooks,
groups, effects, outcomes, trade events, or transfers will continue to lose
their parent continuation and will be difficult to save or undo correctly.

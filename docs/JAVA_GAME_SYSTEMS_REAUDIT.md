# Java game systems second-pass audit

- **Re-audit date:** 2026-09-09
- **Reference:** `flands/*.java`, books 1–6, and their `Adventurers.xml` files
- **Port checked:** `plugins/jafl.koplugin/` at commit `b77cabc`
- **Purpose:** independently challenge the earlier parity claims after Phases 0–6

## 1. Executive conclusion

The KOReader plugin does **not** yet implement all Java game systems. It now has
useful foundations for most major domains, but the second pass confirms that
nearly every rules-heavy domain remains partial. The largest risks are not
unknown XML tag names. They are incomplete semantics behind recognized tags,
and blocking actions executed outside the one coroutine that can suspend.

The most important conclusion is therefore:

> Passing the compatibility and reachability scripts is not evidence of full
> playability or Java parity.

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

### 3.1 Nested blocking execution is not implemented — **critical**

Java's `ExecutableRunner` and nested `ExecutableGrouper` objects allow a group,
while-loop, fight hook, use effect, transaction event, or result branch to stop
at an inner action and later resume at the exact child.

Lua can yield only when `Game:pause_section` is called by `section_runner`.
However, several nested programs are invoked from `Game:_choose`, outside that
coroutine:

- optional `group` children;
- combat `fightround`, `fightdamage`, and enemy-flee hooks;
- market `sold`/bought programs;
- some outcome/check children; and
- embedded effect programs.

An inner difficulty check, goto, fight, market, loss choice, or other blocker
therefore cannot suspend its parent correctly. It may add actions which the
caller subsequently overwrites, or execution may continue past it. Saved state
has no nested continuation stack. This is a reachable defect: book 5 section
689 has a `fightround` containing a difficulty check and failure destination.

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
suite does not currently execute Lua and therefore cannot validate state
transitions, continuation ordering, saves, or exact Java-derived outcomes.

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

- Defence remains a cached scalar initialized at creation. Java recomputes it
  from natural COMBAT, affected Rank, Defence effects, selected armour, and
  active rules. Equipping, removing, replacing, or improving armour does not
  reliably update Lua's scalar.
- General item construction loses the XML element kind in several paths.
  `item_from` sees attributes but not whether the node itself was `weapon`,
  `armour`, or `tool`; purchased or gained equipment can become an ordinary
  item and then cannot equip or affect conditions correctly.
- Natural, affected, testing, and value-purpose ability reads are not equivalent
  to Java. Lua has a natural-stat table but most mutations and consumers bypass
  its intended distinction.
- Java effect division rounds positive values upward; Lua uses floor division.
  Target/divide/add ordering and cumulative multipliers also differ.
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
- Configured default death sections are not invoked when no usable authored
  dead destination remains.
- `sectionview` is intentionally excluded; this is documented rather than
  parity.

### 4.4 Items, equipment, effects, and use actions — **Partial**

**Confirmed implemented:** structured item records, basic matching, equipment
slots, simple aura/wielded/tool effects, and limited-use actions exist.

**Still incomplete or incorrect:**

- Item type loss during construction affects markets, gains, and subsequent
  weapon/armour/tool predicates.
- Equipment removal does not consistently clear slot IDs; duplicate IDs and
  name-only sales/removals can leave stale selections.
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
- There is no centralized death transition using the active book's configured
  `Death` section when authored routes do not handle death.
- Fatal loss, injury blessing, combat death, curse/effect cleanup, ship loss,
  resurrection offer, and route order are not integrated as one lifecycle.
- A player can remain in a dead state with inappropriate actions because action
  availability is not listener-driven as it is in Java.

### 4.12 Save/load, RNG, undo, and hardcore — **Partial; high-risk**

**Confirmed implemented:** schema validation/migration scaffolding, stable XML
paths, per-section applied/completed sets, combat records, transactional rollback,
and KOReader autosave calls exist.

**Still incomplete or incorrect:**

- The RNG journal appends draws but never replays saved draws; its cursor is not
  used to source deterministic values. Persisting it does not make restoration
  deterministic.
- Reload reconstructs state by rewalking XML instead of restoring an executable
  frame stack. Nested interactions and dynamically generated action context can
  be lost or replayed.
- Saved pending actions contain summaries which are not used to restore most
  action-specific data.
- Invalid/corrupt saves are returned as errors by `Save:load`, but the plugin's
  open path can replace a failed load with a new state without a recovery UI.
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

## 5. Revised implementation checklist

The earlier phase checklist describes foundation milestones, not completion of
all game logic. Use this second-pass list for remaining parity work.

### P0 — prevent state corruption and unreachable content

- [ ] Build a serializable executable frame stack for every nested container and
  replace out-of-coroutine `walk` calls.
- [ ] Implement blocking combat hooks first and add book 5/689 as an end-to-end
  save/reload fixture.
- [ ] Add centralized death/resurrection routing with configured book death
  sections.
- [ ] Preserve and report corrupt-save errors instead of silently starting over.

### P1 — behavioral test foundation

- [ ] Run Lua engine tests, not source-text assertions.
- [ ] Port deterministic Java-oracle fixtures for every executable node and
  compare state, text-independent action identity, and continuation position.
- [ ] Add save/reload and undo/reroll checkpoints to every blocking scenario.
- [ ] Extend compatibility declarations from “observed” to “consumed by this
  handler,” failing loudly on unsupported attribute combinations.

### P2 — statistics, items, and mutations

- [ ] Make Defence fully derived and fix equipment-kind preservation.
- [ ] Implement Java effect ordering, rounding, purpose-specific reads, and
  consumable use-effect programs.
- [ ] Complete set/adjust/tick/gain/lose/price attributes, including interactive
  selections, chance/fatal behavior, tags, titles, caches, and fleet forms.
- [ ] Implement the full blessing/affliction lifecycle.

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

## 6. Final assessment

The Phase 0–6 work produced a useful architecture and reduced the amount of
missing infrastructure. It did **not** complete all Java systems. The next work
should focus on execution frames and behavioral tests before adding more
one-off handlers. Without that change, apparently local fixes to combat hooks,
groups, effects, outcomes, trade events, or transfers will continue to lose
their parent continuation and will be difficult to save or undo correctly.

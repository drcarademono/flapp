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
- Life-state matching compares `stamina <= 0` with the `dead` flag. In
  particular, an omitted `dead` flag is false and therefore matches a living
  character. This rule applies equally to `choice` and `goto`, including the
  character-selection and begin-adventure screens.
- Before a profession has been selected there is no active adventurer, matching
  the Java application. The new-game template's initial 0/0 Stamina is therefore
  not treated as death, and all six profession choices remain available.
- Java's `StartPanel` asks the player to choose an installed book before starting
  a new game. KOReader now does the same: **New adventure** first lists every
  installed book, then opens that book's `New.xml` profession selection. A book
  is considered installed when its `New.xml` entry section exists, so all six
  bundled books remain available even when upgrading from a package layout that
  omitted optional metadata files.
- Installed releases prefer their bundled content pack over `jafl_content_root`.
  This prevents an old external-content setting containing only book 1 from
  masking bundled books 2–6 and incorrectly enabling missing-book boundaries
  such as book 1, section 330.
- `not="t"` performs a real boolean inversion. In Lua this is implemented with
  an explicit branch rather than an `and/or` pseudo-ternary, because a false
  inverted result would otherwise fall through to the original true value. Thus
  section 330 suppresses its book-missing block when book 2 is installed and
  continues to the Wishport destination.
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

## Other Java game systems

The same ordered interpreter handles the rest of the playable XML vocabulary:

- **Conditions:** codewords (including AND/OR lists), titles, gods, profession,
  gender, inventory, weapons, armour, tools, money, ticks, variables, flags,
  blessings, curses, diseases, poisons, resurrection, installed books, abilities,
  negation, and alive/dead state.
- **Character effects:** ability, Rank, maximum/current Stamina, money, codeword,
  title, god, flag, blessing, curse, disease, poison, resurrection and inventory
  gains/losses. Wildcard inventory and money losses are supported.
- **Rolls and outcomes:** authored dice counts and adjustments, stored roll
  variables, numeric single/range/or/plus outcome ranges, difficulty and Rank
  checks, and success/failure branches. An `<outcomes>` container dispatch can contain
  either numeric `<outcome>` entries or direct `<success>`/`<failure>` entries;
  the latter resume the matching destination after a check, as used by book 1,
  section 257.
  A matching numeric `<outcome section="…">` creates and blocks on its authored
  destination just like Java's `OutcomeNode`-owned `GotoNode`; its description is
  used as the action label. This covers travel tables such as book 2, section 101.
- **Navigation:** forced and optional gotos, cross-book travel, alive/dead routes,
  section history, and return actions.
- **Economy:** item/weapon/armour/tool buy and sell entries, affordability and
  ownership checks, repeated market transactions, and persistent item/money
  caches and transfers. Java's `MarketNode.execute()` enables the table and
  immediately continues section execution; it never requires a purchase or
  sale. KOReader's separate market screen therefore puts **Leave market** first,
  which resumes at the node after `<market>` without changing inventory or money.
- **Advancement and death:** training rolls, capped ability increases,
  resurrection arrangements and consumption, and authored post-death recovery.
- **Fight extensions:** pre-damage, alternate Defence, alternate damaged ability,
  multiple attacks, player-first control, flee thresholds, damage hooks,
  replacement damage, and fight-associated round/damage/flee nodes. Associated
  nodes are paired before execution, mirroring `FightNode.hookupNodes()` rather
  than accidentally running as ordinary post-fight content.

Pure presentation/container tags (`section`, `p`, headings, emphasis, boxes,
tables, text and grouping nodes) recurse through their children while preserving
mixed-content order. Images are resolved by the content catalog and shown by the
KOReader view.

Interactive text remains part of the prose at its authored XML position. An
explicit difficulty/random label is displayed before the interaction pauses; if
the element is empty, the same kind of default instruction as Java is generated.
When a forced check occurs inside a paragraph, execution defers its pause until
the paragraph has finished rendering. The whole containing sentence is therefore
visible before the roll, while nodes after the paragraph remain unexecuted.
Some older sections, including book 2 section 499, put an inline check directly
under `<section>` with no paragraph wrapper. In that form, the interpreter renders
the following text and pauses immediately before `<outcomes>`, so the complete
sentence is visible but result-dependent branches cannot execute early.
After the roll, the coroutine first finishes the containing sentence and reaches
the matching outcome destination, then appends the roll summary. This prevents a
result from splitting a sentence, as previously happened in book 2, section 499.
Text-node whitespace is condensed, spaced hyphens become en dashes, and three
periods become an ellipsis, matching `ParserHandler.condenseContent()`.

Java constructs and displays the complete section document before its separate
`ExecutableRunner` pauses on an action. KOReader mirrors that distinction for a
forced `goto` embedded in a paragraph: it renders the goto's label and the rest
of the paragraph, but does not execute state changes or expose actions after the
goto. Execution still pauses at the goto. This keeps sentences such as book 2,
section 289's “If not, the brigands kill you.” intact. Conditions using both
`cache` and `shards` compare the requested amount with that money cache rather
than the adventurer's carried Shards.
Action attributes are cumulative rather than mutually exclusive: for example,
`<lose item="*" shards="*">` removes both all possessions and all carried money
before rendering the remainder of the paragraph.

The same display-before-block rule applies to forced gotos inside `if`/`elseif`/
`else` branches even when there is no paragraph wrapper. Generated goto text and
the rest of the selected branch are rendered before execution pauses. Whitespace-
only XML text between conditional tags does not terminate an if/elseif/else chain.
Thus book 2, section 409 displays the complete “If not, Turn to 353.” branch and
uses the same text for its action.

Conditional content has separate presentation and execution states, as it does
in Java. The prose for every `if`/`elseif`/`else` branch remains in the section
document, while only the branch whose conditions are met executes mutations and
enables its destinations. Empty `<goto/>` elements also receive their generated
destination text while a disabled branch is being presented. Consequently book
5, section 150 shows all of its “If you have…” instructions, but exposes only
the destination appropriate to the adventurer's current codewords.

A forced goto directly under a section follows the same rule. It marks execution
as blocked, but the display-only pass consumes the remaining sibling text before
the coroutine yields at the section boundary. This is important for XML that
does not use a `<p>` wrapper: book 2, section 20 therefore retains the authored
period after its generated destination text.

Generated local goto text also follows Java's sentence-aware capitalization.
It uses “Turn to” at the start of a sentence and “turn to” when embedded after
ordinary prose. For example, the source phrase `and <goto section="118"/>` in
book 2, section 20 is displayed as “and turn to 118.”

The same shared display generator now supplies Java-compatible text for empty
`random`, `difficulty`, `rankcheck`, `reroll`, `training`, `lose`, `tick`, item,
weapon, armour, tool, image, resurrection, extra-choice, and field elements.
Sentence-sensitive commands use the already-rendered document context. Default
text is suppressed beneath `group`, `effect`, and `tradeevent`, matching those
Java parents' `hideChildContent()` behavior. Authored element content always
takes precedence over a generated label.

Forced random rolls use the same display-before-block boundary as checks. Text
following the `<random>` element remains visible through the end of its paragraph
or up to its `<outcomes>` container. Thus book 2, section 26 initially displays
“Roll two dice:” rather than losing the authored colon; after the roll, execution
continues into the matching outcome.

Sentence-aware capitalization applies to the inline prose, just as it does to
Java's clickable document span. KOReader additionally repeats available actions
in a standalone numbered menu. That menu capitalizes the first letter because
each button is an independent UI label; it does not alter the inline text. Thus
book 2, section 75 reads “but roll two dice…” in the passage and shows
“1. Roll two dice” in the action menu.

Other resumable blockers (`training`, `fight`, `market`, forced `return`, and
`reroll`) use a non-executing look-ahead renderer. The parser records each node's
parent and mixed-content position, previews all following siblings through the
section boundary, and keeps that preview separate from executed text. Choosing
the action discards the preview and resumes the coroutine at the original XML
position, so later mutations still execute exactly once. This prevents commas,
periods, explanatory clauses, and later paragraphs after any blocking tag from
being cut off without applying their game effects prematurely.

Interaction summaries are appended only after the coroutine has rendered its
authored continuation. Training and combat therefore keep the complete book text
together, followed by a separate blank-line-delimited result. In book 2, section
423, “Training roll: N.” appears after the sentence ending “turn to 97.” rather
than between “Roll one die” and the comma that follows it.

Optional checks register adjacent `success` and `failure` nodes as dormant
branches instead of treating an absent result as failure. The branch descriptions
are not concatenated into section prose and their destinations are not offered
until the roll exists. After rolling, the matching branch becomes an action while
the unrelated ordinary choices remain available. Section-local random and
difficulty result slots are cleared whenever a new section loads, preventing a
previous page's roll from activating a new page's branch.

An `outcomes` container may also contain ordinary `choice` nodes alongside its
roll-dependent branches. If no check result exists—because a surrounding
condition prevented the check from being offered—those ordinary choices still
execute and remain usable, while `success` and `failure` stay dormant. In book 2,
section 543, possessing a parchment exposes the forced SCOUTING roll; without a
parchment, the player instead receives the authored “No parchment” exit.

Main adventure prose and generated choice buttons use the same ordinary
12-point book-reading size. Choice labels are not bold, leaving the title and
status controls as the visual hierarchy rather than oversized action text.

Action menus are split into pages of at most six choices. Previous and Next
controls appear only when another page exists, the title shows the current and
total page numbers, and displayed choice numbers remain their stable global
action indexes. Map, Sheet, and Close stay available on every page. This keeps
large markets and other long choice lists within the screen while retaining
touch and key-only navigation.

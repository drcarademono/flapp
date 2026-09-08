# JaFL to KOReader port plan

## 1. Goal and definition of done

Port JaFL's game engine and reading experience to a native KOReader plugin so a
player can start, play, save, close, and resume a game on an e-ink reader without
a Java runtime.

The first production release is complete when it:

- installs as a conventional `jafl.koplugin` and opens from KOReader's main menu;
- supports touch and physical-key navigation on the device classes supported by
  KOReader;
- can play all reachable paths in the six books currently present in this
  repository, including travel between books;
- implements character creation, checks, dice, combat, possessions, money,
  markets, caches, ships, codewords, blessings, curses, resurrection, maps, and
  illustrations;
- saves atomically, autosaves at safe interaction boundaries, and restores the
  exact pending interaction after restart;
- does not corrupt a game if KOReader is suspended or terminated during a save;
- has automated parity fixtures for the content language and engine rules, plus
  smoke tests on at least one touch device and one key-driven device or emulator;
- ships only code and content for which redistribution permission has been
  confirmed.

This is a rewrite of the runtime, not a JVM embedding exercise. KOReader plugins
are Lua code using KOReader's own widgets and event loop; bundling a JVM would be
large, difficult to support across devices, and poorly matched to KOReader's
e-ink interaction model.

## 2. What is being ported

### Existing assets worth preserving

The repository already separates most content from the Swing UI:

- `book1` through `book6` contain 4,450 XML files. These include six
  `Adventurers.xml` files and six sets of starting-character XML, so the actual
  section count is slightly lower. All files are well-formed XML under a basic
  parser check.
- `books.ini` declares twelve books, but only books 1–6 and their illustrations
  are present. The plugin must report unavailable books rather than offering a
  broken transition.
- each installed book has `book.ini` metadata for its map, death section,
  codewords, and optional rules.
- `Rules.xml`, `QuickRules.xml`, maps, illustrations, and localized Java
  properties are source material for the reader UI.
- the Java node classes are the behavioral specification for the XML tags and
  their edge cases. There are 69 distinct tags in current content, while the
  node factory maps executable and presentation elements to specialized
  classes.

### Existing behavior that must be replaced

The Swing document/view classes and windows are not portable. In particular,
`FLApp`, `SectionDocument`, `AdventurerFrame`, `ShipFrame`, `ImageWindow`, and
mouse listeners should inform behavior, but none should be translated line by
line. The reusable specification lives mainly in:

- model and rules: `Adventurer`, `Item`, `ItemList`, `Ship`, `ShipList`,
  `Blessing`, `Curse`, `Effect`, `Codewords`, `Flag`, and `ActiveRuleset`;
- content execution: `Node` and the `*Node` implementations;
- navigation and resources: `Address`, `Books`, and `SectionNode`;
- persistence: `LoadableHandler`, `Adventurer`, `SectionNode`, `XMLPool`, and
  `ExtraChoice`.

Treat the Java application as the compatibility oracle until the Lua parity
suite replaces it. Do not mix UI state into the new rules engine.

## 3. Decisions to make before implementation

Complete a short, time-boxed technical spike and record the answers in an
architecture decision record (ADR):

1. **Supported KOReader baseline.** Pick the oldest supported KOReader release
   and test its plugin metadata, menu registration, widget, gesture, key-event,
   settings-directory, image, and XML facilities. Develop against a pinned
   KOReader commit/release rather than an unspecified `master`.
2. **XML strategy.** Verify whether the baseline exposes a suitable streaming or
   tree XML parser to plugins. If not, vendor a small pure-Lua parser with its
   license, entity handling, mixed-content ordering, and resource limits tested.
   Do not parse these mixed-content files with patterns.
3. **Content packaging.** Prefer a small code-only plugin with separately
   installed content packs if redistribution rights for the text or artwork are
   unclear. Add content discovery and a friendly setup screen. Bundling content
   is allowed only after a documented license review.
4. **Save compatibility.** Default to a new, versioned Lua save format. Importing
   JaFL `.dat` zip saves is a stretch goal because those archives combine Java
   properties and dynamic XML state. Never overwrite an imported save.
5. **Distribution target.** Start as a side-loaded plugin. Seek inclusion in a
   KOReader plugin index only after confirming its contribution, licensing, and
   maintenance requirements with KOReader maintainers.

Spike exit criteria: a minimal plugin launches on desktop KOReader, displays one
parsed section, follows one choice, writes and reloads a small save, and redraws
correctly after suspend/resume and screen rotation. If an assumption above is
wrong, update this plan before building the complete engine.

## 4. Proposed architecture

Keep the plugin entry point thin and use dependency-injected Lua modules:

```text
plugins/jafl.koplugin/
  _meta.lua                 plugin identity and compatibility metadata
  main.lua                  lifecycle, menu registration, event wiring
  app.lua                   screen/router coordinator
  core/
    game.lua                deterministic state machine
    state.lua               canonical in-memory state and invariants
    commands.lua            validated player intents
    rng.lua                 injectable random source and roll log
    address.lua             book/section addressing and transitions
  content/
    catalog.lua             books.ini/book.ini equivalent
    xml.lua                 parser adapter
    compiler.lua            XML AST -> normalized instruction tree
    schema.lua              tag/attribute validation and diagnostics
    handlers/               one module per rule family
  model/
    adventurer.lua items.lua effects.lua ships.lua caches.lua
    codewords.lua flags.lua resurrection.lua
  persistence/
    saves.lua migrations.lua legacy_import.lua
  ui/
    game_view.lua sheet_dialog.lua choice_dialog.lua dice_dialog.lua
    combat_dialog.lua market_dialog.lua ship_dialog.lua map_view.lua
    setup_dialog.lua error_dialog.lua
  resources/
    strings.lua
  spec/
    unit/ fixtures/ parity/ integration/
```

The content compiler should normalize tag names and attributes, preserve mixed
text/style order, and produce data-only instructions. Handlers evaluate those
instructions against `state` and emit a view model plus a finite set of commands.
The UI renders that model and sends commands back; it never mutates inventory,
stats, or navigation directly.

Model an interaction as an explicit state machine:

```text
load section -> execute automatic nodes -> waiting for player command
             -> apply command -> execute until next wait point -> autosave
```

Wait points include a choice, dice acknowledgement, ability check, market
selection, combat decision, item transfer, resurrection decision, or terminal
state. Explicit wait states make suspend/resume and deterministic testing much
safer than preserving Lua call stacks or widget state.

## 5. Content-language implementation order

Create a machine-readable coverage manifest listing every observed tag and
attribute, its Lua handler, fixture count, implementation status, and any known
Java quirks. Fail loudly with book, section, tag, and attribute context when an
unsupported construct is reached; never silently skip game logic.

Implement in dependency order:

1. **Presentation and navigation:** `section`, `p`, headings, `text`, `desc`,
   `b`, `i`, `caps`, `u`, `image`, `choices`, `choice`, `goto`, `return`,
   `sectionview`, tables/rows/cells.
2. **Variables and control flow:** `set`, `if`, `elseif`, `else`, `while`,
   `group`, `random`, `outcomes`, `outcome`, `success`, `failure`, and variable
   expressions.
3. **Character mutations:** `tick`, `gain`, `lose`, `adjust`, `field`, `item`,
   `items`, `weapon`, `armour`, effects, money, rank, stamina, profession,
   blessings, curses, titles, gods, flags, and codewords.
4. **Checks and time:** `difficulty`, `rankcheck`, `training`, `rest`, and
   `reroll`. All randomness must go through the injected RNG and be recorded in
   the save/audit log.
5. **Complex interactions:** `fight`, `fightround`, `fightdamage`, `flee`,
   `market`, `trade`, `buy`, `sell`, price rules, item and money caches,
   transfers, ships/cargo/crew, resurrection, and extra choices.

For each family, read the matching Java node and model classes, write behavioral
fixtures first, then implement the Lua handler. Preserve known behavior even
where it is surprising; record deliberate corrections separately so they can be
reviewed and regression-tested.

## 6. KOReader interaction design

### Main reading screen

- Use a paged or scrollable KOReader-native text container with large tap
  targets. Executable choices should be numbered and visually distinct, not
  represented only by underlining or color.
- Reserve a compact header/footer for book and section, stamina, shards, and
  unsaved/error state. Allow it to be hidden for a book-like view.
- Map tap/swipe and physical keys to the same semantic commands. Direction keys
  move focus, Enter activates, Back opens a confirmation/history action rather
  than undoing game state silently, and Menu opens plugin actions.
- Refresh only changed regions when safe, but periodically request a full e-ink
  refresh to avoid ghosting. Use KOReader APIs rather than device-specific code.
- Reflow on orientation, DPI, font-size, and theme changes. Do not encode layout
  in book XML.

### Secondary surfaces

- **Adventure sheet:** tabs or sections for abilities, inventory/equipment,
  blessings/curses, codewords/titles, caches, and history.
- **Combat and checks:** show inputs, modifiers, dice, result, and the next legal
  actions. Never require animation.
- **Markets and transfers:** use a focusable list with quantity controls and a
  confirmation summary to prevent accidental purchases on imprecise touchscreens.
- **Ships:** list dock/location, crew, cargo, capacity, and transfer/rename/dump
  actions.
- **Maps and illustrations:** use KOReader's image viewer behavior for zoom/pan;
  provide text alternatives or filenames when an asset is missing.
- **Help:** render quick rules first, with full rules and controls available from
  the menu.

Every modal operation must have a key-only path, an obvious cancel action, and a
minimum touch target suitable for e-ink readers. Avoid timers, hover, right-click,
double-click, drag-and-drop, color-only state, and rapid animation—the desktop
README relies on several of these interactions and they need explicit redesign.

## 7. Persistence and recovery

Store data under KOReader's supported per-user settings/data location, never in
the plugin directory. Use one directory per profile and slot:

```text
jafl/
  settings.lua
  saves/<slot>/state.lua
  saves/<slot>/state.bak
  saves/<slot>/meta.lua
```

The canonical save should contain only data: schema version, plugin version,
content-pack identity/checksum, current address, complete adventurer state,
caches/ships/global flags, section variables, explicit wait state, RNG state or
recorded pending result, timestamps, and hardcore metadata. It must not contain
functions or arbitrary executable Lua loaded from the save.

Save by writing a temporary file, flushing/closing it, validating it by reading
it back, rotating the last good file to `.bak`, and atomically renaming the new
file. Autosave after each resolved command and before KOReader suspend/exit when
the lifecycle permits. On startup, detect an incomplete write and offer the last
good backup. Migrations must be one-way functions over copied data and retain the
original save.

For hardcore mode, document that no client-side implementation can prevent file
copying. Preserve the intended UX—restricted save points and consumed resume—only
after normal saves are proven reliable.

## 8. Verification strategy

### Static content checks

Build a host-side checker that parses every XML and INI file and reports:

- malformed XML, unknown tags/attributes, invalid expressions, and missing IDs;
- broken same-book and cross-book destinations;
- references to absent images, maps, rules, or books;
- impossible/ambiguous handler mappings and untested constructs;
- a tag/attribute frequency report used to track coverage.

### Unit and property tests

Test pure Lua modules outside the KOReader UI where possible:

- dice expressions, seeded RNG, checks, damage, defence, and rerolls;
- stat bounds and death, effects, inventory capacity/equipment, money, caches,
  markets, ships, codewords, blessings, curses, and resurrection;
- expression/control-flow semantics and termination guards for loops;
- save round trips, interrupted-write recovery, corrupted saves, migrations, and
  malicious/unexpected save data;
- invariants such as nonnegative money, capacity limits, unique flags, and the
  absence of unavailable commands.

### Java/Lua parity harness

Before changing the Java code, add a small headless oracle that accepts a fixture
section, initial state, fixed random values, and command sequence, then emits a
normalized event/state trace. Run the same fixture through Lua and diff the
traces. Build fixtures around every tag family and every bug found during manual
play. Golden snapshots should exclude presentation-only differences.

### Integration and device matrix

- Desktop KOReader smoke test: install, launch, create character, choose, roll,
  fight, buy/sell, save, restart, and resume.
- At least one touch Android/Linux device and one key-centric e-ink device or
  emulator: focus order, dialogs, suspend/resume, rotation, frontlight/theme,
  and long-section performance.
- Soak test scripted travel across all six books and repeated save/reload cycles.
- Measure section parse/render latency and peak memory on a low-memory device;
  cache normalized sections with a bounded LRU rather than loading a whole book.
- Run an end-to-end route corpus covering every section that can be reached by
  the scripted states. Track uncovered tags and sections as release blockers.

## 9. Delivery phases and gates

Estimates are ranges for one developer familiar with Lua but learning this code;
re-estimate after each gate.

| Phase | Scope | Exit gate | Estimate |
| --- | --- | --- | --- |
| 0. Discovery | License review, KOReader baseline/API spike, content inventory, ADRs | One-section vertical slice runs and resumes in KOReader | 1–2 weeks |
| 1. Foundations | Plugin shell, parser/compiler, state machine, diagnostics, persistence v1, test harness | Deterministic parse/execute/save loop with CI | 2–3 weeks |
| 2. Playable slice | Character creation, reading UI, navigation, variables, choices, simple checks/items | Curated book 1 route playable by touch and keys | 3–5 weeks |
| 3. Rules parity | Full model, conditions, effects, random outcomes, time, checks, caches | All non-combat/non-trade fixtures match Java | 4–7 weeks |
| 4. Complex systems | Combat, markets, ships, transfers, resurrection, extra choices | All observed tags supported and parity-tested | 5–8 weeks |
| 5. Content/device QA | Six-book validator, maps/images/help, accessibility, performance, recovery | Route corpus and device matrix pass | 3–6 weeks |
| 6. Release | Packaging, install/update docs, license notices, migration policy, beta fixes | Signed/tagged side-loadable beta and rollback instructions | 2–4 weeks |

Expected total: roughly 20–35 developer-weeks, not including delays obtaining
content permission or adding books 7–12. A smaller MVP can stop after phase 2,
but should be labeled a preview because book-wide rule coverage will be absent.

Each phase should land as reviewable changes with tests; avoid a single big-bang
translation. Maintain a demo save and scripted acceptance route so progress is
visible on a real device.

## 10. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Text and artwork copyright or absent code license prevents distribution | Resolve ownership and permissions in phase 0; separate engine from user-supplied content; do not assume repository availability grants redistribution rights. |
| Java behavior is coupled to Swing documents/listeners | Specify commands, events, and invariants in fixtures; port model semantics rather than Java UI structure. |
| Rare XML constructs fail late in a long campaign | Generate complete tag/attribute inventory, validate all content in CI, fail with precise context, and grow parity routes. |
| KOReader internal APIs change | Pin and document a baseline, keep KOReader calls behind UI/storage adapters, and test against the baseline plus latest stable before release. |
| Device termination corrupts saves | Explicit wait states, command-boundary autosave, temp/validate/atomic-rename, backup recovery, and interruption tests. |
| E-ink UX becomes a desktop UI squeezed onto a small screen | Prototype on hardware early; favor lists, pages, focus navigation, large targets, and low-refresh interactions. |
| Full parity takes longer than expected | Ship a clearly marked book-1 preview only if the validator proves its supported route; never silently degrade unsupported mechanics. |
| Huge or malicious content/save files exhaust resources | Apply file/depth/node/loop limits, validate paths and scalar types, and never evaluate save data as code. |

## 11. First implementation backlog

1. Document licensing status for source, book text, and each artwork set.
2. Pin a KOReader release and write the lifecycle/API ADR.
3. Scaffold `jafl.koplugin` with a menu item and empty full-screen widget.
4. Add CI lint/test jobs for the supported Lua runtime.
5. Generate the XML tag/attribute/asset/cross-reference manifest.
6. Complete the parser decision and mixed-content parser fixtures.
7. Define canonical state, commands, events, wait states, and save schema v1.
8. Implement atomic save/recovery and lifecycle tests before substantial rules.
9. Render `book1/1.xml` (or a minimal extracted fixture) with key/touch choices.
10. Add deterministic navigation and variable/control-flow handlers.
11. Build the Java trace oracle and first cross-runtime parity cases.
12. Port character creation and the adventure-sheet read model.
13. Run the phase-2 route on desktop KOReader and two input profiles.
14. Re-estimate phases 3–6 from measured handler and fixture throughput.

## 12. Explicit non-goals for the first release

- embedding Java or reproducing Swing windows;
- network services, cloud sync, multiplayer, achievements, or animated dice;
- books 7–12, which are listed but absent from this repository;
- byte-for-byte compatibility with Java `.dat` saves (import may be added later);
- an in-plugin book editor;
- DRM circumvention or downloading copyrighted content without authorization.

These boundaries keep the initial project focused on a reliable, native,
offline reading-and-playing experience in KOReader.

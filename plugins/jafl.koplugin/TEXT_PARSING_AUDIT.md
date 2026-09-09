# Java/KOReader text parsing audit

This document compares the Java renderer in `flands/` with the KOReader Lua
plugin. It covers the common SAX/document pipeline and every Java node class
that overrides `handleContent()`, generates presentation in `handleEndTag()`, or
implements `hideChildContent()`. This records the current implementation; it
does not claim that every difference is desirable.

## Executive summary

The engines do **not** yet have complete text-presentation parity.

Java first parses the whole section into a styled Swing document and then runs
its `ExecutableRunner`. Conditional or unavailable text remains in the document
but is disabled. KOReader keeps a mixed-content tree and builds a plain string
while executing it. `render_node()` now provides a display-only path around
inactive conditions and blocking gotos, but this emulates Java's two phases
rather than providing an equivalent document model.

Java-compatible plain-text semantics now implemented include authored and
generated text for empty gotos, random/difficulty/rank/training/reroll actions,
losses, ticks, inventory elements, images, resurrection labels, extra choices,
and fields. Generated wording uses the current sentence position. Java's
`hideChildContent()` rule is applied while generating defaults below groups,
effects, and trade events.

Resumable blocking nodes use a separate look-ahead buffer for the rest of the
section. This mirrors Java's parse-before-execute visibility without advancing
the Lua execution coroutine. The buffer is discarded before continuation, so
the same nodes are subsequently executed—not duplicated—as authored.
Generated roll and combat summaries are appended after that continuation has
been rendered, keeping diagnostics out of the middle of authored sentences.
Success and failure descriptions attached to optional checks remain dormant UI
labels until the check is made; they are not flattened into the main prose.

The remaining differences are primarily platform presentation differences:

1. KOReader discards inline styling and Java's enabled/disabled visual state.
2. Some generated descriptions depend on Java-only rich domain objects (most
   notably full resurrection and complex item/use-effect descriptions); KOReader
   provides the authored label and common ability-effect form.
3. Java has node-specific layout for paragraphs, headings, outcomes, choices,
   markets, fields, groups, and combat details. KOReader flattens most of these
   into prose and separate action buttons.
4. Whitespace condensation is similar, but happens at different stages and is
   therefore not identical at every element boundary.
5. KOReader represents inline Java actions as ordinary prose plus accessible,
   paginated buttons rather than clickable styled spans.

## Common XML and whitespace pipeline

| Behavior | Java | KOReader | Status |
| --- | --- | --- | --- |
| Mixed-content order | SAX sends text at each start/end boundary to the active node. | `content/xml.lua` stores strings and child elements in one ordered `children` array. | Equivalent in the parsed tree. |
| Element/attribute case | Element names are lower-cased; node code reads known attribute spellings. | Element and attribute names are lower-cased. | KOReader is more permissive for attribute case. |
| Entity handling | The configured SAX parser resolves XML character/entity references. | Five predefined entities and decimal/hex numeric references are decoded explicitly; unknown entities fail. | Equivalent for shipped content; custom entities differ. |
| DTD/processing instructions | Delegated to SAX configuration. | DTD/entity declarations and non-declaration processing instructions are rejected. | Intentional security difference. |
| Whitespace | `ParserHandler.condenseContent()` collapses Unicode whitespace per accumulated SAX run. Start/end trimming depends on whether the previous node emitted content. | `normalize_text()` collapses Lua `%s` in each stored text node; whitespace-only execution nodes are usually ignored. | Similar, not byte-for-byte equivalent at every tag boundary. |
| Dashes/ellipsis | A hyphen surrounded by spaces becomes an en dash; every `...` becomes an ellipsis. | `normalize_text()` makes the same replacements. | Equivalent for ordinary shipped text. |
| Smart quotes | `simplifyQuotes()` converts curly single quotes to ASCII for matching helpers; displayed text may retain authored quotes. | Entities decode to UTF-8 curly quotes and matching does not globally simplify them. | Potential item/name matching difference, not normally a prose difference. |
| Empty elements | SAX guarantees an empty `handleContent("")` call so nodes can synthesize text. | Empty nodes have no string child; synthesis must be implemented explicitly. | Architectural difference and source of default-text gaps. |
| Safety limits | Parser limits are external. | Explicit 20,000-node and 128-depth limits are enforced. | Intentional defensive difference. |

## Document styling and layout

Java stores text in `SectionDocument` leaves with attributes. It preserves
bold, italic, underline, enabled/highlight state, paragraph alignment, heading
size, and smaller-letter rendering for recognized uppercase ability names.
KOReader sends one plain string to `TextViewer`; `<b>`, `<i>`, `<u>`, and
`<caps>` contribute text but not style.

Consequently Java can visually disable unavailable conditional prose, underline
goto text and bold section numbers, italicize codewords, justify and indent
paragraphs, scale `h1`–`h4`, and render ability names like small caps. KOReader
currently does none of those things. These are presentation gaps rather than
missing words, but the visual result is not an exact Java reproduction.

## Node-by-node audit

### General prose and structure

| Java node/function | Java presentation behavior | KOReader difference |
| --- | --- | --- |
| `SectionNode.handleContent` | Adds top-level prose and owns the complete styled document before execution. | Top-level strings are appended during coroutine execution; display-only continuation is used after forced gotos. |
| `ParagraphNode` | Preserves necessary boundary whitespace, ends with one newline, justifies, and first-line indents. | Adds normalized text and two newlines; no justification or indent. |
| `StyleNode` (`b`, `i`, `u`, `caps`) | Maintains a nested active-style stack and forwards styled text. | Flattens children and loses all styles. |
| `HeadingNode` (`h1`–`h4`) | Bold, scaled text with heading spacing and newline. | Plain text plus a generic double newline. |
| `TextNode` | Captures a reusable `StyledTextList` and preserves styles. | Treated as an ordinary container; no reusable styled-text object. |
| `GroupNode` | Captures/highlights group text and hides generated child content from parent rendering. | Generated child defaults are now suppressed; group highlighting remains unavailable. |
| `RowNode` and box nodes | Build structured rows and boxes. | Flattened; no row or box layout. |
| `FieldNode` | Emits a label, embedded Swing text field, and newline. | Emits the label and spacing; no embedded editable Swing field. KOReader uses separate screens. |
| `SectionViewNode` | Creates styled actionable section-view text. | Generic container; no equivalent section-view action. |
| `ExtraChoice` | Stores styled text for a persistent extra choice and can use its `text=` fallback. | Authored or `text=` presentation is retained; persistence and inline action styling still differ. |
| `WhileNode` | Adds its text once as enable-controlled document content; looping is an execution concern. | Child traversal occurs inside the execution loop, so visible child text can be appended repeatedly. |
| `ImageNode` | Authored text is clickable; empty nodes generate italic `[illustration]`; image opens separately with a title. | Authored text or `[illustration]` is rendered and the image path is exposed; italics/clickable-span presentation differs. |

### Actions and generated text

| Java node/function | Java presentation behavior | KOReader difference |
| --- | --- | --- |
| `GotoNode` | Keeps authored text or generates sentence-aware `Turn to`/`turn to`, or a cross-book title, with underlined/bold spans. | Generated wording now matches; text is plain and duplicated as a separate button. Disabled-link appearance differs. |
| `ChoiceNode` | Builds a description paragraph and separately wired goto, supports `[box]`, and highlights the description. | `plain()` flattens descendants into one button label; layout, styles, and description/destination separation are lost. |
| `RandomNode` | Keeps authored text or generates sentence-aware `Roll/roll one die`, `two dice`, or *n* dice, while later SAX text remains in the document. | Inline wording/capitalization and trailing mixed content match. The separate KOReader menu capitalizes its standalone label. |
| `DifficultyNode` | Keeps text or generates sentence-aware `Make/make a ABILITY roll at Difficulty N`; only initial leaves are highlighted. | Generated wording/case matches; multiple abilities become separate accessible buttons and partial-span styling differs. |
| `RankCheckNode` | Keeps text or generates sentence-aware rank/dice instructions with clickable leaves. | Generated dice/add/subtract wording matches; presentation uses a button. |
| `RerollNode` | Keeps text or generates sentence-aware `Roll again`/`roll again`. | Generated text now matches and reuses the random-roll path; inline styling differs. |
| `ReturnNode` | Makes authored text an enabled/highlighted return action. | Separate Return action when history exists; no Java inline style. |
| `TrainingNode` | Empty nodes generate sentence-aware `Roll/roll ...`; authored content is highlighted. | Generated dice wording now matches; inline presentation differs. |
| `ResurrectionNode` | Keeps text or generates a styled resurrection description. | Authored/`text=` description is retained; fallback and rich resurrection-object wording can still differ. |

### State-changing inline nodes

| Java node/function | Java presentation behavior | KOReader difference |
| --- | --- | --- |
| `LoseNode` | Highlights authored text. Empty nodes synthesize codeword, Stamina, item, Shard, curse, or title text; capitalization is sentence-aware and codewords italic. | Common generated wording is now present and sentence-aware; highlighting, italics, and uncommon domain-specific forms differ. |
| `TickNode` | Keeps text or generates sentence-aware codeword/tick-box wording and tick-box styling. | Common codeword, Shard, title, and generic-tick defaults are present; tick-box visuals and specialized domain forms differ. |
| `ItemNode` | Keeps text or generates a styled item/effect description. | Generates item names and common ability effects; complex chained/use-effect formatting and styles differ. |
| `SetVarNode` | Renders authored text as enabled/highlighted inline content. | Applies state and renders ordinary prose. |
| `RestNode` | Renders authored text as highlighted enabled content. | Applies effects; text is plain. |
| `CurseNode` | Captures a styled reusable effect description. | Flattens text and does not retain the richer description. |
| `TransferNode` | Highlights authored transfer text as one action. | Performs transfer and renders plain child prose. |
| `EffectNode` / `TradeEventNode` | `hideChildContent()` prevents generated internal descriptions being duplicated in the parent. | Default generation is suppressed under these containers; Java-only reusable styled descriptions remain flattened. |

### Results, markets, and combat

| Java node/function | Java presentation behavior | KOReader difference |
| --- | --- | --- |
| `OutcomeNode` | Builds disabled description boxes, optional range or italic codeword labels, and a final goto; enables the selected result. | Evaluates one matching result and creates one action; no full result table or labels. |
| `DifficultyResultNode` | Builds success/failure text and may synthesize a goto paragraph. | Shows a roll summary and one result action; layout and descriptions differ. |
| `MarketNode`, `TradeNode`, `PriceNode` | Build table-like rows, headers, item descriptions, prices, and styled controls. | Dedicated paginated market with synthesized Buy/Sell buttons and Leave action; intentionally different UI and wording. |
| Cache row nodes | Build labels, counts, controls, and component rows. | Separate cache action flow; structured row text is not reproduced. |
| Fight detail/result nodes | Add detail text and controls, including skip/flee affordances and hook-specific prose. | Plain combat log and subsequent actions; typography, incremental controls, and detail layout differ. |

## Text-specific behavioral risks

1. **Complex generated descriptions:** chained items, specialized blessings,
   curses, resurrection objects, and use effects can still be worded less richly.
2. **While-node repetition:** execution and presentation are not fully separate,
   so text inside an authored execution loop can still be appended repeatedly.
3. **Whitespace boundaries:** Lua normalization occurs per stored string rather
   than per SAX accumulation event. Empty/style tags and adjacent whitespace-only
   nodes still need fixture coverage.
4. **Plain choice labels:** `plain()` includes all descendant text without Java's
   description routing, so complex choice/outcome labels can differ.
5. **No disabled styling:** unavailable instructions look like ordinary prose;
   only the action list indicates which destination is usable.

## Parity already implemented

- Mixed-content child order is preserved.
- Ordinary whitespace, spaced hyphens, and ellipses are normalized similarly.
- Authored text around inline checks and forced gotos is retained.
- Inactive conditional prose is retained without executing its state changes.
- Empty gotos generate local or cross-book destination text.
- Local empty gotos use Java-compatible sentence-aware capitalization.
- Nodes with `hidden=` are omitted.

## Recommended implementation order

1. Introduce presentation tokens (`text`, style, enabled state, action target)
   and build them fully before section execution. This removes the need for more
   special display-only coroutine cases.
2. Extend the shared generator for uncommon domain-object descriptions and
   chained item alternatives as content fixtures require.
3. Separate while-loop mutation from its one-time presentation pass.
4. Render at least bold, italic, disabled, and action spans in KOReader while
   retaining paginated buttons as an accessibility fallback.
5. Compare normalized Java and Lua presentation tokens in fixture tests for
   every empty element and mixed-content boundary. Source-string assertions do
   not prove rendered parity.

## Java override inventory reviewed

The audit searched all Java sources for `handleContent`, presentation-producing
`handleEndTag`, `hideChildContent`, `addLeavesTo`, `addStyledText`, and
`isNewSentence`. The presentation overrides reviewed were `SectionNode`,
`ParagraphNode`, `StyleNode`, `HeadingNode`, `TextNode`, `GroupNode`, `RowNode`,
`FieldNode`, `SectionViewNode`, `ImageNode`, `GotoNode`, `ChoiceNode`,
`ExtraChoice`, `RandomNode`, `DifficultyNode`, `RankCheckNode`, `RerollNode`,
`ReturnNode`, `TrainingNode`, `ResurrectionNode`, `LoseNode`, `TickNode`,
`ItemNode`, `SetVarNode`, `RestNode`, `CurseNode`, `TransferNode`, `WhileNode`,
`OutcomeNode`, `DifficultyResultNode`, `MarketNode`, `TradeNode`, `PriceNode`,
the cache row/component nodes, and the fight detail/result inner nodes.

`LoadableNode`, `ActionNode`, `EffectNode`, and `TradeEventNode` were also
reviewed because their end-tag, parent-routing, or child-hiding behavior affects
where another node's text appears even when they do not contribute ordinary
prose themselves. `SectionDocument`, `StyledText`, and `StyledTextList` were
reviewed for the shared leaf splitting, styling, merging, capitalization, and
sentence-boundary rules.

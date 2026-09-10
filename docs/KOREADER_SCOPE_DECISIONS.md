# KOReader scope decisions

## Section browsing

Java's `sectionview` opens a desktop-only random section browser and does not
mutate the adventure. The KOReader port intentionally treats it as an optional
reference/navigation tool rather than executable game logic. It remains absent
from the play screen until a reader-native browser can clearly distinguish a
preview from travel; this is a platform presentation difference, not silent
execution.

## Fields

Java `field` nodes are read-only Swing controls which display a named numeric
variable. They are not editable character inputs. KOReader renders the same
label and current value inline, avoiding a modal or keyboard-only control.

## Optional rules

Fixed rules belong to the saved adventurer and temporary rules come from the
active book's `Rules` property. The runtime normalizes both sets case
insensitively. The current six-book pack declares no temporary rules, but the
mechanism remains active for compatible content packs and imported saves.

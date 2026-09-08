# Fabled Lands for KOReader

This directory is an installable KOReader plugin. It provides a Lua game engine,
e-ink reading UI, adventure sheet, deterministic section interpreter, autosave,
and support for the XML content in JaFL books 1–6.

## Install

From the repository root, create the complete package:

```sh
make koreader-plugin
```

Extract `dist/jafl.koplugin.zip` into KOReader's `plugins` directory. The final
path must be `koreader/plugins/jafl.koplugin/main.lua`. Restart KOReader, then
select **Tools → Fabled Lands → New adventure**.

The packaged plugin includes the six books in this repository. Developers can
also copy `plugins/jafl.koplugin` directly; a source checkout automatically finds
the books at the repository root. Set `jafl_content_root` in KOReader's reader
settings to use a different content-pack directory containing `books.ini`.

## Controls

- Read the current section in KOReader's native text viewer.
- Select **Choices** to see only currently available actions.
- Select **Sheet** for abilities and possessions.
- **Close** saves before returning to KOReader. The game also saves after every
  section transition, so suspend or process termination cannot lose more than
  the unresolved interaction currently on screen.
- Touch and key-only operation are both supplied by KOReader's standard viewer
  and dialog widgets.

Saves are stored as `jafl.lua` in KOReader's settings directory. Content and
save data are treated as data rather than evaluated as Lua code.

## Development checks

```sh
make check-koreader-content
make koreader-plugin
```

The validator parses every book XML file and checks destinations, illustrations,
and the expected content vocabulary before a package is built.

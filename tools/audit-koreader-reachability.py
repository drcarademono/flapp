#!/usr/bin/env python3
"""Statically audit installed book destinations and executable tag dispatch."""

from __future__ import annotations

import json
import re
from collections import deque
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BOOKS = tuple(str(number) for number in range(1, 7))
EXECUTABLE = {
    "adjustmoney", "buy", "choice", "curse", "difficulty", "disease", "effect",
    "extrachoice", "failure", "fight", "fightdamage", "fightround", "flee", "gain",
    "goto", "group", "if", "elseif", "else", "itemcache", "lose", "market",
    "moneycache", "outcome", "outcomes", "poison", "price", "random", "rankcheck", "reroll",
    "rest", "resurrection", "return", "sell", "set", "sold", "success", "tick",
    "sectionview", "trade", "training", "transfer", "while",
}


def main() -> int:
    game = (ROOT / "plugins/jafl.koplugin/core/game.lua").read_text()
    dispatched = set(re.findall(r'(?:\bn|node\.name|child\.name)=="([a-z0-9]+)"', game))
    generic = sorted(EXECUTABLE - dispatched)
    queue = deque((book, "New") for book in BOOKS)
    seen: set[tuple[str, str]] = set()
    missing: list[str] = []
    tags: set[str] = set()
    while queue:
        book, section = queue.popleft()
        if (book, section) in seen:
            continue
        seen.add((book, section))
        path = ROOT / f"book{book}" / f"{section}.xml"
        if not path.exists():
            missing.append(f"{book}/{section}")
            continue
        root = ET.parse(path).getroot()
        for node in root.iter():
            tags.add(node.tag)
            destination = node.attrib.get("section")
            target_book = node.attrib.get("book", book)
            if destination and target_book in BOOKS:
                queue.append((target_book, destination))
    report = {
        "entrypoints": [f"{book}/New" for book in BOOKS],
        "reachable_sections": len(seen) - len(missing),
        "reachable_tags": sorted(tags),
        "missing_destinations": sorted(set(missing)),
        "executable_tags_without_explicit_dispatch": generic,
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 1 if missing or generic else 0


if __name__ == "__main__":
    raise SystemExit(main())

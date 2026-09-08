#!/usr/bin/env python3
"""Validate XML and section/asset references needed by the KOReader package."""
from __future__ import annotations

import configparser
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TAGS: Counter[str] = Counter()
ERRORS: list[str] = []


def target_exists(book: str, section: str) -> bool:
    return (ROOT / f"book{book}" / f"{section}.xml").is_file()


for book in range(1, 7):
    directory = ROOT / f"book{book}"
    for path in directory.glob("*.xml"):
        try:
            tree = ET.parse(path)
        except ET.ParseError as exc:
            ERRORS.append(f"{path.relative_to(ROOT)}: malformed XML: {exc}")
            continue
        for element in tree.iter():
            TAGS[element.tag.lower()] += 1
            if element.tag.lower() in {"goto", "choice"} and "section" in element.attrib:
                target_book = element.attrib.get("book", str(book))
                target = element.attrib["section"]
                if target_book.isdigit() and int(target_book) <= 6 and not target_exists(target_book, target):
                    ERRORS.append(f"{path.relative_to(ROOT)}: missing target {target_book}/{target}")
            if element.tag.lower() == "image":
                name = element.attrib.get("file") or element.attrib.get("name")
                image_book = element.attrib.get("book", str(book))
                if name and not any((ROOT / place / name).is_file() for place in (f"book{image_book}", f"illus{image_book}")):
                    ERRORS.append(f"{path.relative_to(ROOT)}: missing image {name}")

if len(TAGS) != 69:
    ERRORS.append(f"content vocabulary changed: expected 69 tags, found {len(TAGS)}")

print(f"Validated {sum(TAGS.values())} elements across {sum(1 for i in range(1, 7) for _ in (ROOT / f'book{i}').glob('*.xml'))} XML files")
print(f"Observed {len(TAGS)} tags: {', '.join(sorted(TAGS))}")
if ERRORS:
    print("\n".join(ERRORS), file=sys.stderr)
    sys.exit(1)

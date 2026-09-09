#!/usr/bin/env python3
"""Inventory executable XML shapes which require Java/Lua behavioral proof."""
from __future__ import annotations
import argparse, hashlib, json
from collections import Counter
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
EXECUTABLE={"adjustmoney","buy","choice","curse","difficulty","disease","effect","extrachoice","failure","fight","fightdamage","fightround","flee","gain","goto","group","if","elseif","else","itemcache","lose","market","moneycache","outcome","outcomes","poison","price","random","rankcheck","reroll","rest","resurrection","return","sell","set","sold","success","tick","trade","training","transfer","while"}
OUT=ROOT/"docs/koreader-capability-signatures.json"

def signature(node: ET.Element,parent: str)->dict:
    children=sorted({c.tag.lower() for c in node if isinstance(c.tag,str)})
    attrs=sorted(k.lower() for k in node.attrib)
    shape={"tag":node.tag.lower(),"parent":parent.lower(),"attributes":attrs,"children":children}
    key=json.dumps(shape,sort_keys=True,separators=(",",":"))
    shape["id"]=hashlib.sha256(key.encode()).hexdigest()[:16]
    return shape

def collect()->dict:
    annotations={}
    if OUT.exists():
        try:
            previous=json.loads(OUT.read_text())
            annotations={row["id"]:row for row in previous.get("signatures",[])}
        except (OSError,json.JSONDecodeError,KeyError):
            pass
    entries={}
    for book in range(1,7):
        for path in sorted((ROOT/f"book{book}").glob("*.xml")):
            try: root=ET.parse(path).getroot()
            except ET.ParseError: continue
            def visit(node,parent=""):
                tag=node.tag.lower() if isinstance(node.tag,str) else ""
                if tag in EXECUTABLE:
                    shape=signature(node,parent); old=annotations.get(shape["id"],{})
                    rec=entries.setdefault(shape["id"],{**shape,"occurrences":0,"examples":[],"capability":old.get("capability"),"oracle":old.get("oracle"),"status":old.get("status","unverified")})
                    rec["occurrences"]+=1
                    if len(rec["examples"])<5: rec["examples"].append(f"book{book}/{path.name}")
                for child in node:
                    if isinstance(child.tag,str): visit(child,tag)
            visit(root)
    rows=sorted(entries.values(),key=lambda r:(r["tag"],r["parent"],r["attributes"],r["children"]))
    return {"schema":1,"source":"books 1-6","signatures":rows,"summary":{"total":len(rows),"verified":sum(r["status"]=="verified" for r in rows),"unverified":sum(r["status"]!="verified" for r in rows)}}

def main()->int:
    parser=argparse.ArgumentParser(); parser.add_argument("--check",action="store_true"); args=parser.parse_args()
    generated=collect(); text=json.dumps(generated,indent=2,sort_keys=True)+"\n"
    if args.check:
        if not OUT.exists() or OUT.read_text()!=text:
            print(f"{OUT.relative_to(ROOT)} is stale; run {Path(__file__).name}")
            return 1
        print(f"Capability census current: {generated['summary']['total']} signatures, {generated['summary']['unverified']} unverified")
        return 0
    OUT.write_text(text); print(f"Wrote {OUT.relative_to(ROOT)} with {generated['summary']['total']} signatures")
    return 0
if __name__=="__main__": raise SystemExit(main())

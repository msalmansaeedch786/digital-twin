#!/usr/bin/env python3
"""Regenerate data/05_certifications.txt from the canonical certifications file.

Certification facts used to be typed by hand in two places — data/ (what the
twin retrieves) and the badge cards (what a visitor sees) — with nothing
linking them. They drifted, and the twin spent months claiming an AWS SysOps
Administrator that was never earned.

Now frontend/src/app/certifications.json is the single source: the badge cards
import it directly, and this script derives the data/ text from it. The badge
cards are the right place for canonical truth because each entry carries a
Credly or issuer URL, so every claim is externally checkable.

Only the enumerated list is generated. Prose stays hand-written elsewhere in
data/ — generating natural language from structured data would make the twin
read like a database, and reading like a person is the product.

  --check   exit 1 if the file on disk differs from what would be generated
"""
from __future__ import annotations

import json
import sys
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "frontend" / "src" / "app" / "certifications.json"
TARGET = ROOT / "data" / "05_certifications.txt"

# data/ groups by a human heading; the JSON carries the formal issuer name.
ISSUER_HEADINGS = {
    "Amazon Web Services": "Amazon Web Services (AWS)",
    "HashiCorp": "HashiCorp",
    "Docker": "Docker",
}
# data/ reads as prose, so it uses a plain hyphen where the cards use an en dash.
DASH = "–"


def render() -> str:
    certs = json.loads(SOURCE.read_text(encoding="utf-8"))["certifications"]

    # The page groups Foundational -> Professional so the level chips read as a
    # rising scale. data/ is prose a recruiter's twin reads aloud, where the
    # senior certifications belong first. Same facts, deliberately different
    # order, so sort here rather than forcing one view on both.
    seniority = {"Professional": 0, "Associate": 1, "Foundational": 2}
    ordered = sorted(certs, key=lambda c: seniority.get(c.get("type", ""), 99))

    grouped: "OrderedDict[str, list[str]]" = OrderedDict()
    for c in ordered:
        grouped.setdefault(c["issuer"], []).append(c["title"].replace(DASH, "-"))

    aws_count = len(grouped.get("Amazon Web Services", []))

    lines = ["# Certifications", ""]
    for issuer, titles in grouped.items():
        lines.append(f"## {ISSUER_HEADINGS.get(issuer, issuer)}")
        if issuer == "Amazon Web Services":
            lines.append(f"I am a {aws_count}x AWS Certified professional:")
        for i, title in enumerate(titles, 1):
            lines.append(f"{i}. {title}")
        lines.append("")
    return "\n".join(lines).rstrip("\n") + "\n"


def main() -> int:
    generated = render()
    check = "--check" in sys.argv

    if check:
        current = TARGET.read_text(encoding="utf-8") if TARGET.exists() else ""
        if current != generated:
            print(f"{TARGET.relative_to(ROOT)} is out of date.\n")
            print(f"  It is generated from {SOURCE.relative_to(ROOT)}, which has changed.")
            print("  Run: python3 scripts/generate_certifications.py")
            return 1
        print(f"  {TARGET.relative_to(ROOT)} matches {SOURCE.name}")
        return 0

    TARGET.write_text(generated, encoding="utf-8")
    print(f"  wrote {TARGET.relative_to(ROOT)} from {SOURCE.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

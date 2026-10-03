#!/usr/bin/env python3
"""Fail if the twin and the portfolio disagree about which credentials are held.

The same certification facts live in five files with nothing linking them:

    data/05_certifications.txt          what the twin retrieves and asserts
    data/01_professional_summary.txt    the "Nx AWS Certified" count
    data/04_skills_and_tools.txt        the count again
    frontend/.../portfolio-client.js    the badge cards a visitor sees
    frontend/.../dictionaries/*.json    the count in three keys per locale

They drifted once, and the twin spent months claiming an AWS SysOps
Administrator - Associate that was never earned while never mentioning the AI
Practitioner that was. Nothing caught it; a visitor did.

This asserts two invariants:
  1. the certification titles in data/ and on the page are the same set
  2. every "Nx AWS Certified" claim matches the actual number of AWS certs

Pure stdlib, no AWS, no network — runs in pre-commit and CI.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CERTS_TXT = ROOT / "data" / "05_certifications.txt"
PORTFOLIO = ROOT / "frontend" / "src" / "app" / "[lang]" / "portfolio-client.js"
COUNT_FILES = [
    ROOT / "data" / "01_professional_summary.txt",
    ROOT / "data" / "04_skills_and_tools.txt",
    CERTS_TXT,
    ROOT / "frontend" / "src" / "app" / "dictionaries" / "en.json",
    ROOT / "frontend" / "src" / "app" / "dictionaries" / "de.json",
]


def normalise(title: str) -> str:
    """Compare on substance, not punctuation.

    data/ writes "Solutions Architect - Professional" (hyphen) while the badge
    cards use an en dash. Both are correct; neither should fail the check.
    """
    t = title.replace("–", "-").replace("—", "-")
    t = re.sub(r"\s*-\s*", " - ", t)
    return re.sub(r"\s+", " ", t).strip().casefold()


def certs_from_data() -> set[str]:
    out = set()
    for line in CERTS_TXT.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*\d+\.\s+(.+?)\s*$", line)
        if m:
            out.add(normalise(m.group(1)))
    return out


def certs_from_page() -> set[str]:
    src = PORTFOLIO.read_text(encoding="utf-8")
    return {normalise(t) for t in re.findall(r'title:\s*"([^"]+)",\s*issuer:', src)}


def aws_count_claims() -> list[tuple[Path, int, str]]:
    """Every "Nx AWS ..." assertion, wherever it lives."""
    found = []
    for path in COUNT_FILES:
        for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for m in re.finditer(r"(\d+)x AWS", line):
                found.append((path, i, m.group(1)))
    return found


def main() -> int:
    data, page = certs_from_data(), certs_from_page()
    problems = []

    only_data = sorted(data - page)
    only_page = sorted(page - data)
    if only_data:
        problems.append(
            "In data/ but NOT shown on the page — the twin will claim these to "
            "visitors with nothing on the site to back them up:\n"
            + "\n".join(f"    - {c}" for c in only_data)
        )
    if only_page:
        problems.append(
            "On the page but NOT in data/ — the twin does not know about these "
            "and will deny holding them if asked:\n"
            + "\n".join(f"    - {c}" for c in only_page)
        )

    actual_aws = sum(1 for c in data if c.startswith("aws certified"))
    wrong = [(p, ln, n) for p, ln, n in aws_count_claims() if int(n) != actual_aws]
    if wrong:
        problems.append(
            f"data/ lists {actual_aws} AWS certifications, but these claim otherwise:\n"
            + "\n".join(
                f"    - {p.relative_to(ROOT)}:{ln} says \"{n}x AWS\"" for p, ln, n in wrong
            )
        )

    if problems:
        print("Credential sources disagree.\n")
        for p in problems:
            print(f"  {p}\n")
        print("  Fix: the badge cards are the checkable side — each carries a Credly")
        print("  or issuer URL. Verify data/ against them, not the other way round.")
        return 1

    print(f"  credentials consistent: {len(data)} certifications, {actual_aws}x AWS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

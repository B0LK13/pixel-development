#!/usr/bin/env python3
"""Validate evidence path references in markdown docs/reports."""
from pathlib import Path
import re
import sys


LINK_RE = re.compile(r"(evidence/[A-Za-z0-9._/\-]+)")
SCAN_DIRS = ("docs", "reports")


def main(argv):
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    if argv:
        print(f"check-evidence-links: unknown argument: {argv[0]}", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parent.parent
    violations = []
    scanned = 0
    refs = 0
    for d in SCAN_DIRS:
        base = root / d
        if not base.is_dir():
            continue
        for p in base.rglob("*.md"):
            scanned += 1
            text = p.read_text(encoding="utf-8")
            for m in LINK_RE.finditer(text):
                refs += 1
                rel = m.group(1).rstrip(").,")
                # Ignore obvious prose matches that are not concrete repository
                # paths (e.g., "evidence/report" in plain language).
                if rel.endswith("-"):
                    continue
                if rel.count("/") == 1 and "." not in rel and not rel.endswith("/"):
                    continue
                if not (root / rel).exists():
                    violations.append(f"{p.relative_to(root)} references missing evidence path: {rel}")

    for v in violations:
        print(f"VIOLATION {v}")
    print(f"evidence-link check: {scanned} markdown file(s), {refs} reference(s), {len(violations)} violation(s)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

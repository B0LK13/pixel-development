#!/usr/bin/env python3
"""Detect stale hard-coded numeric claims in Agent OS docs."""
from pathlib import Path
import re
import sys


TARGETS = [
    "AGENTS.md",
    ".github/copilot-instructions.md",
    "docs/AGENT_ARCHITECTURE.md",
    "docs/AGENT_WORKFLOW_CONTRACT.md",
    "docs/AGENT_SECURITY_BOUNDARIES.md",
    "docs/AGENT_TEST_STRATEGY.md",
    "docs/AGENT_HANDOFF_PROTOCOL.md",
]

PATTERNS = [
    re.compile(r"\b[0-9]{2,}\s+tests?\b", re.IGNORECASE),
    re.compile(r"\b[0-9]{2,}\s+invariants?\b", re.IGNORECASE),
    re.compile(r"\b[0-9]{2,}\s+CI\s+legs?\b", re.IGNORECASE),
]


def main(argv):
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    if argv:
        print(f"check-stale-claims: unknown argument: {argv[0]}", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parent.parent
    violations = []
    scanned = 0
    for rel in TARGETS:
        p = root / rel
        if not p.is_file():
            continue
        scanned += 1
        text = p.read_text(encoding="utf-8")
        for pat in PATTERNS:
            m = pat.search(text)
            if m:
                violations.append(f"{rel} has potentially stale numeric claim: {m.group(0)!r}")

    evidence_scaffolding = root / "evidence" / "SIGNING-EVIDENCE.json"
    if evidence_scaffolding.is_file():
        scanned += 1
        text = evidence_scaffolding.read_text(encoding="utf-8")
        if '"valid_for_release": false' not in text and "'valid_for_release': false" not in text:
            violations.append("evidence/SIGNING-EVIDENCE.json (scaffolding evidence) must explicitly set 'valid_for_release': false")

    for v in violations:
        print(f"VIOLATION {v}")
    print(f"stale-claims check: {scanned} file(s), {len(violations)} violation(s)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))


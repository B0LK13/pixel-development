#!/usr/bin/env python3
"""Scan Agent OS files for obvious credential/key material leaks."""
from pathlib import Path
import re
import sys


SCAN_GLOBS = [
    "AGENTS.md",
    ".github/copilot-instructions.md",
    ".github/AGENTS.md",
    "docs/AGENT*.md",
    ".agent/**/*.yaml",
    ".agent/**/*.md",
    "reports/session-14-final-report.md",
]

PATTERNS = [
    re.compile(r"-----BEGIN (?:RSA|EC|OPENSSH|PGP)? ?PRIVATE KEY-----"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b"),
    re.compile(r"authorization:\s*bearer\s+[A-Za-z0-9._\-]+", re.IGNORECASE),
]


def main(argv):
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    if argv:
        print(f"check-agent-secrets: unknown argument: {argv[0]}", file=sys.stderr)
        return 2
    root = Path(__file__).resolve().parent.parent
    files = []
    for g in SCAN_GLOBS:
        files.extend(root.glob(g))
    files = sorted({p for p in files if p.is_file()})
    violations = []
    for p in files:
        text = p.read_text(encoding="utf-8")
        for pat in PATTERNS:
            m = pat.search(text)
            if m:
                violations.append(f"{p.relative_to(root)} matched secret pattern: {m.group(0)[:60]}")
    for v in violations:
        print(f"VIOLATION {v}")
    print(f"agent-secrets check: {len(files)} file(s), {len(violations)} violation(s)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))


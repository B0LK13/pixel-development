#!/usr/bin/env python3
"""Check command-reference parity across core docs.

Ensures canonical commands are present in key docs and scripts referenced by
those commands exist.
"""
from pathlib import Path
import re
import sys


CANONICAL_COMMANDS = [
    "bash tests/run_tests.sh",
    "bash scripts/ci-local.sh",
    "python3 scripts/check-github-action-pins.py",
    "bash scripts/update-bootstrap-checksums.sh --check",
]

DOC_FILES = [
    "README.md",
    "docs/CONTRIBUTOR_QUICKSTART.md",
    "docs/OPERATOR_COMMAND_INDEX.md",
    ".github/copilot-instructions.md",
]


def main(argv):
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    if argv:
        print(f"check-doc-command-parity: unknown argument: {argv[0]}", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parent.parent
    violations = []

    docs_text = {}
    for rel in DOC_FILES:
        p = root / rel
        if not p.is_file():
            violations.append(f"missing doc file: {rel}")
            continue
        docs_text[rel] = p.read_text(encoding="utf-8")

    for cmd in CANONICAL_COMMANDS:
        if not any(cmd in t for t in docs_text.values()):
            violations.append(f"canonical command missing from docs: {cmd}")

    # Script existence for referenced script paths in command snippets.
    cmd_pattern = re.compile(r"(?:bash|python3)\s+([a-zA-Z0-9_./-]+)")
    for rel, text in docs_text.items():
        for m in cmd_pattern.finditer(text):
            candidate = m.group(1)
            if candidate.startswith("./"):
                candidate = candidate[2:]
            if candidate.startswith("scripts/") or candidate.startswith("tests/"):
                if not (root / candidate).exists():
                    violations.append(f"{rel} references missing path: {candidate}")

    for v in violations:
        print(f"VIOLATION {v}")
    print(f"doc-command parity: {len(DOC_FILES)} doc file(s), {len(violations)} violation(s)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))


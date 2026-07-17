#!/usr/bin/env python3
"""Validate .agent/skills/index.yaml references existing skill files."""
from pathlib import Path
import re
import sys


ENTRY_RE = re.compile(r"^\s*-\s*id:\s*(\S+)\s*$")
PATH_RE = re.compile(r"^\s*path:\s*\"?([^\"]+)\"?\s*$")


def main(argv):
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    if argv:
        print(f"check-skill-index: unknown argument: {argv[0]}", file=sys.stderr)
        return 2
    root = Path(__file__).resolve().parent.parent
    idx = root / ".agent/skills/index.yaml"
    if not idx.is_file():
        print("VIOLATION missing .agent/skills/index.yaml")
        print("skill-index check: 1 violation(s)")
        return 1
    lines = idx.read_text(encoding="utf-8").splitlines()
    entries = []
    current_id = None
    for line in lines:
        m = ENTRY_RE.match(line)
        if m:
            current_id = m.group(1)
            continue
        p = PATH_RE.match(line)
        if p and current_id:
            entries.append((current_id, p.group(1)))
            current_id = None
    violations = []
    ids = set()
    for sid, rel in entries:
        if sid in ids:
            violations.append(f"duplicate skill id: {sid}")
        ids.add(sid)
        if not (root / rel).is_file():
            violations.append(f"missing skill path for {sid}: {rel}")
    for v in violations:
        print(f"VIOLATION {v}")
    print(f"skill-index check: {len(entries)} entry(s), {len(violations)} violation(s)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))


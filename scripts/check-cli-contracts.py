#!/usr/bin/env python3
"""Check CLI contract drift between scripts and docs/CLI_CONTRACT.md."""
from pathlib import Path
import re
import sys


SCRIPT_FLAGS = {
    "pixel-bootstrap.sh": ["--open-store", "--repo-base=", "--help", "-h"],
    "pixel-dev-setup.sh": ["--minimal", "--no-ai", "--yes", "-y", "--help", "-h"],
    "pixel-apps-setup.sh": ["--open-stores", "--with-tailscale-cli", "--no-font", "--yes", "-y", "--ssh-port=", "--help", "-h"],
    "pixel-autodev.sh": ["--workspace=", "--backlog=", "--max-tasks=", "--max-turns=", "--budget=", "--timeout=", "--model=", "--agent=", "--yolo", "--push", "--dry-run", "--yes", "-y", "--help", "-h"],
}


def main(argv):
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    if argv:
        print(f"check-cli-contracts: unknown argument: {argv[0]}", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parent.parent
    doc = root / "docs/CLI_CONTRACT.md"
    if not doc.is_file():
        print("VIOLATION missing docs/CLI_CONTRACT.md")
        print("cli-contract check: 1 violation(s)")
        return 1
    doc_text = doc.read_text(encoding="utf-8")

    violations = []
    for script, flags in SCRIPT_FLAGS.items():
        p = root / script
        if not p.is_file():
            violations.append(f"missing script: {script}")
            continue
        text = p.read_text(encoding="utf-8")
        for flag in flags:
            # In script parser
            needle = flag[:-1] if flag.endswith("=") else flag
            if needle not in text:
                violations.append(f"{script} missing flag token: {flag}")
            # In contract doc
            if needle not in doc_text:
                violations.append(f"docs/CLI_CONTRACT.md missing flag reference: {script} {flag}")

    for v in violations:
        print(f"VIOLATION {v}")
    print(f"cli-contract check: {len(SCRIPT_FLAGS)} script(s), {len(violations)} violation(s)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))


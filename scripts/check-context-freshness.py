#!/usr/bin/env python3
"""Check freshness/consistency of Agent OS context references."""
from pathlib import Path
import re
import sys


def main(argv):
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    if argv:
        print(f"check-context-freshness: unknown argument: {argv[0]}", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parent.parent
    violations = []

    # Required command references must resolve.
    required_paths = [
        "AGENTS.md",
        ".agent/repository-manifest.yaml",
        ".agent/task-router.yaml",
        "tests/run_tests.sh",
        "scripts/ci-local.sh",
        "scripts/agent-context.sh",
    ]
    for rel in required_paths:
        if not (root / rel).exists():
            violations.append(f"missing required path: {rel}")

    # Prevent stale explicit branch names in core Agent OS docs.
    stale_branch_re = re.compile(r"\b(auto/|main\b|master\b)")
    for rel in (
        "AGENTS.md",
        ".github/copilot-instructions.md",
        "docs/AGENT_ARCHITECTURE.md",
        "docs/AGENT_WORKFLOW_CONTRACT.md",
    ):
        p = root / rel
        if not p.is_file():
            continue
        text = p.read_text(encoding="utf-8")
        if "master" in text:
            violations.append(f"{rel} contains obsolete branch name 'master'")
        # allow main in command examples only when referenced with ci/workflow context
        if stale_branch_re.search(text) and "branch" in text.lower() and "policy" not in rel.lower():
            pass

    for v in violations:
        print(f"VIOLATION {v}")
    print(f"context-freshness check: {len(required_paths)} required path(s), {len(violations)} violation(s)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))


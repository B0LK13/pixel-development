#!/usr/bin/env python3
"""Validate repository agent-instruction scaffolding.

Exit codes:
  0 compliant
  1 violations found
  2 usage/error
"""
from pathlib import Path
import re
import sys


REQUIRED_FILES = [
    "AGENTS.md",
    ".github/copilot-instructions.md",
    ".github/AGENTS.md",
    "scripts/AGENTS.md",
    "tests/AGENTS.md",
    "docs/AGENTS.md",
    "docs/AGENT_ARCHITECTURE.md",
    "docs/AGENT_WORKFLOW_CONTRACT.md",
    "docs/AGENT_SECURITY_BOUNDARIES.md",
    "docs/AGENT_TEST_STRATEGY.md",
    "docs/AGENT_HANDOFF_PROTOCOL.md",
    ".agent/repository-manifest.yaml",
    ".agent/task-router.yaml",
    ".agent/skills/index.yaml",
    "tests/section-map.tsv",
    "reports/agent-os/harness-inventory.md",
    "harness/README.md",
]


def main(argv):
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    if argv:
        print(f"check-agent-instructions: unknown argument: {argv[0]}", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parent.parent
    violations = []

    for rel in REQUIRED_FILES:
        if not (root / rel).is_file():
            violations.append(f"missing required file: {rel}")

    copilot = (root / ".github/copilot-instructions.md")
    agents = (root / "AGENTS.md")
    manifest = (root / ".agent/repository-manifest.yaml")
    router = (root / ".agent/task-router.yaml")
    if copilot.is_file():
        text = copilot.read_text(encoding="utf-8")
        for needle in ("AGENTS.md", "bash tests/run_tests.sh", "bash scripts/ci-local.sh"):
            if needle not in text:
                violations.append(f".github/copilot-instructions.md missing reference: {needle}")
    if agents.is_file():
        text = agents.read_text(encoding="utf-8")
        for needle in (
            "## Repository purpose",
            "## Authoritative commands",
            "## Branch/commit/worktree rules",
            "## Required pre-completion state",
            "## Operator-only actions",
            "## Completion report format",
            "docs/AGENT_WORKFLOW_CONTRACT.md",
            "docs/AGENT_SECURITY_BOUNDARIES.md",
        ):
            if needle not in text:
                violations.append(f"AGENTS.md missing canonical reference: {needle}")
    if manifest.is_file():
        text = manifest.read_text(encoding="utf-8")
        for needle in ("entrypoints:", "checks:", "boundaries:", "gates:", "evidence:", "platforms:", "supported_agents:"):
            if needle not in text:
                violations.append(f".agent/repository-manifest.yaml missing section: {needle}")
    if router.is_file():
        text = router.read_text(encoding="utf-8")
        if "routes:" not in text:
            violations.append(".agent/task-router.yaml missing routes")
    skills_index = root / ".agent/skills/index.yaml"
    if skills_index.is_file():
        text = skills_index.read_text(encoding="utf-8")
        if "skills:" not in text:
            violations.append(".agent/skills/index.yaml missing skills root")

    # Lightweight command existence check for Copilot entry docs.
    if copilot.is_file():
        text = copilot.read_text(encoding="utf-8")
        cmd_re = re.compile(r"`(?:bash|python3)\s+([A-Za-z0-9_./-]+)")
        for m in cmd_re.finditer(text):
            rel = m.group(1).lstrip("./")
            if rel.startswith(("scripts/", "tests/", "docs/", ".agent/")) and not (root / rel).exists():
                violations.append(f".github/copilot-instructions.md references missing path: {rel}")

    for v in violations:
        print(f"VIOLATION {v}")
    print(f"agent-instruction check: {len(REQUIRED_FILES)} required file(s), {len(violations)} violation(s)")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

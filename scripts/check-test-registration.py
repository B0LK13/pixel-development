#!/usr/bin/env python3
"""Ensure harness sections are registered in tests/section-map.tsv."""
from pathlib import Path
import re
import sys


SECTION_RE = re.compile(r"^# --- ([0-9]+)\. (.+?) -+\s*$")


def main(argv):
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    if argv:
        print(f"check-test-registration: unknown argument: {argv[0]}", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parent.parent
    harness = root / "tests/run_tests_full.sh"
    mapping = root / "tests/section-map.tsv"
    violations = []

    if not harness.is_file():
        violations.append("missing tests/run_tests_full.sh")
    if not mapping.is_file():
        violations.append("missing tests/section-map.tsv")
    if violations:
        for v in violations:
            print(f"VIOLATION {v}")
        print(f"test-registration check: {len(violations)} violation(s)")
        return 1

    harness_sections = []
    for line in harness.read_text(encoding="utf-8").splitlines():
        m = SECTION_RE.match(line)
        if m:
            harness_sections.append(int(m.group(1)))
    mapped_sections = []
    mapped_tests = set()
    for line in mapping.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 7:
            violations.append(f"malformed mapping row: {line}")
            continue
        try:
            sid = int(parts[0].strip())
        except ValueError:
            violations.append(f"invalid section id in mapping: {parts[0]}")
            continue
        test_id = parts[1].strip()
        deps = parts[3].strip()
        tags = parts[4].strip()
        duration = parts[5].strip()
        platforms = parts[6].strip()
        if test_id in mapped_tests:
            violations.append(f"duplicate test id: {test_id}")
        mapped_tests.add(test_id)
        mapped_sections.append(sid)
        if not tags:
            violations.append(f"missing tags for section {sid}")
        if duration not in {"short", "medium", "long"}:
            violations.append(f"invalid expected_duration for section {sid}: {duration!r}")
        if platforms not in {"all", "linux", "windows"}:
            violations.append(f"invalid supported_platforms for section {sid}: {platforms!r}")
        if deps not in {"-", ""}:
            for d in deps.split(","):
                if not d.isdigit():
                    violations.append(f"invalid dependency entry for section {sid}: {d!r}")

    if sorted(harness_sections) != sorted(mapped_sections):
        violations.append(
            f"section mismatch: harness={sorted(harness_sections)} map={sorted(mapped_sections)}"
        )

    for v in violations:
        print(f"VIOLATION {v}")
    print(
        f"test-registration check: {len(harness_sections)} harness section(s), "
        f"{len(mapped_sections)} mapped section(s), {len(violations)} violation(s)"
    )
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

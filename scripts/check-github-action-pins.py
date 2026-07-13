#!/usr/bin/env python3
"""Enforce the repository GitHub Actions pinning policy.

Policy (docs/GITHUB_ACTIONS_PINNING_POLICY.md): every external action or
reusable-workflow reference in .github/workflows must be pinned to a full
40-character commit SHA and carry an inline "# vX.Y.Z" release comment.
Local actions (./...), and docker:// images pinned by sha256 digest, are
allowed. Mutable refs (@main, @master, @latest, @v4, short SHAs, branch
names) are rejected.

Stdlib-only, no network, deterministic output. Exit 0 = compliant,
1 = violations found, 2 = usage/scan error.
"""
import re
import sys
from pathlib import Path

SHA_RE = re.compile(r"[0-9a-f]{40}")
VERSION_COMMENT_RE = re.compile(r"#\s*v\d+\.\d+\.\d+")
DOCKER_DIGEST_RE = re.compile(r"^docker://\S+@sha256:[0-9a-f]{64}$")
# owner/repo[/path]@ref — owner and repo are non-space, non-@ segments
EXTERNAL_RE = re.compile(r"^(?P<where>[^\s/@]+/[^\s/@]+(?:/[^\s@]*)?)@(?P<ref>\S+)$")
USES_RE = re.compile(r"^(?P<indent>\s*)(?:-\s*)?uses:\s*(?P<value>.*)$")

MUTABLE_NAMES = {"main", "master", "latest", "HEAD"}


def split_value_comment(raw):
    """Split a YAML plain/quoted scalar into (value, comment_text).

    Good enough for `uses:` lines, which are always single-line scalars in
    valid GitHub Actions workflows.
    """
    s = raw.strip()
    if not s:
        return "", ""
    if s[0] in "\"'":
        quote = s[0]
        end = s.find(quote, 1)
        if end == -1:
            return s, ""
        return s[1:end], s[end + 1:]
    hash_pos = s.find(" #")
    if hash_pos != -1:
        return s[:hash_pos].strip(), s[hash_pos + 1:]
    return s, ""


def classify_violation(value, comment):
    """Return a violation reason string, or None if the reference complies."""
    if value.startswith("./") or value.startswith(".\\"):
        return None  # repository-local action
    if value.startswith("docker://"):
        if DOCKER_DIGEST_RE.match(value):
            return None
        return "docker image not pinned by sha256 digest: %s" % value
    m = EXTERNAL_RE.match(value)
    if not m:
        return "unparseable or unpinned external reference (no @ref): %s" % value
    ref = m.group("ref")
    if SHA_RE.fullmatch(ref):
        if not VERSION_COMMENT_RE.search(comment):
            return "SHA pin missing inline version comment (# vX.Y.Z): %s" % value
        return None
    if re.fullmatch(r"[0-9a-f]{7,39}", ref):
        return "short SHA is not immutable enough (need full 40 chars): @%s" % ref
    if ref in MUTABLE_NAMES:
        return "mutable branch ref prohibited: @%s" % ref
    if re.fullmatch(r"v?\d+(\.\d+)?(\.\d+)?", ref):
        return "mutable version tag prohibited (pin the commit SHA): @%s" % ref
    return "ref is not a full 40-char commit SHA: @%s" % ref


def scan_file(path):
    """Yield (lineno, reason) violations for one workflow file."""
    violations = []
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        violations.append((0, "cannot read file: %s" % exc))
        return violations, 0
    refs = 0
    for lineno, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        m = USES_RE.match(line)
        if not m:
            continue
        value, comment = split_value_comment(m.group("value"))
        if not value:
            violations.append((lineno, "empty uses: value"))
            continue
        refs += 1
        reason = classify_violation(value, comment)
        if reason:
            violations.append((lineno, reason))
    return violations, refs


def main(argv):
    root = Path(__file__).resolve().parent.parent
    args = list(argv)
    if "--help" in args or "-h" in args:
        print(__doc__.strip())
        return 0
    if "--root" in args:
        i = args.index("--root")
        try:
            root = Path(args[i + 1]).resolve()
        except IndexError:
            print("check-action-pins: --root needs a path", file=sys.stderr)
            return 2
        del args[i:i + 2]
    if args:
        print("check-action-pins: unknown argument: %s" % args[0], file=sys.stderr)
        return 2

    wf_dir = root / ".github" / "workflows"
    if not wf_dir.is_dir():
        print("check-action-pins: no workflow directory: %s" % wf_dir, file=sys.stderr)
        return 2

    files = sorted(wf_dir.glob("*.yml")) + sorted(wf_dir.glob("*.yaml"))
    total_refs = 0
    total_violations = 0
    for path in files:
        violations, refs = scan_file(path)
        total_refs += refs
        rel = path.relative_to(root)
        for lineno, reason in violations:
            total_violations += 1
            loc = "%s:%s" % (rel, lineno) if lineno else str(rel)
            print("VIOLATION %s: %s" % (loc, reason))

    print("action-pin check: %d workflow file(s), %d uses ref(s), %d violation(s)"
          % (len(files), total_refs, total_violations))
    return 1 if total_violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

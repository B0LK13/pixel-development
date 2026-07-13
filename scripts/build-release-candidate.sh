#!/usr/bin/env bash
###############################################################################
#  scripts/build-release-candidate.sh — assemble (never publish) a release    #
#  candidate bundle for the pixel-development kit. See                        #
#  docs/BOOTSTRAP_RELEASE_PROCESS.md and docs/RELEASE_SIGNING.md.             #
#                                                                             #
#  Usage:                                                                     #
#    bash scripts/build-release-candidate.sh --version=X.Y.Z                  #
#    bash scripts/build-release-candidate.sh --version=X.Y.Z --check          #
#    bash scripts/build-release-candidate.sh --version=X.Y.Z \                #
#      --output-dir=DIR [--keep-partial]                                      #
#                                                                             #
#  The bundle is a directory <output-dir>/pixel-development-<version>/ with   #
#  the three pinned scripts, bootstrap-checksums.txt, SHA256SUMS,             #
#  RELEASE-METADATA.json, SIGNING-MANIFEST.json, INSTALL.md, VERIFY.md.       #
#  Signing is never done here — it is an offline operator act.                #
#                                                                             #
#  Gates (any failure exits 1, nothing shipped): strict SemVer, clean git     #
#  tree, checksum lockstep, bash -n on the artifacts. Output is atomic: the   #
#  bundle is built in a temp dir and renamed into place; a failed build       #
#  leaves no bundle (unless --keep-partial). No network, no signing tools.    #
#  SOURCE_DATE_EPOCH (unix seconds) pins created_at + file mtimes so two      #
#  builds from the same commit are byte-identical.                            #
#  Exit codes: 0 ok · 1 gate/IO failure · 2 usage error                       #
###############################################################################
set -uo pipefail

VERSION='' CHECK='' OUT_PARENT='' KEEP_PARTIAL=''
for a in "$@"; do
  case "$a" in
    --version=*)     VERSION="${a#*=}" ;;
    --check)         CHECK=1 ;;
    --output-dir=*)  OUT_PARENT="${a#*=}" ;;
    --keep-partial)  KEEP_PARTIAL=1 ;;
    --help|-h) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*) echo "build-release-candidate: unknown flag: $a (try --help)" >&2; exit 2 ;;
    *)   echo "build-release-candidate: unexpected argument: $a (try --help)" >&2; exit 2 ;;
  esac
done

die(){ printf 'build-release-candidate: %s\n' "$*" >&2; exit 1; }

# --- usage validation first (repo CLI contract: before any side effect) ------
[ -n "$VERSION" ] || { echo "usage: bash scripts/build-release-candidate.sh --version=X.Y.Z [--check] [--output-dir=DIR] [--keep-partial]" >&2; exit 2; }
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "build-release-candidate: malformed version: $VERSION (want strict SemVer X.Y.Z, e.g. 1.0.0)" >&2
  exit 2
fi
# environment input validation, before any side effect
if [ -n "${SOURCE_DATE_EPOCH:-}" ] && ! [[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]]; then
  echo "build-release-candidate: SOURCE_DATE_EPOCH must be unix seconds: $SOURCE_DATE_EPOCH" >&2
  exit 1
fi

# --- resolve the repository root (this script lives in <root>/scripts/) ------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" \
  || die "cannot resolve script directory"
ROOT="$(dirname -- "$SCRIPT_DIR")"
[ -f "$ROOT/pixel-bootstrap.sh" ] && [ -d "$ROOT/config" ] \
  || die "repository root not recognized at $ROOT"

[ -n "$OUT_PARENT" ] || OUT_PARENT="$ROOT/dist"
BUNDLE_NAME="pixel-development-$VERSION"
TMPB="$OUT_PARENT/.$BUNDLE_NAME.tmp.$$"
FAILED=1
cleanup(){ [ "$FAILED" = 1 ] && [ -z "$KEEP_PARTIAL" ] && [ -n "${TMPB:-}" ] && rm -rf "$TMPB" 2>/dev/null; return 0; }
trap cleanup EXIT

sha256_of(){
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else die "no SHA-256 tool (sha256sum or shasum)"; fi
}

# --- release gates -------------------------------------------------------------
# Full commit SHA of the source tree.
COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" \
  || die "not a git repository: $ROOT"
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "unexpected commit SHA: $COMMIT"

# Official candidates come from a clean tree only (tracked AND untracked).
dirty="$(git -C "$ROOT" status --porcelain 2>/dev/null)"
[ -z "$dirty" ] || die "working tree is not clean — commit or stash first:"$'\n'"$dirty"

# Checksum lockstep: manifest + embedded pins must agree with the files.
if ! lockstep_out="$(bash "$ROOT/scripts/update-bootstrap-checksums.sh" --check 2>&1)"; then
  printf '%s\n' "$lockstep_out" >&2
  die "checksum lockstep failed — run: bash scripts/update-bootstrap-checksums.sh --write"
fi

# Syntax gate on the three artifacts.
for s in pixel-bootstrap.sh pixel-dev-setup.sh pixel-apps-setup.sh; do
  bash -n "$ROOT/$s" || die "syntax check failed: $s"
done

# --- artifact table (bundle path | source relpath | mode | role), sorted ------
ART_PATHS=(bootstrap-checksums.txt pixel-apps-setup.sh pixel-bootstrap.sh pixel-dev-setup.sh)
ART_SRCS=(config/bootstrap-checksums.txt pixel-apps-setup.sh pixel-bootstrap.sh pixel-dev-setup.sh)
ART_MODES=(0644 0755 0755 0755)
ART_ROLES=(checksum-manifest setup-apps bootstrap setup-dev)

i=0
while [ "$i" -lt "${#ART_PATHS[@]}" ]; do
  src="$ROOT/${ART_SRCS[$i]}"
  [ -L "$src" ] && die "refusing symlink artifact: ${ART_SRCS[$i]}"
  [ -f "$src" ] || die "missing artifact: ${ART_SRCS[$i]}"
  case "${ART_PATHS[$i]}" in */*|*..*) die "unsafe bundle path: ${ART_PATHS[$i]}" ;; esac
  i=$((i+1))
done

if [ -n "$CHECK" ]; then
  printf 'release candidate OK (check mode — nothing written)\n'
  printf '  version:  %s\n  commit:   %s\n  bundle:   %s/%s\n  artifacts: %d\n' \
    "$VERSION" "$COMMIT" "$OUT_PARENT" "$BUNDLE_NAME" "${#ART_PATHS[@]}"
  exit 0
fi

# --- assemble atomically: temp dir, then rename --------------------------------
[ ! -e "$OUT_PARENT/$BUNDLE_NAME" ] \
  || die "output already exists: $OUT_PARENT/$BUNDLE_NAME (remove it or choose another --output-dir)"
mkdir -p "$OUT_PARENT" || die "cannot create output dir: $OUT_PARENT"
rm -rf "$TMPB" 2>/dev/null
mkdir -p "$TMPB" || die "cannot create temp bundle dir: $TMPB"

i=0
while [ "$i" -lt "${#ART_PATHS[@]}" ]; do
  cp "$ROOT/${ART_SRCS[$i]}" "$TMPB/${ART_PATHS[$i]}" || die "cannot copy ${ART_SRCS[$i]}"
  chmod "${ART_MODES[$i]}" "$TMPB/${ART_PATHS[$i]}" || die "cannot chmod ${ART_PATHS[$i]}"
  i=$((i+1))
done

# SHA256SUMS (sha256sum -c compatible, sorted by path)
: > "$TMPB/SHA256SUMS" || die "cannot write SHA256SUMS"
i=0
while [ "$i" -lt "${#ART_PATHS[@]}" ]; do
  printf '%s  %s\n' "$(sha256_of "$TMPB/${ART_PATHS[$i]}")" "${ART_PATHS[$i]}" >> "$TMPB/SHA256SUMS" \
    || die "cannot hash ${ART_PATHS[$i]}"
  i=$((i+1))
done

# created_at: SOURCE_DATE_EPOCH (reproducible builds, validated above) or now.
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  CREATED_AT="$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
    || die "date cannot format SOURCE_DATE_EPOCH (needs GNU-compatible date -d)"
else
  CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

# RELEASE-METADATA.json — deterministic key order, one artifact object per line.
META="$TMPB/RELEASE-METADATA.json"
{
  printf '{\n'
  printf '  "schema_version": "1.0",\n'
  printf '  "project": "pixel-development",\n'
  printf '  "version": "%s",\n' "$VERSION"
  printf '  "commit": "%s",\n' "$COMMIT"
  printf '  "created_at": "%s",\n' "$CREATED_AT"
  printf '  "bootstrap_entrypoint": "pixel-bootstrap.sh",\n'
  printf '  "checksum_algorithm": "sha256",\n'
  printf '  "signature_algorithm": "openpgp-detached",\n'
  printf '  "signature_required": false,\n'
  printf '  "artifacts": [\n'
  i=0
  while [ "$i" -lt "${#ART_PATHS[@]}" ]; do
    sep=','; [ "$i" -eq $((${#ART_PATHS[@]}-1)) ] && sep=''
    printf '    { "path": "%s", "sha256": "%s", "mode": "%s", "role": "%s" }%s\n' \
      "${ART_PATHS[$i]}" "$(sha256_of "$TMPB/${ART_PATHS[$i]}")" "${ART_MODES[$i]}" "${ART_ROLES[$i]}" "$sep"
    i=$((i+1))
  done
  printf '  ]\n'
  printf '}\n'
} > "$META" || die "cannot write RELEASE-METADATA.json"

# SIGNING-MANIFEST.json — binds identity + metadata digest + artifact hashes.
# The operator signs THIS file offline; the verifier checks the signature
# before trusting these hashes (see docs/RELEASE_SIGNING.md).
SMAN="$TMPB/SIGNING-MANIFEST.json"
{
  printf '{\n'
  printf '  "schema_version": "1.0",\n'
  printf '  "project": "pixel-development",\n'
  printf '  "version": "%s",\n' "$VERSION"
  printf '  "commit": "%s",\n' "$COMMIT"
  printf '  "signature_algorithm": "openpgp-detached",\n'
  printf '  "expected_signature": "SIGNING-MANIFEST.json.asc",\n'
  printf '  "release_metadata_sha256": "%s",\n' "$(sha256_of "$META")"
  printf '  "artifacts": [\n'
  i=0
  while [ "$i" -lt "${#ART_PATHS[@]}" ]; do
    sep=','; [ "$i" -eq $((${#ART_PATHS[@]}-1)) ] && sep=''
    printf '    { "path": "%s", "sha256": "%s" }%s\n' \
      "${ART_PATHS[$i]}" "$(sha256_of "$TMPB/${ART_PATHS[$i]}")" "$sep"
    i=$((i+1))
  done
  printf '  ]\n'
  printf '}\n'
} > "$SMAN" || die "cannot write SIGNING-MANIFEST.json"
chmod 0644 "$TMPB/SHA256SUMS" "$META" "$SMAN"

BOOT_SHA="$(sha256_of "$TMPB/pixel-bootstrap.sh")"

# INSTALL.md / VERIFY.md — operator-facing, concrete values, no placeholders.
INSTALL_MD="$TMPB/INSTALL.md"
{
  printf '# Install pixel-development %s\n\n' "$VERSION"
  printf 'Verified install — fetch, verify, then run (never pipe a download into a shell):\n\n'
  printf '```bash\n'
  printf '# 1. Fetch the bootstrap script from the immutable commit URL\n'
  printf 'curl -fL -o pixel-bootstrap.sh \\\n'
  printf '  "https://raw.githubusercontent.com/B0LK13/pixel-development/%s/pixel-bootstrap.sh"\n\n' "$COMMIT"
  printf '# 2. Verify it against the pinned SHA-256 (must print: pixel-bootstrap.sh: OK)\n'
  printf 'printf '"'"'%%s  %%s\\n'"'"' \\\n'
  printf '  "%s" \\\n' "$BOOT_SHA"
  printf '  "pixel-bootstrap.sh" | sha256sum -c -\n\n'
  printf '# 3. Run it — pinning the same commit for the two setup scripts\n'
  printf 'PIXEL_REPO_BASE="https://raw.githubusercontent.com/B0LK13/pixel-development/%s" \\\n' "$COMMIT"
  printf '  bash pixel-bootstrap.sh --open-store\n'
  printf '```\n\n'
  printf 'Bundle contents: pixel-bootstrap.sh (entry point), pixel-dev-setup.sh,\n'
  printf 'pixel-apps-setup.sh, bootstrap-checksums.txt (integrity pins), SHA256SUMS,\n'
  printf 'RELEASE-METADATA.json, SIGNING-MANIFEST.json, INSTALL.md, VERIFY.md.\n'
} > "$INSTALL_MD" || die "cannot write INSTALL.md"

VERIFY_MD="$TMPB/VERIFY.md"
{
  printf '# Verify pixel-development %s\n\n' "$VERSION"
  printf 'Integrity only (proves the bytes match the release metadata — NOT authorship):\n\n'
  printf '```bash\n'
  printf 'bash scripts/verify-release-bundle.sh --bundle ./%s\n' "$BUNDLE_NAME"
  printf '```\n'
  printf 'Expected verdict: `verified-integrity-only`.\n\n'
  printf 'Signed (once a maintainer public key is published out-of-band):\n\n'
  printf '```bash\n'
  printf 'bash scripts/verify-release-bundle.sh \\\n'
  printf '  --bundle ./%s \\\n' "$BUNDLE_NAME"
  printf '  --signature ./%s/SIGNING-MANIFEST.json.asc \\\n' "$BUNDLE_NAME"
  printf '  --keyring /path/to/pixel-release-signing.gpg \\\n'
  printf '  --require-signature\n'
  printf '```\n'
  printf 'Expected verdict: `verified-signed`. See docs/RELEASE_SIGNING.md for the\n'
  printf 'operator signing procedure and the missing/invalid-signature policy.\n'
} > "$VERIFY_MD" || die "cannot write VERIFY.md"
chmod 0644 "$INSTALL_MD" "$VERIFY_MD"

# Pin file mtimes for reproducible archiving when requested.
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  find "$TMPB" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} + 2>/dev/null \
    || find "$TMPB" -exec touch -d "@$SOURCE_DATE_EPOCH" {} + \
    || die "touch cannot apply SOURCE_DATE_EPOCH (needs GNU-compatible touch -d)"
fi

mv "$TMPB" "$OUT_PARENT/$BUNDLE_NAME" || die "cannot move bundle into place"
FAILED=0
printf 'release candidate built: %s/%s\n' "$OUT_PARENT" "$BUNDLE_NAME"
printf '  version: %s  commit: %s  artifacts: %d  created_at: %s\n' \
  "$VERSION" "$COMMIT" "${#ART_PATHS[@]}" "$CREATED_AT"
printf 'next: operator reviews, then signs offline (docs/RELEASE_SIGNING.md)\n'

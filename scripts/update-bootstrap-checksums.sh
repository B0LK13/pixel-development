#!/usr/bin/env bash
###############################################################################
#  scripts/update-bootstrap-checksums.sh — checksum lifecycle for the three   #
#  pinned bootstrap entry points (see docs/BOOTSTRAP_TRUST_MODEL.md). One     #
#  lockstep workflow keeps config/bootstrap-checksums.txt AND the digests     #
#  embedded in pixel-bootstrap.sh in sync with the actual files — no two      #
#  sources of truth.                                                          #
#                                                                             #
#  Usage: bash scripts/update-bootstrap-checksums.sh [--check|--write]        #
#    --check  (default) verify manifest + embedded digests vs. the files;     #
#             exit 0 when current, exit 1 (itemized) when stale. No writes.   #
#    --write  update embedded digests first, then the manifest (atomic        #
#             temp+rename); exit 0, printing what changed.                    #
#  Exit codes: 0 ok · 1 stale / failed · 2 usage error                        #
###############################################################################
set -uo pipefail

MODE='check' SEEN_CHECK='' SEEN_WRITE=''
for a in "$@"; do
  case "$a" in
    --check) SEEN_CHECK=1 ;;
    --write) SEEN_WRITE=1 ;;
    --help|-h) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "update-bootstrap-checksums: unknown argument: $a (try --help)" >&2; exit 2 ;;
  esac
done
if [ -n "$SEEN_CHECK" ] && [ -n "$SEEN_WRITE" ]; then
  echo "update-bootstrap-checksums: --check and --write conflict" >&2; exit 2
fi
if [ -n "$SEEN_WRITE" ]; then MODE='write'; fi

die(){ printf 'update-bootstrap-checksums: %s\n' "$*" >&2; exit 1; }

# --- locate the repository root (this script lives in <root>/scripts/) -------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" \
  || die "cannot resolve script directory"
ROOT="$(dirname -- "$SCRIPT_DIR")"
[ -f "$ROOT/pixel-bootstrap.sh" ] && [ -d "$ROOT/config" ] \
  || die "repository root not recognized at $ROOT (expected pixel-bootstrap.sh + config/)"

# --- canonical artifact list (basenames only, sorted — deterministic order) --
ARTIFACTS="pixel-apps-setup.sh pixel-bootstrap.sh pixel-dev-setup.sh"
MANIFEST="$ROOT/config/bootstrap-checksums.txt"
TEMPS=()
cleanup(){ for t in "${TEMPS[@]:-}"; do [ -n "$t" ] && rm -f "$t"; done; }
trap cleanup EXIT INT TERM

sha256_of(){
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else die "no SHA-256 tool (sha256sum or shasum)"; fi
}

# --- load + validate the artifacts (no symlinks, no escapes: basenames only) -
declare -A ACTUAL
for s in $ARTIFACTS; do
  p="$ROOT/$s"
  [ -L "$p" ] && die "refusing symlink artifact: $s"
  [ -f "$p" ] || die "missing artifact: $s"
  ACTUAL[$s]="$(sha256_of "$p")"
done

# --- parse the manifest (comments/blank lines preserved; digest lines strict)-
#     a valid digest line: ^<64 lowercase hex>  <two spaces><artifact name>$
declare -A MANIFEST_SHA SEEN
MANIFEST_OK=1
ORDER_OK=1
prev=""
note(){ printf '  ✖    %s\n' "$*" >&2; MANIFEST_OK=0; }
if [ -f "$MANIFEST" ]; then
  ln=0
  while IFS= read -r line || [ -n "$line" ]; do
    ln=$((ln+1))
    case "$line" in ''|'#'*) continue ;; esac
    if [[ "$line" =~ ^[0-9a-f]{64}\ \ ([a-z.-]+)$ ]]; then
      name="${BASH_REMATCH[1]}"
      case " $ARTIFACTS " in *" $name "*) ;; *) note "line $ln: unexpected artifact: $name" ; continue ;; esac
      if [ -n "${SEEN[$name]:-}" ]; then note "line $ln: duplicate entry: $name"; continue; fi
      SEEN[$name]=1
      MANIFEST_SHA[$name]="${line%% *}"
      # canonical order check
      if [ -n "$prev" ] && [ "$(printf '%s\n%s\n' "$prev" "$name" | sort | head -1)" != "$prev" ]; then ORDER_OK=0; fi
      prev="$name"
    else
      note "line $ln: malformed digest line: $line"
    fi
  done < "$MANIFEST"
else
  [ "$MODE" = write ] || die "manifest not found: $MANIFEST"
fi
for s in $ARTIFACTS; do
  [ -f "$MANIFEST" ] && [ -z "${MANIFEST_SHA[$s]:-}" ] && note "missing manifest entry: $s"
done
if [ "$MODE" = write ] && [ "$MANIFEST_OK" = 0 ]; then
  die "manifest has errors (see above) — refusing to rewrite; fix config/bootstrap-checksums.txt by hand"
fi

# --- embedded digests in pixel-bootstrap.sh (dev/apps only) -------------------
embedded_sha(){ grep -A1 -- "$1)" "$ROOT/pixel-bootstrap.sh" | grep -oE '[0-9a-f]{64}' | head -1; }

report_check(){
  local s bad=0
  for s in $ARTIFACTS; do
    if [ "${MANIFEST_SHA[$s]:-}" = "${ACTUAL[$s]}" ]; then
      printf '  ok   manifest: %s\n' "$s"
    else
      printf '  ✖    STALE: %s (manifest %s, actual %s)\n' "$s" "${MANIFEST_SHA[$s]:-<missing>}" "${ACTUAL[$s]}" >&2; bad=1
    fi
  done
  for s in pixel-dev-setup.sh pixel-apps-setup.sh; do
    if [ "$(embedded_sha "$s")" = "${ACTUAL[$s]}" ]; then
      printf '  ok   embedded: %s\n' "$s"
    else
      printf '  ✖    EMBEDDED STALE: %s\n' "$s" >&2; bad=1
    fi
  done
  [ "$ORDER_OK" = 1 ] || { printf '  ✖    digest lines not in canonical sorted order\n' >&2; bad=1; }
  [ "$MANIFEST_OK" = 1 ] || bad=1
  return $bad
}

rewrite_embedded(){ # $1 script name  $2 new digest — atomic temp+rename
  local name="$1" new="$2" boot="$ROOT/pixel-bootstrap.sh" tmpf n perm
  n="$(grep -cE "^[[:space:]]*${name}\).*[0-9a-f]{64}" "$boot")"
  [ "$n" -eq 1 ] || die "embedded digest for $name: expected 1 line, found $n — refusing to rewrite"
  perm="$(stat -c %a "$boot" 2>/dev/null || printf '644')"
  tmpf="$(mktemp "$ROOT/.embedded.XXXXXX")"; TEMPS+=("$tmpf")
  sed -E "/^[[:space:]]*${name}\).*[0-9a-f]{64}/ s/[0-9a-f]{64}/${new}/" "$boot" > "$tmpf" \
    || die "failed rewriting embedded digest for $name"
  if ! cmp -s "$tmpf" "$boot"; then
    chmod "$perm" "$tmpf" 2>/dev/null || true
    mv "$tmpf" "$boot" || die "cannot update $boot"
  fi
}

write_manifest(){
  local tmpm s perm=644
  tmpm="$(mktemp "$ROOT/config/.bootstrap-checksums.XXXXXX")" \
    || die "cannot create temp file in $ROOT/config (read-only?)"
  TEMPS+=("$tmpm")
  if [ -f "$MANIFEST" ]; then
    perm="$(stat -c %a "$MANIFEST" 2>/dev/null || printf '644')"
    grep -E '^(#|$)' "$MANIFEST" > "$tmpm" || true
  else
    printf '# Bootstrap integrity pins — SHA-256 digests (schema v1).\n' > "$tmpm"
    printf '# Generated by scripts/update-bootstrap-checksums.sh; do not hand-edit digest lines.\n' >> "$tmpm"
  fi
  for s in $ARTIFACTS; do printf '%s  %s\n' "${ACTUAL[$s]}" "$s" >> "$tmpm"; done
  if [ -f "$MANIFEST" ] && cmp -s "$tmpm" "$MANIFEST"; then
    printf '  ok   manifest already current\n'
  else
    chmod "$perm" "$tmpm" 2>/dev/null || true
    mv "$tmpm" "$MANIFEST" || die "cannot replace $MANIFEST"
    printf '  ✔    manifest written: %s\n' "$MANIFEST"
  fi
}

if [ "$MODE" = check ]; then
  if report_check; then
    printf 'checksum manifest is current (3 artifacts, embedded digests in lockstep)\n'
    exit 0
  fi
  printf 'checksum manifest is STALE — run: bash scripts/update-bootstrap-checksums.sh --write\n' >&2
  exit 1
fi

# --write: embedded first (its edit changes pixel-bootstrap.sh's own digest),
# then re-hash the anchor, then the manifest.
for s in pixel-dev-setup.sh pixel-apps-setup.sh; do
  if [ "$(embedded_sha "$s")" != "${ACTUAL[$s]}" ]; then
    rewrite_embedded "$s" "${ACTUAL[$s]}"
    printf '  ✔    embedded digest updated: %s\n' "$s"
  else
    printf '  ok   embedded: %s\n' "$s"
  fi
done
ACTUAL[pixel-bootstrap.sh]="$(sha256_of "$ROOT/pixel-bootstrap.sh")"
write_manifest
printf 'checksum manifest updated (3 artifacts, embedded digests in lockstep)\n'

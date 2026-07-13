#!/usr/bin/env bash
###############################################################################
#  scripts/verify-release-bundle.sh — standalone verifier for a release       #
#  candidate bundle built by scripts/build-release-candidate.sh. Offline,     #
#  no network, no secrets. See docs/RELEASE_SIGNING.md and                    #
#  docs/BOOTSTRAP_RELEASE_PROCESS.md.                                         #
#                                                                             #
#  Usage:                                                                     #
#    bash scripts/verify-release-bundle.sh --bundle=DIR                       #
#    bash scripts/verify-release-bundle.sh --bundle=DIR \                     #
#      --signature=FILE --keyring=PUBKEY_FILE [--require-signature]           #
#                                                                             #
#  Order of trust (do not reorder): layout → metadata schema → signing        #
#  manifest consistency → SIGNATURE → checksums+modes. The signature is       #
#  verified BEFORE the manifest's hashes are trusted, and artifact bytes      #
#  are checked AFTER the signature — a valid signature never bypasses         #
#  checksum verification, and checksums never claim authenticity.             #
#                                                                             #
#  Verdicts (stdout): verified-integrity-only · verified-signed ·             #
#    failed-layout · failed-metadata · failed-signature · failed-checksum ·   #
#    failed-policy                                                            #
#  Exit codes: 0 verified · 1 trust failure · 2 usage error                   #
###############################################################################
set -uo pipefail

BUNDLE='' SIG='' KEYRING='' REQ_SIG=''
for a in "$@"; do
  case "$a" in
    --bundle=*)     BUNDLE="${a#*=}" ;;
    --signature=*)  SIG="${a#*=}" ;;
    --keyring=*)    KEYRING="${a#*=}" ;;
    --require-signature) REQ_SIG=1 ;;
    --help|-h) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*) echo "verify-release-bundle: unknown flag: $a (try --help)" >&2; exit 2 ;;
    *)   echo "verify-release-bundle: unexpected argument: $a (try --help)" >&2; exit 2 ;;
  esac
done

# --- usage validation first (repo CLI contract: before touching the bundle) ---
[ -n "$BUNDLE" ] || { echo "usage: bash scripts/verify-release-bundle.sh --bundle=DIR [--signature=FILE --keyring=FILE] [--require-signature]" >&2; exit 2; }
if [ -n "$SIG" ] && [ -z "$KEYRING" ]; then
  echo "verify-release-bundle: --signature requires --keyring" >&2; exit 2
fi
# --keyring alone is valid: the bundle's SIGNING-MANIFEST.json.asc is then
# auto-detected (absent .asc → integrity-only, or failed-policy when required).

fail(){ # $1 verdict-word  $2 detail — verdict on stdout, detail on stderr
  printf 'verify-release-bundle: %s\n' "$2" >&2
  printf 'verdict: %s\n' "$1"
  exit 1
}
ok(){ printf '  ok   %s\n' "$1"; }

# --- locate the repository root (for the gpgv signature helper) --------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" \
  || fail failed-policy "cannot resolve script directory"
ROOT="$(dirname -- "$SCRIPT_DIR")"
HELPER="$ROOT/scripts/verify-bootstrap-signature.sh"

sha256_of(){
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else fail failed-policy "no SHA-256 tool (sha256sum or shasum)"; fi
}
mode_of(){ stat -c %a "$1" 2>/dev/null; }   # empty when unsupported

# scalar JSON field (line-oriented schema emitted by the builder)
jget(){ grep -E "^  \"$2\": " "$1" 2>/dev/null | head -1 | sed "s/^  \"$2\": //; s/,\$//; s/^\"//; s/\"\$//"; }

CORE_FILES="INSTALL.md RELEASE-METADATA.json SHA256SUMS SIGNING-MANIFEST.json VERIFY.md bootstrap-checksums.txt pixel-apps-setup.sh pixel-bootstrap.sh pixel-dev-setup.sh"

# --- 1. layout -----------------------------------------------------------------
[ -e "$BUNDLE" ] || fail failed-layout "bundle not found: $BUNDLE"
[ -d "$BUNDLE" ] || fail failed-layout "not a directory: $BUNDLE"
[ -L "$BUNDLE" ] && fail failed-layout "bundle path is a symlink: $BUNDLE"

while IFS= read -r e; do
  [ -n "$e" ] || continue
  name="${e##*/}"
  case "$name" in *..*|*/*|-*) fail failed-layout "unsafe entry name: $name" ;; esac
  [ -L "$e" ] && fail failed-layout "symlink entry: $name"
  [ -d "$e" ] && fail failed-layout "unexpected directory entry: $name"
  case " $CORE_FILES SIGNING-MANIFEST.json.asc " in
    *" $name "*) ;;
    *) fail failed-layout "unexpected entry: $name" ;;
  esac
done <<EOF
$(find "$BUNDLE" -maxdepth 1 -mindepth 1 2>/dev/null)
EOF
for f in $CORE_FILES; do
  [ -f "$BUNDLE/$f" ] || fail failed-layout "missing file: $f"
done
ok "layout (9 core files, no unsafe entries)"

# --- 2. RELEASE-METADATA.json schema ---------------------------------------------
META="$BUNDLE/RELEASE-METADATA.json"
[ "$(jget "$META" schema_version)" = "1.0" ] \
  || fail failed-metadata "unsupported schema version: $(jget "$META" schema_version)"
[ "$(jget "$META" project)" = "pixel-development" ] || fail failed-metadata "wrong project"
MVER="$(jget "$META" version)"
[[ "$MVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail failed-metadata "malformed version: $MVER"
MCOMMIT="$(jget "$META" commit)"
[[ "$MCOMMIT" =~ ^[0-9a-f]{40}$ ]] || fail failed-metadata "malformed or abbreviated commit: $MCOMMIT"
[[ "$(jget "$META" created_at)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
  || fail failed-metadata "malformed created_at"
[ "$(jget "$META" bootstrap_entrypoint)" = "pixel-bootstrap.sh" ] \
  || fail failed-metadata "wrong bootstrap_entrypoint"
[ "$(jget "$META" checksum_algorithm)" = "sha256" ] \
  || fail failed-metadata "unknown checksum algorithm: $(jget "$META" checksum_algorithm)"
[ "$(jget "$META" signature_algorithm)" = "openpgp-detached" ] \
  || fail failed-metadata "unknown signature algorithm: $(jget "$META" signature_algorithm)"
[ "$(jget "$META" signature_required)" = "false" ] \
  || fail failed-metadata "signature_required must be false (policy is the verifier's, not the bundle's)"

# artifacts: strict single-line object shape, then set/role/mode policy
ART_RE='^    \{ "path": "[a-z0-9.-]+", "sha256": "[0-9a-f]{64}", "mode": "0[0-7]{3}", "role": "[a-z-]+" \},?$'
n_art="$(grep -cE '^    \{ "path": ' "$META")"
[ "$n_art" -gt 0 ] || fail failed-metadata "no artifacts in metadata"
bad_art="$(grep -E '^    \{ "path": ' "$META" | grep -cvE "$ART_RE" || true)"
[ "${bad_art:-0}" -eq 0 ] || fail failed-metadata "malformed artifact entry in metadata"

meta_paths="$(grep -oE '^    \{ "path": "[a-z0-9.-]+"' "$META" | sed 's/.*"path": "//; s/"$//')"

# expected artifacts with role + mode policy; record metadata digests
declare -A WANT_ROLE WANT_MODE META_SHA SEEN_P
WANT_ROLE[bootstrap-checksums.txt]=checksum-manifest; WANT_MODE[bootstrap-checksums.txt]=0644
WANT_ROLE[pixel-apps-setup.sh]=setup-apps;             WANT_MODE[pixel-apps-setup.sh]=0755
WANT_ROLE[pixel-bootstrap.sh]=bootstrap;               WANT_MODE[pixel-bootstrap.sh]=0755
WANT_ROLE[pixel-dev-setup.sh]=setup-dev;               WANT_MODE[pixel-dev-setup.sh]=0755
n_paths=0; dup=''
while IFS= read -r p; do
  [ -n "$p" ] || continue
  n_paths=$((n_paths+1))
  [ -n "${SEEN_P[$p]:-}" ] && dup="$p"
  SEEN_P[$p]=1
  case "$p" in bootstrap-checksums.txt|pixel-apps-setup.sh|pixel-bootstrap.sh|pixel-dev-setup.sh) ;;
    *) fail failed-metadata "unexpected artifact: $p" ;;
  esac
  line="$(grep -F "\"path\": \"$p\"" "$META")"
  got_role="$(printf '%s' "$line" | grep -oE '"role": "[a-z-]+"' | sed 's/.*: "//; s/"$//')"
  got_mode="$(printf '%s' "$line" | grep -oE '"mode": "0[0-7]{3}"' | grep -oE '0[0-7]{3}')"
  [ "$got_role" = "${WANT_ROLE[$p]}" ] || fail failed-metadata "role mismatch for $p: $got_role (want ${WANT_ROLE[$p]})"
  [ "$got_mode" = "${WANT_MODE[$p]}" ] || fail failed-metadata "mode mismatch for $p: $got_mode (want ${WANT_MODE[$p]})"
  META_SHA[$p]="$(printf '%s' "$line" | grep -oE '[0-9a-f]{64}')"
done <<EOF
$meta_paths
EOF
[ -z "$dup" ] || fail failed-metadata "duplicate artifact in metadata: $dup"
[ "$n_paths" -eq 4 ] || fail failed-metadata "artifact count != 4"
for p in bootstrap-checksums.txt pixel-apps-setup.sh pixel-bootstrap.sh pixel-dev-setup.sh; do
  [ -n "${META_SHA[$p]:-}" ] || fail failed-metadata "missing artifact in metadata: $p"
done
ok "metadata (schema 1.0, version $MVER, commit ${MCOMMIT:0:12}…, 4 artifacts)"

# --- 3. SIGNING-MANIFEST.json + cross-consistency ---------------------------------
SMAN="$BUNDLE/SIGNING-MANIFEST.json"
[ "$(jget "$SMAN" schema_version)" = "1.0" ] || fail failed-metadata "signing manifest: unsupported schema version"
[ "$(jget "$SMAN" project)" = "pixel-development" ] || fail failed-metadata "signing manifest: wrong project"
[ "$(jget "$SMAN" signature_algorithm)" = "openpgp-detached" ] \
  || fail failed-metadata "signing manifest: unknown signature algorithm"
[ "$(jget "$SMAN" expected_signature)" = "SIGNING-MANIFEST.json.asc" ] \
  || fail failed-metadata "signing manifest: unexpected signature filename"
[ "$(jget "$SMAN" version)" = "$MVER" ] || fail failed-metadata "version mismatch: manifest vs metadata"
[ "$(jget "$SMAN" commit)" = "$MCOMMIT" ] || fail failed-metadata "commit mismatch: manifest vs metadata"
[ "$(jget "$SMAN" release_metadata_sha256)" = "$(sha256_of "$META")" ] \
  || fail failed-metadata "signing manifest does not match RELEASE-METADATA.json (metadata altered?)"

SMAN_RE='^    \{ "path": "[a-z0-9.-]+", "sha256": "[0-9a-f]{64}" \},?$'
bad_sman="$(grep -E '^    \{ "path": ' "$SMAN" | grep -cvE "$SMAN_RE" || true)"
[ "${bad_sman:-0}" -eq 0 ] || fail failed-metadata "malformed artifact entry in signing manifest"
for p in bootstrap-checksums.txt pixel-apps-setup.sh pixel-bootstrap.sh pixel-dev-setup.sh; do
  sline="$(grep -F "\"path\": \"$p\"" "$SMAN")"
  [ -n "$sline" ] || fail failed-metadata "signing manifest missing artifact: $p"
  [ "$(printf '%s' "$sline" | grep -oE '[0-9a-f]{64}')" = "${META_SHA[$p]}" ] \
    || fail failed-metadata "digest mismatch manifest vs metadata: $p"
done
[ "$(grep -cE '^    \{ "path": ' "$SMAN")" -eq 4 ] || fail failed-metadata "signing manifest: artifact count != 4"
ok "signing manifest (bound to version, commit, metadata digest, artifact hashes)"

# --- 4. signature (BEFORE trusting the manifest's hashes for step 5) -------------
ASC="$BUNDLE/SIGNING-MANIFEST.json.asc"
EFF_SIG="$SIG"
[ -z "$EFF_SIG" ] && [ -f "$ASC" ] && EFF_SIG="$ASC"
SIGNED=''
if [ -z "$EFF_SIG" ]; then
  [ -n "$REQ_SIG" ] && fail failed-policy "signature required (--require-signature) but none provided"
  printf '  note signature: not provided — integrity-only verification\n'
else
  if [ -z "$KEYRING" ]; then
    [ -n "$REQ_SIG" ] && fail failed-policy "signature present but no --keyring to verify against (required)"
    printf '  note signature: present but NOT verified (no --keyring) — integrity-only\n'
  else
    [ -f "$EFF_SIG" ] || fail failed-signature "signature file not found: $EFF_SIG"
    [ -f "$KEYRING" ] || fail failed-signature "keyring not found: $KEYRING"
    [ -f "$HELPER" ] || fail failed-policy "signature helper missing: $HELPER"
    if serr="$(bash "$HELPER" --keyring="$KEYRING" --signature="$EFF_SIG" "$SMAN" 2>&1 >/dev/null)"; then
      SIGNED=1
      ok "signature (detached openpgp over SIGNING-MANIFEST.json)"
    else
      printf '%s\n' "$serr" >&2
      fail failed-signature "signature verification FAILED — do not trust this bundle"
    fi
  fi
fi

# --- 5. checksums + modes (artifact bytes vs the now-trusted record) --------------
MODE_NOTE=''
for p in bootstrap-checksums.txt pixel-apps-setup.sh pixel-bootstrap.sh pixel-dev-setup.sh; do
  got="$(sha256_of "$BUNDLE/$p")"
  [ "$got" = "${META_SHA[$p]}" ] || fail failed-checksum "digest mismatch: $p"
  want_mode="${WANT_MODE[$p]#0}"   # metadata "0755" vs stat "755"
  m="$(mode_of "$BUNDLE/$p")"
  if [ -n "$m" ]; then
    [ "$m" = "$want_mode" ] || fail failed-checksum "mode drift: $p (want $want_mode, got $m)"
  else
    MODE_NOTE=1
  fi
done
# SHA256SUMS must agree with the metadata record (it is operator-facing)
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  sdig="${line%% *}"
  sname="${line##* }"
  case "$sname" in bootstrap-checksums.txt|pixel-apps-setup.sh|pixel-bootstrap.sh|pixel-dev-setup.sh) ;;
    *) fail failed-checksum "SHA256SUMS lists unexpected file: $sname" ;;
  esac
  [ "$sdig" = "${META_SHA[$sname]}" ] || fail failed-checksum "SHA256SUMS disagrees with metadata: $sname"
done < "$BUNDLE/SHA256SUMS"
for p in bootstrap-checksums.txt pixel-apps-setup.sh pixel-bootstrap.sh pixel-dev-setup.sh; do
  grep -qE "^[0-9a-f]{64}  $p\$" "$BUNDLE/SHA256SUMS" || fail failed-checksum "SHA256SUMS missing entry: $p"
done
ok "checksums + modes (4 artifacts)"
[ -n "$MODE_NOTE" ] && printf '  note mode enforcement skipped (stat -c unsupported on this host)\n'

# --- verdict -----------------------------------------------------------------------
if [ -n "$SIGNED" ]; then
  printf 'verdict: verified-signed\n'
else
  printf 'integrity proven; authenticity NOT established (no verified signature)\n'
  printf 'verdict: verified-integrity-only\n'
fi
exit 0

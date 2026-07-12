#!/usr/bin/env bash
###############################################################################
#  scripts/verify-bootstrap-signature.sh — verify a detached gpgv signature   #
#  over a bootstrap release artifact (Tier 2 of the bootstrap trust model;    #
#  see docs/BOOTSTRAP_TRUST_MODEL.md and docs/adr/ADR-BOOTSTRAP-ANCHOR-       #
#  AUTHENTICITY.md).                                                          #
#                                                                             #
#  Usage:                                                                     #
#    bash scripts/verify-bootstrap-signature.sh \                             #
#      --keyring=PUBKEY_FILE --signature=SIG_FILE ARTIFACT                    #
#                                                                             #
#  Exit codes: 0 verified · 1 failed/missing input/no verifier · 2 usage      #
#  Env seam: GPGV_BIN (unset→PATH gpgv; empty→missing; path→must be           #
#  executable; bare name→PATH lookup) — same contract as the pixel-autodev    #
#  tool seams; used by the test harness, a no-op in normal use.               #
###############################################################################
set -uo pipefail

KEYRING='' SIG='' ARTIFACT=''
for a in "$@"; do
  case "$a" in
    --keyring=*)   KEYRING="${a#*=}" ;;
    --signature=*) SIG="${a#*=}" ;;
    --help|-h) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*) echo "verify-bootstrap-signature: unknown flag: $a (try --help)" >&2; exit 2 ;;
    *) if [ -z "$ARTIFACT" ]; then ARTIFACT="$a"
       else echo "verify-bootstrap-signature: unexpected extra argument: $a" >&2; exit 2; fi ;;
  esac
done

die(){ printf 'verify-bootstrap-signature: %s\n' "$*" >&2; exit 1; }

# Usage errors come before any dependency resolution (repo CLI contract).
if [ -z "$KEYRING" ] || [ -z "$SIG" ] || [ -z "$ARTIFACT" ]; then
  echo "usage: bash scripts/verify-bootstrap-signature.sh --keyring=PUBKEY_FILE --signature=SIG_FILE ARTIFACT" >&2
  exit 2
fi

# Resolve the verifier through the seam. gpgv is the right tool here: it
# checks a detached signature against a specific keyring and nothing else —
# no keyserver, no network, no trustdb writes.
gpgv_bin="${GPGV_BIN-gpgv}"
if [ -n "${GPGV_BIN+x}" ]; then
  [ -n "$gpgv_bin" ] || die "gpgv not found (GPGV_BIN set but empty)"
  case "$gpgv_bin" in
    */*) [ -x "$gpgv_bin" ] || die "GPGV_BIN is not an executable file: $gpgv_bin" ;;
    *) gpgv_bin="$(command -v "$gpgv_bin" 2>/dev/null)" || die "gpgv not found on PATH: $GPGV_BIN" ;;
  esac
else
  gpgv_bin="$(command -v gpgv 2>/dev/null)" \
    || die "gpgv not found — install gnupg first (Termux: pkg install gnupg)"
fi

[ -f "$KEYRING" ]  || die "keyring not found: $KEYRING"
[ -f "$SIG" ]      || die "signature not found: $SIG"
[ -f "$ARTIFACT" ] || die "artifact not found: $ARTIFACT"

if verr="$("$gpgv_bin" --keyring "$KEYRING" "$SIG" "$ARTIFACT" 2>&1 >/dev/null)"; then
  printf 'signature verified: %s\n' "$ARTIFACT"
else
  printf '%s\n' "$verr" >&2
  die "signature verification FAILED for $ARTIFACT — do not run it"
fi

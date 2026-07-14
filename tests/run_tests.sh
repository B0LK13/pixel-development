#!/usr/bin/env bash
###############################################################################
# tests/run_tests.sh — targeted/full harness wrapper                           #
###############################################################################
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)" || {
  echo "run_tests: cannot resolve script dir" >&2; exit 1; }
ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)" || {
  echo "run_tests: cannot resolve repo root" >&2; exit 1; }
CORE="$SCRIPT_DIR/run_tests_full.sh"
MAP="$SCRIPT_DIR/section-map.tsv"

die_usage(){ echo "run_tests: $*" >&2; exit 2; }

LIST=0
CHANGED=0
AS_JSON=0
FORMAT=''
SECTION_RAW=''
TEST_RAW=''
TAG_RAW=''
BASE_REF=''
SECTIONS=''
REASONS=''

append_unique(){
  local val="$1"
  case ",$SECTIONS," in *,"$val",*) ;; *) SECTIONS="${SECTIONS:+$SECTIONS,}$val" ;; esac
}
add_reason(){
  REASONS="${REASONS}${REASONS:+
}$1"
}
json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST=1 ;;
    --section=*) SECTION_RAW="${1#*=}" ;;
    --section) [ $# -ge 2 ] || die_usage "--section needs a value"; SECTION_RAW="$2"; shift ;;
    --test=*) TEST_RAW="${1#*=}" ;;
    --test) [ $# -ge 2 ] || die_usage "--test needs a value"; TEST_RAW="$2"; shift ;;
    --tag=*) TAG_RAW="${1#*=}" ;;
    --tag) [ $# -ge 2 ] || die_usage "--tag needs a value"; TAG_RAW="$2"; shift ;;
    --changed) CHANGED=1 ;;
    --base=*) BASE_REF="${1#*=}" ;;
    --base) [ $# -ge 2 ] || die_usage "--base needs a value"; BASE_REF="$2"; shift ;;
    --json) AS_JSON=1 ;;
    --format=*) FORMAT="${1#*=}" ;;
    --format) [ $# -ge 2 ] || die_usage "--format needs a value"; FORMAT="$2"; shift ;;
    --help|-h)
      cat <<'EOF'
Usage: bash tests/run_tests.sh [options]
  --list                          list checks
  --section=<id[,id...]>          target section(s) by numeric section ID
  --test=<check-id[,check-id...]> target by stable check ID (from --list)
  --tag=<tag[,tag...]>            target by check tags
  --changed [--base <ref>]        conservative selection from changed files
  --format json                   structured output (alias: --json)
  --help, -h
EOF
      exit 0
      ;;
    *) die_usage "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

if [ -n "$FORMAT" ]; then
  case "$FORMAT" in json) AS_JSON=1 ;; *) die_usage "--format must be json" ;; esac
fi

[ -f "$CORE" ] || { echo "run_tests: missing $CORE" >&2; exit 1; }
[ -f "$MAP" ] || { echo "run_tests: missing $MAP" >&2; exit 1; }

# section_id\tcheck_id\ttitle\tdeps\ttags\tduration\tplatforms
map_rows(){ awk -F '\t' 'NF>=7 && $1 !~ /^#/ {print}' "$MAP"; }
lookup_section(){
  q="$1" awk -F '\t' '
    BEGIN{found=0}
    NF>=2 && $1 !~ /^#/ && ($1==ENVIRON["q"] || $2==ENVIRON["q"]) {print $1; found=1; exit 0}
    END{if(!found) exit 1}
  ' "$MAP"
}

list_plain(){
  echo "checks:"
  map_rows | while IFS=$'\t' read -r sec cid title deps tags dur plat; do
    printf '  - %s\t%s\tsection=%s\tdeps=%s\ttags=%s\tduration=%s\tplatforms=%s\n' \
      "$cid" "$title" "$sec" "$deps" "$tags" "$dur" "$plat"
  done
}
list_json(){
  printf '{\n  "checks": [\n'
  first=1
  while IFS=$'\t' read -r sec cid title deps tags dur plat; do
    [ "$first" -eq 1 ] || printf ',\n'
    first=0
    printf '    {"check_id":"%s","title":"%s","section":%s,"dependencies":"%s","tags":"%s","expected_duration":"%s","supported_platforms":"%s"}' \
      "$(json_escape "$cid")" "$(json_escape "$title")" "$sec" "$(json_escape "$deps")" "$(json_escape "$tags")" "$(json_escape "$dur")" "$(json_escape "$plat")"
  done <<EOF
$(map_rows)
EOF
  printf '\n  ]\n}\n'
}
if [ "$LIST" = 1 ]; then
  if [ "$AS_JSON" = 1 ]; then list_json; else list_plain; fi
  exit 0
fi

select_from_tokens(){
  local raw="$1" reason="$2" tok sec
  IFS=',' read -r -a toks <<<"$raw"
  for tok in "${toks[@]}"; do
    [ -n "$tok" ] || continue
    if ! [[ "$tok" =~ ^[0-9a-zA-Z._-]+$ ]]; then
      die_usage "invalid selector syntax: $tok"
    fi
    sec="$(lookup_section "$tok")" || die_usage "unknown selector: $tok"
    [ -n "$sec" ] || die_usage "unknown selector: $tok"
    append_unique "$sec"
    add_reason "$reason: $tok -> section $sec"
  done
}

[ -n "$SECTION_RAW" ] && select_from_tokens "$SECTION_RAW" "section selector"
[ -n "$TEST_RAW" ] && select_from_tokens "$TEST_RAW" "test selector"

if [ -n "$TAG_RAW" ]; then
  IFS=',' read -r -a tags <<<"$TAG_RAW"
  for tag in "${tags[@]}"; do
    [ -n "$tag" ] || continue
    found=0
    while IFS=$'\t' read -r sec cid title deps tags_col dur plat; do
      case ",$tags_col," in
        *,"$tag",*)
          append_unique "$sec"
          add_reason "tag selector: $tag -> section $sec ($cid)"
          found=1
          ;;
      esac
    done <<EOF
$(map_rows)
EOF
    [ "$found" -eq 1 ] || die_usage "unknown tag: $tag"
  done
fi

if [ "$CHANGED" = 1 ]; then
  changed_paths=''
  fallback_to_full=0
  if [ "$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null || echo false)" = "true" ]; then
    add_reason "conservative fallback: shallow repository detected selects full gate"
    fallback_to_full=1
  fi
  if [ "$fallback_to_full" -eq 0 ] && [ -n "$BASE_REF" ]; then
    if ! git -C "$ROOT" rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
      add_reason "conservative fallback: base ref '$BASE_REF' missing/invalid; using local diff only"
    else
      if ! base_diff="$(git -C "$ROOT" diff --name-only "$BASE_REF"...HEAD 2>/dev/null)"; then
        add_reason "conservative fallback: git diff '$BASE_REF'...HEAD failed selects full gate"
        fallback_to_full=1
      else
        changed_paths="$base_diff"
      fi
    fi
  fi
  if [ "$fallback_to_full" -eq 0 ]; then
    if ! git -C "$ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
      add_reason "conservative fallback: missing HEAD ref selects full gate"
      fallback_to_full=1
    else
      local_diff="$( { git -C "$ROOT" diff --name-only --cached 2>/dev/null; git -C "$ROOT" diff --name-only 2>/dev/null; git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null; } | awk 'NF' )"
      changed_paths="${changed_paths}
${local_diff}"
      changed_paths="$(printf '%s\n' "$changed_paths" | awk 'NF' | sort -u)"
      if [ -z "$changed_paths" ]; then
        add_reason "no changed files detected; selecting validation subset section 0"
        SECTIONS='0'
        changed_paths=''
      fi
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        case "$p" in
          .github/*) append_unique 22; append_unique 30; add_reason "changed path: $p -> workflow/ci checks" ;;
          README.md|CLAUDE.md) append_unique 21; append_unique 28; append_unique 29; append_unique 31; add_reason "changed path: $p -> repo docs checks" ;;
          harness/*) append_unique 31; append_unique 32; append_unique 22; add_reason "changed path: $p -> harness checks" ;;
          .codebase-memory/*) add_reason "changed path: $p -> local session cache ignored" ;;
          tests/*) append_unique 1; append_unique 2; append_unique 8; append_unique 22; append_unique 31; append_unique 32; add_reason "changed path: $p -> harness checks" ;;
          scripts/check-*|AGENTS.md|.agent/*|schemas/*) append_unique 31; append_unique 32; append_unique 22; add_reason "changed path: $p -> agent-os checks" ;;
          scripts/update-bootstrap-checksums.sh|config/bootstrap-checksums.txt) append_unique 16; append_unique 20; add_reason "changed path: $p -> checksum checks" ;;
          pixel-bootstrap.sh|pixel-dev-setup.sh|pixel-apps-setup.sh) append_unique 16; append_unique 17; append_unique 18; add_reason "changed path: $p -> bootstrap checks" ;;
          pixel-autodev.sh) append_unique 5; append_unique 6; append_unique 10; append_unique 11; append_unique 13; append_unique 15; add_reason "changed path: $p -> autodev checks" ;;
          scripts/build-release-candidate.sh) append_unique 24; append_unique 27; add_reason "changed path: $p -> release builder checks" ;;
          scripts/verify-release-bundle.sh) append_unique 25; append_unique 26; append_unique 28; add_reason "changed path: $p -> release verifier checks" ;;
          scripts/*) append_unique 22; append_unique 31; append_unique 32; add_reason "changed path: $p -> scripts checks" ;;
          docs/*|reports/*|evidence/*) append_unique 21; append_unique 28; append_unique 29; append_unique 31; add_reason "changed path: $p -> docs/evidence checks" ;;
          *)
            add_reason "conservative fallback: unknown changed path '$p' selects full gate"
            fallback_to_full=1
            break
            ;;
        esac
      done <<EOF
$changed_paths
EOF
    fi
  fi
  if [ "$fallback_to_full" -eq 1 ]; then
    SECTIONS=''
  fi
fi

resolve_dependencies(){
  local expanded="$SECTIONS" changed=1 sec deps dep
  while [ "$changed" -eq 1 ]; do
    changed=0
    IFS=',' read -r -a current <<<"$expanded"
    for sec in "${current[@]}"; do
      [ -n "$sec" ] || continue
      deps="$(awk -F '\t' -v s="$sec" 'NF>=4 && $1==s {print $4; exit}' "$MAP")"
      [ -n "$deps" ] && [ "$deps" != "-" ] || continue
      IFS=',' read -r -a ds <<<"$deps"
      for dep in "${ds[@]}"; do
        case ",$expanded," in
          *,"$dep",*) ;;
          *)
            expanded="${expanded:+$expanded,}$dep"
            changed=1
            add_reason "dependency: section $sec requires section $dep"
            ;;
        esac
      done
    done
  done
  SECTIONS="$(printf '%s\n' "$expanded" | tr ',' '\n' | awk 'NF' | sort -n | paste -sd, -)"
}
[ -n "$SECTIONS" ] && resolve_dependencies

if [ -n "${PIXEL_SKIP_SECTION_IDS:-}" ] && [ -n "$SECTIONS" ]; then
  skip_set="$(printf '%s' "$PIXEL_SKIP_SECTION_IDS" | tr ',' '\n' | awk 'NF' | sort -n | paste -sd, -)"
  filtered=''
  IFS=',' read -r -a selected_arr <<<"$SECTIONS"
  for s in "${selected_arr[@]}"; do
    case ",$skip_set," in
      *,"$s",*) add_reason "skip filter: section $s removed by PIXEL_SKIP_SECTION_IDS" ;;
      *) filtered="${filtered:+$filtered,}$s" ;;
    esac
  done
  SECTIONS="$filtered"
fi

mode='full'
is_full_gate=true
if [ -n "$SECTIONS" ] || [ "$CHANGED" -eq 1 ] || [ -n "$SECTION_RAW" ] || [ -n "$TEST_RAW" ] || [ -n "$TAG_RAW" ]; then
  if [ -n "$SECTIONS" ]; then
    mode='targeted'
  fi
  is_full_gate=false
fi

LOCK_DIR="$ROOT/reports/logs/run_tests.full.lockdir"
LOCK_HELD=0
lock_file_path(){ printf '%s/%s' "$LOCK_DIR" "$1"; }
lock_read(){ [ -f "$(lock_file_path "$1")" ] && cat "$(lock_file_path "$1")" 2>/dev/null || true; }
lock_release(){
  [ "$LOCK_HELD" -eq 1 ] || return 0
  [ "$(lock_read pid)" = "$$" ] || return 0
  rm -rf "$LOCK_DIR" 2>/dev/null || true
  LOCK_HELD=0
}
lock_acquire_full_gate(){
  [ "$is_full_gate" = true ] || return 0
  mkdir -p "$ROOT/reports/logs" 2>/dev/null || {
    echo "run_tests: cannot create lock directory parent $ROOT/reports/logs" >&2
    exit 1
  }
  while :; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      printf '%s\n' "$$" > "$(lock_file_path pid)"
      printf '%s\n' "$PPID" > "$(lock_file_path ppid)"
      printf '%s\n' "$(ps -o pgid= -p $$ 2>/dev/null | awk 'NF{print $1; exit}')" > "$(lock_file_path pgid)"
      printf '%s\n' "$(ps -o args= -p $$ 2>/dev/null | sed 's/^[[:space:]]*//')" > "$(lock_file_path command)"
      LOCK_HELD=1
      return 0
    fi
    owner_pid="$(lock_read pid)"
    owner_ppid="$(lock_read ppid)"
    owner_pgid="$(lock_read pgid)"
    owner_cmd="$(lock_read command)"
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      owner_stat="$(ps -o stat= -p "$owner_pid" 2>/dev/null | awk 'NF{print $1; exit}')"
      case "$owner_stat" in
        Z*|'') ;;
        *)
          printf 'run_tests: full gate already running (pid=%s ppid=%s pgid=%s)\n' \
            "$owner_pid" "${owner_ppid:-?}" "${owner_pgid:-?}" >&2
          printf 'run_tests: command: %s\n' "${owner_cmd:-unknown}" >&2
          exit 1
          ;;
      esac
    fi
    printf 'run_tests: removing stale full-gate lock for pid %s\n' "${owner_pid:-unknown}" >&2
    rm -rf "$LOCK_DIR" 2>/dev/null || {
      echo "run_tests: cannot remove stale lock directory $LOCK_DIR" >&2
      exit 1
    }
  done
}

start_ts="$(date +%s)"
LOG_DIR="${PIXEL_LOG_DIR:-$ROOT/reports/logs/run_tests_${start_ts}}"
mkdir -p "$LOG_DIR" 2>/dev/null || {
  echo "run_tests: cannot create log directory $LOG_DIR" >&2
  exit 1
}
LOG_FILE="$LOG_DIR/run_tests_${mode}.log"

INTERRUPTED=0
CHILD_PID=''
dur=0
end_ts=0

EMITTED_JSON=0
emit_test_json(){
  local exit_code="$1"
  [ "$AS_JSON" -eq 1 ] || return 0
  [ "$EMITTED_JSON" -eq 0 ] || return 0
  EMITTED_JSON=1

  if [ "$INTERRUPTED" -eq 1 ]; then exit_code=130; fi
  summary_line="$(grep -E '^passed: [0-9]+   failed: [0-9]+   skipped: [0-9]+' "$LOG_FILE" 2>/dev/null | tail -1 || true)"
  passed=0 failed=0 skipped=0
  if [ -n "$summary_line" ]; then
    passed="$(printf '%s\n' "$summary_line" | sed -E 's/^passed: ([0-9]+).*/\1/')"
    failed="$(printf '%s\n' "$summary_line" | sed -E 's/^passed: [0-9]+   failed: ([0-9]+).*/\1/')"
    skipped="$(printf '%s\n' "$summary_line" | sed -E 's/^passed: [0-9]+   failed: [0-9]+   skipped: ([0-9]+).*/\1/')"
  fi
  if [ "$exit_code" -ne 0 ] && [ "$failed" -eq 0 ]; then
    failed=1
  fi
  if [ "$exit_code" -eq 0 ] && [ "$failed" -gt 0 ]; then
    exit_code=1
  fi
  sections_json="[]"
  if [ -n "$SECTIONS" ]; then
    sections_json="[$(printf '%s' "$SECTIONS" | awk -F, '{for(i=1;i<=NF;i++) printf (i>1?", ":"") $i}')]"
  elif [ "$mode" = "full" ]; then
    sections_json="[$(awk -F '\t' 'NF>=7 && $1 !~ /^#/ {print $1}' "$MAP" | sort -nu | paste -sd, - | sed 's/,/, /g')]"
  fi
  printf '{\n'
  printf '  "schema_version": "1",\n'
  printf '  "mode": "%s",\n' "$mode"
  printf '  "full_gate": %s,\n' "$is_full_gate"
  printf '  "branch": "%s",\n' "$(json_escape "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)")"
  printf '  "commit": "%s",\n' "$(json_escape "$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)")"
  printf '  "exit_code": %s,\n' "$exit_code"
  printf '  "duration_seconds": %s,\n' "$dur"
  printf '  "passed": %s,\n' "$passed"
  printf '  "failed": %s,\n' "$failed"
  printf '  "skipped": %s,\n' "$skipped"
  printf '  "sections": %s,\n' "$sections_json"
  printf '  "selected_sections": %s,\n' "$sections_json"
  printf '  "log_file": "%s",\n' "$(json_escape "$LOG_FILE")"
  printf '  "selection_reasons": ['
  first=1
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    [ "$first" -eq 1 ] || printf ', '
    first=0
    printf '"%s"' "$(json_escape "$r")"
  done <<EOF
$REASONS
EOF
  printf ']\n}\n'
}

on_signal(){
  INTERRUPTED=1
  printf 'run_tests: interrupted by signal. Terminating child processes...\n' >&2
  if [ -n "${CHILD_PID:-}" ] && kill -0 "$CHILD_PID" 2>/dev/null; then
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    sleep 0.1
    kill -9 "$CHILD_PID" 2>/dev/null || true
  fi
  pkill -P $$ 2>/dev/null || true
  [ "$end_ts" -eq 0 ] && { end_ts="$(date +%s)"; dur="$((end_ts-start_ts))"; }
  emit_test_json 130
  exit 130
}
trap 'on_signal' INT TERM HUP

tmp=''
cleanup(){
  local orig_rc=$?
  if [ -n "${CHILD_PID:-}" ] && kill -0 "$CHILD_PID" 2>/dev/null; then
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    sleep 0.1
    kill -9 "$CHILD_PID" 2>/dev/null || true
  fi
  pkill -P $$ 2>/dev/null || true
  [ "$end_ts" -eq 0 ] && { end_ts="$(date +%s)"; dur="$((end_ts-start_ts))"; }
  if [ "$orig_rc" -eq 0 ] && [ -f "$LOG_FILE" ] && grep -q -E '^passed: [0-9]+   failed: [1-9][0-9]*' "$LOG_FILE" 2>/dev/null; then
    orig_rc=1
  fi
  if [ "$LIST" -eq 1 ]; then
    [ -n "${tmp:-}" ] && [ -f "$tmp" ] && rm -f "$tmp" || true
    lock_release
    exit "$orig_rc"
  fi
  emit_test_json "$orig_rc"
  [ -n "${tmp:-}" ] && [ -f "$tmp" ] && rm -f "$tmp" || true
  lock_release
  exit "$orig_rc"
}
trap cleanup EXIT

if [ "$mode" = "full" ]; then
  lock_acquire_full_gate
  if [ "${PIXEL_HARNESS_ACTIVE:-0}" = "1" ] && [ "${PIXEL_ALLOW_RECURSIVE_FULL:-0}" != "1" ]; then
    echo "run_tests: recursive full harness invocation detected and blocked (PIXEL_HARNESS_ACTIVE=1)" >&2
    exit 1
  fi
  if [ "$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null || echo false)" = "true" ]; then
    echo "run_tests: shallow clone detected; fetch full history (e.g., git fetch --unshallow) for full-gate execution" >&2
    exit 1
  fi
fi

build_targeted_runner(){
  local selected="$1" include_shared=0 n
  IFS=',' read -r -a arr <<<"$selected"
  for n in "${arr[@]}"; do
    [ "$n" -ge 5 ] && include_shared=1
  done
  selected=",$selected," include_shared="$include_shared" awk '
BEGIN{state="pre"; in_selected=0}
function secnum(line, t){t=line; sub(/^# --- /,"",t); sub(/\..*$/,"",t); return t+0}
function is_sel(s){ return index(ENVIRON["selected"], "," s ",") != 0 }
/^# --- [0-9]+\./{ state="sec"; in_selected=is_sel(secnum($0)) }
/^# --- shared fixtures /{ state="shared" }
/^# --- summary /{ state="summary" }
{
  if(state=="pre"){print; next}
  if(state=="shared"){if(ENVIRON["include_shared"]=="1") print; next}
  if(state=="sec"){if(in_selected) print; next}
  if(state=="summary"){print; next}
}' "$CORE"
}

rc=0
export PIXEL_HARNESS_ACTIVE=1
if [ "$mode" = "full" ]; then
  if [ "$AS_JSON" = 1 ]; then
    bash "$CORE" > "$LOG_FILE" 2>&1 &
    CHILD_PID=$!
    wait "$CHILD_PID" || rc=$?
    CHILD_PID=''
  else
    bash "$CORE" 2>&1 | tee "$LOG_FILE" &
    CHILD_PID=$!
    wait "$CHILD_PID" || rc=$?
    CHILD_PID=''
  fi
else
  tmp="$(mktemp "${TMPDIR:-/tmp}/pixel-targeted-tests.XXXXXX")"
  build_targeted_runner "$SECTIONS" > "$tmp"
  sed -i "s|^ROOT=.*|ROOT=\"$ROOT\"|" "$tmp"
  chmod +x "$tmp"
  if [ "$AS_JSON" = 1 ]; then
    bash "$tmp" > "$LOG_FILE" 2>&1 &
    CHILD_PID=$!
    wait "$CHILD_PID" || rc=$?
    CHILD_PID=''
  else
    bash "$tmp" 2>&1 | tee "$LOG_FILE" &
    CHILD_PID=$!
    wait "$CHILD_PID" || rc=$?
    CHILD_PID=''
  fi
fi
end_ts="$(date +%s)"; dur="$((end_ts-start_ts))"

if [ -n "$REASONS" ] && [ "$AS_JSON" = 0 ]; then
  echo
  echo "selection reasons:"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    printf '  - %s\n' "$r"
  done <<EOF
$REASONS
EOF
fi

exit "$rc"

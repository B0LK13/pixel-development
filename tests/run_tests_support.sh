#!/usr/bin/env bash

append_unique(){
  local val="$1"
  case ",$SECTIONS," in *,"$val",*) ;; *) SECTIONS="${SECTIONS:+$SECTIONS,}$val" ;; esac
}

add_reason(){
  REASONS="${REASONS}${REASONS:+
}$1"
}

classify_changed_path(){
  local path="$1"
  case "$path" in
    .github/*) append_unique 22; append_unique 30; add_reason "changed path: $path -> workflow/ci checks" ;;
    README.md|CLAUDE.md) append_unique 21; append_unique 28; append_unique 29; append_unique 31; add_reason "changed path: $path -> repo docs checks" ;;
    .gitignore) append_unique 0; add_reason "changed path: $path -> repository metadata baseline" ;;
    harness/*) append_unique 31; append_unique 32; append_unique 22; add_reason "changed path: $path -> harness checks" ;;
    .codebase-memory/*) add_reason "changed path: $path -> local session cache ignored" ;;
    tests/*) append_unique 1; append_unique 2; append_unique 8; append_unique 22; append_unique 31; append_unique 32; add_reason "changed path: $path -> harness checks" ;;
    scripts/check-*|AGENTS.md|.agent/*|schemas/*) append_unique 31; append_unique 32; append_unique 22; add_reason "changed path: $path -> agent-os checks" ;;
    scripts/update-bootstrap-checksums.sh|config/bootstrap-checksums.txt) append_unique 16; append_unique 20; add_reason "changed path: $path -> checksum checks" ;;
    pixel-bootstrap.sh|pixel-dev-setup.sh|pixel-apps-setup.sh) append_unique 16; append_unique 17; append_unique 18; add_reason "changed path: $path -> bootstrap checks" ;;
    pixel-autodev.sh) append_unique 5; append_unique 6; append_unique 10; append_unique 11; append_unique 13; append_unique 15; add_reason "changed path: $path -> autodev checks" ;;
    scripts/build-release-candidate.sh) append_unique 24; append_unique 27; add_reason "changed path: $path -> release builder checks" ;;
    scripts/verify-release-bundle.sh) append_unique 25; append_unique 26; append_unique 28; add_reason "changed path: $path -> release verifier checks" ;;
    scripts/*) append_unique 22; append_unique 31; append_unique 32; add_reason "changed path: $path -> scripts checks" ;;
    docs/*|reports/*|evidence/*) append_unique 21; append_unique 28; append_unique 29; append_unique 31; add_reason "changed path: $path -> docs/evidence checks" ;;
    *)
      add_reason "conservative fallback: unknown changed path '$path' selects full gate"
      return 1
      ;;
  esac
}

run_harness_core(){
  local runner="$1" log_file="$2" as_json="$3" rc=0
  if [ "$as_json" -eq 1 ]; then
    bash "$runner" > "$log_file" 2>&1 &
  else
    bash "$runner" 2>&1 | tee "$log_file" &
  fi
  CHILD_PID=$!
  wait "$CHILD_PID" || rc=$?
  CHILD_PID=''
  return "$rc"
}

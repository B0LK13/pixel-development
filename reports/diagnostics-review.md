# Session 8 — Diagnostics & Observability Review

Scope: bootstrap, setup, policy checks, test harness, release build, bundle
verification, signature verification, reproducibility, CI parity, clean-clone
execution. Base: HEAD `e4304d5` (working tree clean apart from
`evidence/session-8/`). Method: full read of all 9 scripts + harness +
workflow, plus cheap live probes of failure paths (invalid inputs only —
they exit 2 before side effects by contract). No files modified; nothing
committed; full suite left to the background run.

## Live-verified failure behavior (probes run this session)

| probe | rc | output |
|-------|----|--------|
| `pixel-apps-setup.sh --ssh-port=abc` (temp HOME) | 2 | stderr only: `pixel-apps-setup: --ssh-port must be an integer between 1 and 65535 (got 'abc')`; **no log file created** — validation truly precedes side effects |
| `build-release-candidate.sh --version=bad` | 2 | `build-release-candidate: malformed version: bad (want strict SemVer X.Y.Z, e.g. 1.0.0)` — names input, constraint, example |
| `pixel-autodev.sh --budget=0` | 2 | `pixel-autodev: --budget must be a positive number (e.g. 2.00) (got '0')` |
| `pixel-dev-setup.sh --bogus`, stderr discarded | 2 | `Unknown flag: --bogus (try --help)` — printed on **stdout**, unprefixed (see D5) |
| `verify-release-bundle.sh` (no args) | 2 | full usage line on stderr |
| ERR-trap semantics (dev-setup:57 / apps-setup:65) | — | trap **does** fire without `set -e`, and `$LINENO`/`$?` report the failing command correctly (probe: `LINENO=3 rc=1`) |

## Findings

### Improve this session

**D1 — bootstrap: local-copy install failure is silent; run can exit 0 with a
broken install.** `pixel-bootstrap.sh:96-97`: `cp "$found" "$DEST/$s" && ok
"$s (copied from ${found%/*})"` has no `else` — a failed copy prints nothing,
shortcuts get created pointing at a missing script, and the run ends `✔
One-tap layer ready.` (exit 0). Same class at `:109` (`mv …; ok "…sha256
verified)"` — `;` not `&&`, so `ok` prints even if the move failed) and `:118`
(`chmod +x … || true` masks a non-executable install that only fails at
widget-tap time). Proposed change:
```bash
cp "$found" "$DEST/$s" && ok "$s (copied from ${found%/*})" \
  || die "could not copy $found to $DEST/$s — copy it there manually and re-run"
mv "$DLTMP/$s" "$DEST/$s" || die "could not install $s to $DEST — check free space"
chmod +x "$DEST/$s" 2>/dev/null || warn "could not chmod +x $DEST/$s — run: chmod +x '$DEST/$s'"
```
Regression risk: **none found.** The harness never exercises the local-copy
branch or `--open-store` (grep-verified: no assertion matches
`copied|cached|open-store` in `tests/run_tests.sh`); §17 download-path
assertions are untouched, and the §16 static pin counts `curl -fsSL -o`
lines — this edit adds none.

**D2 — bootstrap: false success when no URL opener exists.**
`pixel-bootstrap.sh:194-198`: if neither `termux-open-url` nor `am` exists,
nothing opens but `ok "Opened Termux:Widget on F-Droid…"` prints anyway.
Proposed: add `else warn "no URL opener — install com.termux.widget from
F-Droid manually"` before the `ok`, and move the `ok` into the success
branches. Risk: none (zero harness coverage of this path, per D1 grep).

**D3 — harness: no failed-test recap, and the clean-clone smoke failure is
detail-free.** `tests/run_tests.sh:30` (`t_fail`) prints name + ≤20 lines of
detail inline, but the summary (`:1542-1544`) is counts only; with ~300
assertions an operator scrolls/greps back for `FAIL`. Worse, §8 runs the
nested suite with output discarded (`:318`) and on failure reports only
`clean-clone smoke: suite must pass from a fresh clone` (`:321`) — which
nested test failed is invisible. Proposed (additive): accumulate
`FAILED_TESTS+=("$1")` in `t_fail` and, before the summary, print
`printf '  - %s\n' "${FAILED_TESTS[@]}"` when non-empty; in §8 capture the
nested run to a file and pass `$(tail -20 …)` as the `t_fail` detail.
Risk: **none.** Nothing greps harness stdout — ci-local (gate 5), the workflow
step, and the §8 nested run consume **rc only**; `t_fail`'s existing console
format is unchanged.

**D4 — apps-setup `die` does not log FATAL; dev-setup's does.**
`pixel-apps-setup.sh:63` is bare `printf … >&2; exit 1`, while
`pixel-dev-setup.sh:54` does `_log "FATAL $*"`. A preflight death in
apps-setup leaves a log ending at `STEP 1. Preflight` with no cause — the one
artifact a remote operator would send back is incomplete. Proposed: add
`_log "FATAL $*"` to the apps-setup `die`. Risk: none — harness asserts the
log file's *absence* on usage errors (§9a) and never reads its content.

### Deferred (real, but low value / contract-pinned)

**D5 — unknown-flag line is stdout + unprefixed in the four entry scripts**
(`pixel-bootstrap.sh:29`, `pixel-dev-setup.sh:36`, `pixel-apps-setup.sh:36`,
`pixel-autodev.sh:53`), while every `scripts/` tool emits
`tool-name: unknown flag: …` on **stderr** — inconsistent with the repo's own
prefixed stderr validation messages (verified live above).
`docs/CLI_CONTRACT.md:33-34` documents the stdout choice as "historical";
harness §3/§7/§12 pin **rc only**, so the fix is harness-safe but needs a
contract-doc edit. Value is marginal (interactive use); defer.

**D6 — thin detail in some verifier metadata failures.**
`scripts/verify-release-bundle.sh` fails fast at the first fault (correct for
a trust-ordered verifier), but several messages omit the got-value: `:99`
`failed-metadata "wrong project"`, `:105` `malformed created_at`, and any
`jget`-empty field yields e.g. `unsupported schema version: ` (trailing
blank). Verdict + message still identify file and check, so this is polish;
harness §25 asserts **verdict words only** (`vassert`,
`tests/run_tests.sh:1243-1249`), so enriching details is harness-safe.

**D7 — bare `warn`s without cause or remediation.**
`pixel-dev-setup.sh:138` `warn "ssh-keygen failed"`;
`pixel-apps-setup.sh:274` `warn "Could not write checklist file"`;
`pixel-apps-setup.sh:85` `warn "pkg failed: $p (skipped)"` — its dev-setup
twin (`:98`) adds the useful hint `(skipped — name may differ in your repo)`.
None are harness-pinned; fold into a future cosmetic pass.

**D8 — autodev summary conflates SKIP/NO-OP with FAILED.**
`pixel-autodev.sh:293-296,345` `return 1` for dir-missing / not-git /
dirty-tree / no-op, landing in the same `open/failed: N` count (`:378`) as
agent/test failures. The label is literally accurate and each case emits a
distinct stderr `warn` + `SKIP:`/`RESULT:` log line, so a split counter is
cosmetic. Defer.

**D9 — exit 0 despite component failures in dev/apps-setup.** The resilient
installer prints `FAILED` items in the summary (`pixel-dev-setup.sh:295-297`,
`pixel-apps-setup.sh:297`) and exits 0. Already adjudicated:
`docs/AUTONOMOUS_AUDIT.md` F12 (intentional best-effort phone installer).
Noted so exit-0 is never mistaken for "all green" in automation.

**D10 — `SOURCE_DATE_EPOCH` malformed → exit 1, not 2**
(`build-release-candidate.sh:53-56`). Env input, not a flag, so class-1 is
defensible under the header's taxonomy; §27c pins rc=1; the message is
already excellent (`SOURCE_DATE_EPOCH must be unix seconds: notanumber`).

**D11 — harness section headers are comments, not output.** The 29
`# --- N. ---` markers never print, so CI output is a flat ~300-line
`ok/FAIL/skip` stream. The D3 recap covers the failure case; echoing banners
touches ~29 sites for marginal gain. Defer.

### No action — already correct (verified, not assumed)

- **Bootstrap fail-closed die set is exemplary** — every message names the
  component, cause, and remediation or candidate causes (`pixel-bootstrap.sh`
  `:103` no pinned checksum → "refusing to fetch unverified content (see
  config/bootstrap-checksums.txt)"; `:105` no SHA-256 tool → "refusing to
  install it"; `:111` mismatch → "expected $exp, got ${got:-<unreadable>};
  NOT installed (source may be tampered, or the pin is stale)"; `:115`
  download failure → "Put it next to this script, or fix --repo-base.").
- **Validation-before-side-effects ordering holds on every checked path**:
  apps-setup validates `:40-51` before the log truncation `:67` (proven live:
  no log file on bad port); autodev validates `:61-85` before any `.autodev`
  state (harness §10g); builder usage-checks `:44-56` before temp dir/gates
  (§24i proves no output on bad version); verifier usage-checks `:40-43`
  before touching the bundle (§28g proves side-effect-free);
  `update-bootstrap-checksums.sh:94-96` refuses to rewrite a manifest with
  errors, and §20k proves a failed `--write` leaves it byte-identical.
- **Exit-code classes match `docs/CLI_CONTRACT.md`** on every path probed or
  read: 2 for unknown flags / invalid values / conflicting modes, 1 for
  preflight/runtime/gate failures, 0 for success/`--help`. No `exit $?`
  masking anywhere — `ci-local.sh:26` preserves the failing gate's status via
  `fail "…" $?` → `exit "$2"` (pinned by §22). The harness's own guard
  (`tests/run_tests.sh:1544` `[ "$FAIL" -eq 0 ]`) makes CI red on red.
- **Timeout expiry is distinguishable** (audit F3, fixed): rc=124 gets its
  own warning + `RESULT: FAILED (timeout after Ns)` log line
  (`pixel-autodev.sh:331-334`); §6g proves both backends.
- **Reproducibility failures are diagnosable**: distinct messages for
  non-numeric epoch, `date -d` incapability, and `touch -d` incapability
  (`build-release-candidate.sh:54,147,252`); CI surfaces `diff -r` output
  directly (workflow `:55-58`).
- **Log files**: `pixel-dev-setup.log`/`pixel-apps-setup.log` carry
  timestamped STEP/INFO/OK/WARN/FATAL lines plus full `pkg`/`apt` output —
  genuinely useful. Sensitive-data check: no tokens, keys, or emails are
  logged (interactive git identity is never `_log`ed; the summary's API-key
  instructions are stdout-only). `.autodev/run-*.md` truncates agent output
  to 600 chars (`pixel-autodev.sh:328`), is workspace-local, and `.autodev/`
  is gitignored. Risk: low.

## Q: does structured/machine-readable output have a real consumer here?

**Yes — exactly one, and it already exists.** The verifier's verdict protocol
(`verify-release-bundle.sh:49,237,240`: `verdict: failed-layout |
failed-metadata | failed-signature | failed-checksum | failed-policy |
verified-integrity-only | verified-signed`, stdout; detail on stderr) is
consumed by two machines: harness `vassert` (~20 sites) and the release job
(`test.yml:54,73`, `grep -q "verdict: …"`). That meets the mandate's bar
without adding anything. For the four entry scripts the only consumer is a
human on a phone — no log shipper, wrapper, or CI step parses their output.
**Do not add JSON/structured modes to them.**

## Q: stable error identifier scheme?

**Not proposed — de facto stable identifiers already exist, and a formal code
scheme would be pure churn.** Already greppable today: (1) the `verdict:`
protocol; (2) tool-name prefixes on every `scripts/` message and on
validation errors (`pixel-autodev:`, `pixel-apps-setup:`); (3)
`STALE:`/`EMBEDDED STALE:` in the checksum tool; (4) `RESULT:`/`SKIP:` in
`.autodev` run logs; (5) policy-line tokens (`timeout=Ns`, `budget/task=$X`)
pinned by §6b/§10e. Cost side: the harness holds ~40 `case "$out" in *"…"*`
and ~60 `grep -q` text assertions (`"checksum mismatch for
pixel-dev-setup.sh"`, `"no pinned checksum for pixel-apps-setup.sh"`,
`"Run inside Termux"`, `"expected 1 line"`, …); every message edit already
requires a paired assertion edit — the documented discipline, and it works.
`E1xxx` codes would touch all ~100 sites for zero new capability. Safe-edit
rule going forward: verdict words, exit codes, and the pinned substrings are
frozen; surrounding detail text (D6, D7) may be enriched where only the
verdict/rc is asserted.

## Negative results (excellent as-is)

Verifier failure-mode coverage is the standout: §25/§26 inject ~30 faults
(layout, schema, binding, signature, checksum, mode drift, traversal, wrong
file signed, injection) and each verdict maps to a distinct, actionable
operator response — the trust-order comment (`verify-release-bundle.sh:13-22`)
doubles as a diagnostic flowchart. `verify-bootstrap-signature.sh` names the
missing dependency with its install command (`:51`). The checksum tool's
itemized report (`ok`/`✖` per artifact + manifest/embedded lockstep) is a
model failure listing. `PIXEL_TEST_TIMINGS=1` has a demonstrated consumer
(`evidence/session-7/test-timings.txt`). CI steps are individually named in
both jobs, so the failing gate is obvious from the run page without log
spelunking.

## Caveats

- The working tree drifted under audit (a concurrent session-8 edit added ~8
  lines in §24 mid-read, since reverted; tree verified clean vs HEAD at write
  time). Line numbers cite HEAD `e4304d5` content.
- D1–D4 are proposals only — this review modified nothing; the background
  suite was left undisturbed.

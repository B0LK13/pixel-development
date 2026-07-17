# Horizon 0.2 evidence directory

Bounded, non-sensitive evidence for the Horizon 0.2 release-readiness
workstream. Raw logs stay on the operating host (`/tmp/h02/`) per the
`evidence/README.md` bounded-output policy; only summaries, transcripts
with secrets elided, and result records are committed here.

Subdirectories are created by each workstream:

- `baseline/` — starting-state and baseline-gate record (Agent A)
- `reproducibility/` — build/rebuild comparison (Agent B)
- `signing-rehearsal/` — throwaway-identity signing proof (Agent C)
- `adversarial/` — fail-closed scenario records (Agent D)
- `provenance/` — SBOM/provenance readiness artifacts (Agent E)
- `recovery/` — rollback/DR rehearsal records (Agent F)
- `security-audit/` — audit scan results (Agent G)
- `final-rehearsal/` — Phase 11 end-to-end rehearsal (coordinator)

Hard rules: no private key material, no passphrases, no tokens, no full
environment dumps, no unnecessary absolute user paths. Evidence is
append-only; corrections land as new files.

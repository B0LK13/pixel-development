REMEDIATE_STREAM_JSON_SENTINEL_PARSER

Approval ID: REMEDIATE_STREAM_JSON_SENTINEL_PARSER
Created: 2026-07-17T09:15:00Z
Ledger sequence: 1039
Originating exhausted approval: approval-47ba36c0bbea42e6b1c27bc0718170c7
Failed session preserved: 532ea493-2ad3-4fa7-aa5f-85fd3aa2e877
Evidence package (preserved, do not edit): evidence/smoke-attempt-2/

Authorized scope (minimal, read+write for remediation only):
- adapters/Invoke-CursorAgent.ps1
- tools/Test-InvokeCursorAgent.ps1
- reports/SMOKE-CURSOR-WINDOWS.md

Explicit prohibitions (NOT authorized):
- any real Cursor launch or Mission Control execution
- ledger/evidence modification or deletion of historical evidence
- approval-consumption changes or reuse of approval-47ba36c0...
- schema redesign outside this narrow parser fix
- unrelated adapter or infrastructure edits

Remediation objective (high-level)
- Replace naive substring sentinel matching in stream-json mode with envelope-aware parsing.
- Implement defensive property access and deterministic fail-closed behavior that always writes dispatch-result.json.
- Add deterministic regression fixtures (use redacted lines from evidence where safe).

Required parser behavior (must be implemented and tested):
1) For stream-json output mode:
   - Parse each incoming line as JSON; on parse error, emit STREAM_JSON_PARSE_ERROR and continue robustly.
   - Inspect envelope "type" and accept only eligible envelope types for protocol events; ignore user/system echoes.
   - Extract nested event payloads explicitly; validate presence of 'event' property before access.
   - Recognize acknowledgment: {"event":"CURSOR_TASK_ACKNOWLEDGED"}
   - Recognize completion: {"event":"CURSOR_TASK_COMPLETED","status":"COMPLETE"}
   - Do not treat sentinel substrings in arbitrary text fields as protocol events.
   - On malformed envelope or unsupported envelope type, produce deterministic failure result (MALFORMED_PROTOCOL_EVENT or UNSUPPORTED_STREAM_ENVELOPE) and write dispatch-result.json.

2) For text mode (existing behavior):
   - Keep current bounded-text sentinel detection (fail-closed remains acceptable).
   - Ensure mode override flag (-OutputFormat text) still functions.

Defensive coding requirements:
- Check property existence before access (PowerShell: $obj.PSObject.Properties.Name -contains 'event').
- Catch JSON parse exceptions; do not allow unhandled exceptions to bubble.
- Any error path must result in writing a valid dispatch-result.json explaining failure.

Regression test matrix (deterministic fixtures required):
- echoed user prompt with sentinel strings
- system envelope containing sentinel strings
- assistant text containing sentinel strings but no event object
- valid ack event
- valid completion event
- ack before completion and completion before ack
- duplicates (ack/ack, completion/completion)
- malformed JSON line
- valid JSON w/o 'event'
- nested event in expected location
- unsupported envelope type
- literal completion status "COMPLETE"
- reproduction of the original crash case
- adapter always writes dispatch-result.json on protocol failure
- text-mode passthrough test and explicit output-format override

Review & approval process:
- Implementer creates a focused branch and a draft PR limited to the three authorized files and test fixtures.
- Do NOT run any real Cursor adapter launch in CI for this PR; tests should be unit/fixture-based and local-only.
- Assign an independent read-only reviewer (not the implementer). Reviewer must validate scope, run the regression fixtures, and confirm behavior.
- On reviewer signoff, create a separate PENDING approval for a single real Cursor smoke attempt (Task ID ADOS-SMOKE-CURSOR-WINDOWS-001). Do not combine remediation and execution approvals.

Preservation note:
- The failed attempt is authoritative and must not be altered. Any debug lines copied into fixtures must be redacted for secrets and recorded in the fixture metadata.

Contact/Owners: implementer TBD, governance contact: security@org.example

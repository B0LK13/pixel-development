# Agent OS Harness — Product Vision

## Vision & Mission

**Vision:** Make repository automation trustworthy enough that a human or AI agent can answer, for any change, what changed, why it was validated, what executed, and whether it is safe to promote.

**Mission:** Turn a script-first repository into a deterministic engineering control plane with explicit policy, reproducible validation, signed evidence, and safe promotion boundaries.

**Why this matters:** Most automation is fast but opaque. This project is optimized for truth first: exact Git objects, clean-clone parity, stable exit codes, and evidence that can be replayed later.

**Long-term design:** The product is evolving from a local validation harness into a layered engineering operating system with core domain services, runtime isolation, change intelligence, evidence provenance, governance, and eventually distributed execution. The near-term work must keep that shape in mind so every new capability fits the same trust model instead of becoming a one-off script.

**Core values**

- **Trust before speed** — if the result cannot be reproduced, it is not good enough.
- **Explicit boundaries** — every runtime, fallback, and promotion step must state its limits.
- **Determinism over convenience** — ambiguous state should widen validation, not hide risk.
- **Evidence over assertion** — logs, signatures, and manifests beat confidence.
- **Graceful degradation** — unsupported environments should fail clearly, never silently.

## User Research

**Primary persona:** A maintainer or platform engineer responsible for a trust-sensitive repository. They care about release integrity, contract drift, and safe automation, and they need a system that explains itself under pressure.

**Secondary personas**

- AI coding agents that need bounded execution, explicit budgets, and approval rules.
- CI maintainers who need stable, low-noise validation gates.
- Security reviewers who need provenance, evidence, and exact promotion records.

**Jobs to be done**

- Decide which validation should run for a change.
- Prove the result came from the intended commit and environment.
- Detect drift between scripts, docs, and policy.
- Promote only what has been validated and signed.
- Recover safely from interrupted or partial runs.

**Pain points**

- Validation is often either too broad to be efficient or too narrow to be trusted.
- Fallbacks hide problems instead of explaining them.
- Evidence is scattered across logs, CI output, and commit history.
- Documentation and live behavior drift apart.
- Recursive or nested execution can corrupt the meaning of a run.

**Current alternatives**

- Ad hoc shell scripts and manual checks.
- Generic CI pipelines with opaque jobs.
- Release checklists in docs or issue comments.
- Custom one-off automation that works until it drifts.

**Key assumptions to validate**

- Maintainers will value explainability even when it adds implementation cost.
- Clean-clone validation is a strong trust signal for this class of repo.
- Evidence bundles are useful when they are easy to inspect and hard to forge.
- A command-first interface is more credible than a dashboard-first one for this workflow.

**User journey map**

1. A maintainer makes or receives a change.
2. The harness classifies the change and selects a validation plan.
3. The plan runs in a bounded runtime with explicit environment normalization.
4. Evidence is recorded with exact source identity and policy context.
5. The maintainer reviews the result and either promotes, retries, or blocks.

## Product Strategy

**Product principles**

- Exact objects, not vague branch names.
- Validation plans should be explainable before execution.
- Unsupported environments should be named and classified.
- Fallbacks must be explicit and policy-approved.
- Evidence must be durable and independently readable.

**Market differentiation**

Generic CI systems optimize for job completion. Agent OS Harness optimizes for trust, reproducibility, and promotion safety. The differentiator is not the number of checks; it is the clarity of why a check ran and whether the output can be defended later.

**Architecture strategy**

The long-term architecture should stay layered and contract-driven: platform foundation, core domain services, repository state, runtime and isolation, policy control, change intelligence, validation graph, distributed execution, observability, evidence, governance, and user interfaces. Each layer should expose a stable interface to the next so the system can grow without collapsing into tangled shell logic.

**Magic moment design**

The product should make it obvious, in a single run, why a change is safe or unsafe. The magic moment is when a maintainer sees the selected validation plan, the exact commit, the environment fingerprint, and the evidence bundle, and does not need to ask follow-up questions.

**MVP definition**

The MVP should be buildable in 4–8 weeks and include:

- change-aware validation selection;
- contract hardening for command, exit-code, and output behavior;
- clean-clone and source/clone parity checks;
- immutable evidence capture for each run;
- a deterministic promotion decision path.

**Explicit out of scope for MVP**

- distributed execution;
- predictive optimization;
- machine-learning-based selection;
- rich web dashboards;
- full multi-tenant agent governance.

**Feature priority**

- **Must have:** deterministic validation, evidence capture, clean-clone parity, exact-object promotion, clear failures.
- **Should have:** diagnostic commands, machine-readable output, policy versioning, interruption recovery.
- **Could have:** caching, advisory risk scoring, richer reporting.
- **Won’t have yet:** autonomous optimization loops, distributed worker fleet, broad UI surfaces.

**Core user flows**

1. Change lands or is proposed.
2. Harness selects the minimum safe validation set.
3. Validation runs in an approved runtime.
4. Results and evidence are written to immutable artifacts.
5. Promotion is approved or blocked based on policy.

**Success metrics**

- Exact source-to-clone parity remains stable.
- Validation decisions are explainable without tribal knowledge.
- Contract drift is detected before it becomes a release risk.
- Unsupported environments fail clearly and consistently.
- Evidence bundles can be audited after the fact without rerunning the system.

**Risks**

- Overfitting the architecture to edge cases before the core contract is stable.
- Accidentally weakening sandboxing in the name of portability.
- Adding too many fallback paths and losing trust clarity.
- Expanding scope into dashboards or orchestration before the command contract is solid.

**Long-term direction**

This is not just a better test runner. Over time it should become the repository’s control plane for trusted automation: selection, execution, evidence, promotion, recovery, and eventually multi-worker scheduling. The product should keep the command-line surface authoritative even if richer interfaces appear later.

## Brand Strategy

**Positioning statement**

Agent OS Harness is the trusted engineering control plane for repositories where evidence, determinism, and safe promotion matter more than raw throughput.

**Brand personality**

- Rigorous
- Calm
- Exacting
- Helpful without being chatty

**Voice & tone guide**

- **Do:** name the reason a check ran, the runtime used, and the exact risk class.
- **Do:** say when something is unsupported and what that means.
- **Do:** prefer short, evidence-backed statements.
- **Don’t:** promise safety without showing provenance.
- **Don’t:** hide fallback behavior behind generic success language.
- **Don’t:** use vague “looks good” language where exact evidence exists.

**Examples**

- **Good:** “Validation ran because release tooling changed. Evidence bundle: `evidence/SIGNING-EVIDENCE.json`.”
- **Good:** “Bubblewrap is unavailable in this environment, so the runtime is classified as unsupported.”
- **Bad:** “Everything passed, so we’re fine.”
- **Bad:** “It probably worked, but the logs are noisy.”

**Messaging framework**

- **For maintainers:** “Know exactly what changed and why it was checked.”
- **For AI agents:** “Operate within bounded scope, with explicit approval and evidence.”
- **For security reviewers:** “Audit exact commits, exact policies, and exact artifacts.”

**Elevator pitches**

- **5 seconds:** “It makes repository automation trustworthy.”
- **30 seconds:** “Agent OS Harness selects the right validations, runs them in a controlled runtime, records immutable evidence, and only promotes exact objects that satisfy policy.”
- **2 minutes:** “Most CI systems tell you whether a job passed. This system tells you what changed, why it was validated, what actually executed, and whether the result is safe to promote. It is built for repositories where clean-clone parity, signed provenance, and explicit fallback behavior are part of the product, not an afterthought.”

**Competitive differentiation narrative**

The difference is not just more automation. It is a stronger trust model: exact object promotion, explicit runtime classification, evidence bundles, and a contract-first approach that makes drift visible before it becomes a release risk.

> Visual identity, tokens, and component styling live in `docs/design.md`. If it does not exist yet, run the Design System skill with image references before implementation work starts.

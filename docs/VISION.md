# Vision — Agent OS Harness

> Captured by the Product Planner skill. This file is the source of truth for
> generating product-vision.md, prd.md, and product-roadmap.md. Edit it directly
> and re-run the Product Planner to regenerate downstream documents.

**Created:** 2026-07-15T15:09:53Z
**Updated:** 2026-07-15T15:09:53Z

## Founder

- **Name:** B0LK13
- **Expertise:** Repository engineering, validation automation, and trust-sensitive developer tooling
- **Background:** I have been building a script-first harness to make AI-assisted development deterministic, reproducible, and safe to promote. The work comes from living through the failure modes first: ambiguous execution, weak evidence, stale contracts, and tooling drift.

## Purpose

- **Who you help:** Developers, maintainers, and AI coding agents working in trust-sensitive repositories and release pipelines
- **Problem you solve:** Engineering workflows are usually fragmented across scripts, CI, logs, and manual judgment, so it is hard to know what changed, why a check ran, what executed, and whether the result is safe
- **Desired transformation:** Every change is evaluated with deterministic validation, signed evidence, and a clear promotion decision that can be reproduced later
- **Why you:** I am already operating the system, I know the failure modes, and I care about trust boundaries, not just speed
- **Long-term design:** The near-term goal is to harden the current harness, but the long-term goal is to evolve it into a layered engineering control plane with explicit runtime isolation, change intelligence, evidence provenance, and governance boundaries

## Product

- **Name:** Agent OS Harness
- **One-liner:** Agent OS Harness turns repository validation into a trusted engineering control plane with deterministic execution, evidence, and promotion rules
- **How it works:** A change is classified, mapped to required validations, executed inside an approved runtime, recorded as immutable evidence, and then promoted or blocked based on policy and provenance
- **Key capabilities:**
  - Change-aware validation selection
  - Clean-clone and source/clone parity checks
  - Immutable evidence and signed provenance
  - Runtime isolation and fallback control
  - Agent and promotion governance
- **Platform:** cross-platform
- **Market differentiation:** Unlike generic CI or script collections, this system is designed around trust: exact Git objects, explicit policy, deterministic path resolution, evidence-backed promotion, and safe agent autonomy
- **Long-term architecture:** The system should grow into a layered platform rather than a pile of scripts: platform foundation, core services, repository state, runtime isolation, policy, change intelligence, validation orchestration, evidence, governance, and interfaces
- **Magic moment:** A maintainer can inspect a run and immediately answer what changed, why the validation set was selected, exactly what executed, and whether the result is safe to promote

## Audience

- **Primary user:** A maintainer or platform engineer responsible for a trust-sensitive repository, usually one that combines automation, release integrity, and AI-assisted development
- **Secondary users:**
  - AI coding agents that need bounded permissions and reproducible execution
  - CI maintainers who need stable gates and contract checks
  - Security reviewers who need provenance, auditability, and exact promotion records
- **Current alternatives:** Ad hoc shell scripts, generic CI pipelines, manual release checklists, and scattered logs in GitHub Actions, terminals, and notes
- **Frustrations:** The current tools hide intent, allow drift between docs and behavior, make fallback paths hard to trust, and produce evidence that is difficult to audit later

## Business

- **Revenue model:** free
- **90-day goal:** Stabilize the harness contract, keep source and clean-clone validation in lockstep, and make the run/evidence model understandable to contributors
- **6-month vision:** A modular, observable, policy-driven harness that can explain and reproduce its own decisions across local, CI, and clean-clone execution
- **Constraints:** Limited time, trust-sensitive behavior, no silent security regressions, and a need to preserve current repository contracts while evolving them
- **Go-to-market:** Dogfood in this repository first, document the contract clearly, and expand through adjacent automation and agent-workflow repos once the control plane is proven

## Brand Voice

- **Personality:** Rigorous, calm, and exacting — the kind of system that explains itself clearly and never bluffs
- **Tone of voice:** Direct, technical, and evidence-first. Prefer precise statements like “validation selected because changed files touched release tooling” over vague reassurance; when something is unsupported, say so plainly and name the fallback or failure mode

> Visual identity (mood, anti-patterns, design tokens) is deliberately not
> captured here — it lives in docs/design.md, generated by the Design System
> skill from image references.

## Tech Stack

- **App type:** cross-platform
- **Frontend:** Shell CLI and Markdown reports — this is a command-first control plane, so the primary interface is scripts, logs, and machine-readable results
- **Backend:** Bash and Node.js orchestration — the repo is script-first today, and any heavier service layer should be added only when it clearly improves trust or maintainability
- **Database:** None — state lives in Git, evidence artifacts, and generated reports rather than an application database
- **Auth:** Git identity and signing keys — the system is rooted in repository permissions, commit signatures, and promotion policy rather than end-user sign-in
- **Payments:** None — this is a trust/control-plane product, not a monetized customer app
- **Analytics:** None — structured logs, evidence bundles, and run metadata are the operational analytics
- **Email:** None — notifications should stay inside repository and CLI workflows unless a future workflow explicitly needs email
- **Error tracking:** None — failures are captured in logs, exit codes, and evidence artifacts

## Tooling

- **Coding agent:** GitHub Copilot

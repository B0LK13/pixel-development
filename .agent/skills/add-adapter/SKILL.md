# Skill: add-adapter

## Purpose

Add a new adapter integration without making it the source of truth.

## Steps

1. Define adapter boundary in docs.
2. Keep repository contracts/manifests authoritative.
3. Add checks/tests for non-regression.
4. Validate with full gate.

## Prohibited shortcuts

- moving policy truth into external adapters
- weakening hermetic test behavior


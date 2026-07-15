# Terminology

| term | meaning |
|---|---|
| run | one validation or promotion execution |
| plan | the selected checks and their order |
| evidence | the logs, reports, bundles, and metadata that explain what ran |
| promotion | moving validated work toward `main` under policy |
| gate | a deterministic validation step with a known ID |
| registry | the live list of gates, routes, or skills |
| fallback | a conservative widening of validation when the baseline is unclear |
| baseline | the validated source commit and its recorded state |

## Usage notes

- "run" is the broadest term; it includes validation and promotion flows.
- "plan" is selected before execution and should be deterministic for the same
  commit and policy.
- "evidence" includes both human-readable reports and machine-readable output.
- "promotion" is operator-controlled in this repository.

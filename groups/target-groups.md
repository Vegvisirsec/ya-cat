# Target Groups

## Standard names

- `CA-BreakGlass-Exclude`
- `CA-Tier-Baseline`
- `CA-Tier-P1-Managed`
- `CA-Tier-Frontline`
- `CA-Tier-E5`
- `CA-Admins`
- `CA-Pilot`

## Notes

This file tracks the canonical group naming model used by policy targeting.

## Policy Exclusion Groups

Policy-specific exclusion groups are defined in `groups/policy-exclusion-groups.json`.

Principles:
- one exclusion group per policy where exceptions are expected
- avoid broad, reusable \"exclude from everything\" groups
- keep exceptions temporary and review membership regularly

## Targeting hygiene

Preferred operating model:
- each covered workforce identity belongs to an intended toolkit targeting group
- `CA-BL-015` can be used in report-only to detect identities that are outside the targeting model
- do not use the admission exception group as a permanent placement bucket

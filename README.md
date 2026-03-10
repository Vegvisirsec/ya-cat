# ya-cat: Yet Another Conditional Access Toolkit

```text
 /\_/\\
( o.o )  ya-cat
 > ^ <
```

Portable Conditional Access policy definitions, deployment helpers, export utilities, and reviewer guidance for Microsoft 365 environments.

## Design approach

This toolkit loosely follows a persona-based Conditional Access design approach, but it is not a pure persona model. The policy tiers reflect both user shape and license capability: baseline and managed controls can be thought of as sub-personas of the "typical user", while frontline and E5 extend that model for materially different operating patterns or higher-capability license estates.

## What this repo includes

- policy JSON for baseline, managed, frontline, and E5 tiers
- PowerShell scripts for deploy, evaluate, export, and context-package generation
- target-group and exclusion-group reference material
- per-policy reviewer instructions for structured assessment work
- local evaluation inputs for offline LLM or human review

## Safety defaults

- new toolkit-managed policies deploy as `reportOnly`
- break-glass exclusions are delivered through group membership, but must be manually maintained in the target tenant
- deployment should be validated in a non-production tenant first!

## Intentional placeholders

Two policy templates intentionally retain tenant-specific deployment placeholders and will be skipped until manually edited to replace the placeholders with correct values

- `policies/baseline/CA-BL-009.block-non-business-countries.json` requires `{{BUSINESS_COUNTRIES_LOCATION_ID}}`
- `policies/baseline/CA-BL-010.require-terms-of-use-for-guests.json` requires `{{TERMS_OF_USE_ID}}`

## Core paths

- `policies/` policy definitions and schema
- `groups/` target group and exclusion group model
- `src/deploy/` deployment entry points
- `src/evaluate/` export and context-package utilities
- `src/graph/` supporting Graph utilities
- `docs/` architecture, catalog, and reviewer guidance
- `examples/` sample config and data files

## Main scripts

Deploy or evaluate toolkit policies:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src/deploy/Deploy-CAPolicies.ps1 -Mode Evaluate -EnvFile .env.local -ReportFormat Csv
```

Export tenant Conditional Access policies:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src/evaluate/Export-CAPolicies.ps1 -EnvFile .env.local
```

Export a local evaluation context package:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src/evaluate/Export-CAContextPackage.ps1 -EnvFile .env.local -DaysPast 30
```

## Documentation 

- `docs/architecture.md`
- `docs/policy-catalog.md`
- `docs/context-package.md`
- `docs/policy-evaluation/README.md`
- `groups/target-groups.md`

## Further reading

Honorable mention: Ewelina Paczkowska ("Welka") at Welka's World has published a strong Conditional Access series that aligns well with the persona-based and operational design approach used here.

- [Conditional Access Essentials: Introduction, use cases, the art of possible](https://www.welkasworld.com/post/conditional-access-essentials-introduction-use-cases-the-art-of-possible)
- [Conditional Access Essentials: Naming conventions, personas, emergency access & design process](https://www.welkasworld.com/post/conditional-access-naming-conventions-personas-design-process)
- [Conditional Access Essentials: Managing Exclusions with Identity Governance and Temporary Access Pass](https://www.welkasworld.com/post/conditional-access-essentials-managing-exclusions-with-identity-governance-and-temporary-access-pas)

## Setup

1. Copy `.env.example` to `.env.local`.
2. Populate tenant and app registration values.
3. Resolve any intentional tenant placeholders called out above before enabling the affected policies.
4. Review the required Graph permissions before running deploy or export scripts.
5. Start with `-Mode Evaluate` or `-WhatIf` before any deployment run.

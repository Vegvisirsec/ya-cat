┌──────────────────────────────────────────────────────────────┐
│ ya-cat : Yet Another Conditional Access Toolkit             │
├──────────────────────────────────────────────────────────────┤
│      /\_/\\                                                 │
│     ( o.o )                                                 │
│      > ^ <                                                  │
│                                                              │
│  __   __        ______      _                               │
│  \ \ / /__ _   / ____/___ _| |_                             │
│   \ V / _` |  / /   / __ `| __|                             │
│    | | (_| | / /___/ /_/ / |_                              │
│    |_|\__,_| \____/\__,_|\__|                              │
│                                                              │
│      Yet Another Conditional Access Toolkit                 │
└──────────────────────────────────────────────────────────────┘

Portable Conditional Access policy definitions, deployment helpers, export utilities, and reviewer guidance for Microsoft 365 environments.

## What it does

Core things this repo is for:

1. Deploy the preset Conditional Access policies from this repo to a target tenant, either all of them or selected bundles/policies.
2. Pull Conditional Access policies from a target tenant and store them locally as JSON.
3. Compare/evaluate the target tenant policy set against the repo policy set and show what coverage is missing.
4. Pull recent sign-in locations from the target tenant and turn them into a named location.

## Design approach

This toolkit loosely follows a persona-based Conditional Access design approach, but it is not a pure persona model. The policy tiers reflect both user type (persona) and license capability: baseline can be thought of as the stuff, that should be deployed to every tenant. Managed controls can be thought of as the policies that you should deploy, if you have devices mostly managed by Intune. While frontline and E5 can be considered as sub-personas of the "typical user", with different operating "patterns" or higher-capability license availability. 

## What this repo includes

- policy JSON for baseline, managed, frontline, and E5 tiers
- PowerShell scripts for deploy, evaluate, export, and supporting Graph utilities
- target-group and exclusion-group reference material
- per-policy reviewer instructions for structured assessment work
- reviewer-oriented documentation for structured assessment work

## Supported

- Authentication methods: `ClientSecret`, `ClientCertificate`, and `Delegated` interactive sign-in
- Main script coverage: deploy, deploy-from-folder, export, and Graph utility scripts all resolve auth from `.env.local`
- Default auth mode: `ClientSecret` if `AUTH_METHOD` is not set
- Environment-based configuration: set `AUTH_METHOD` plus the matching credential values in `.env.local`

## Safety defaults

- new toolkit-managed policies deploy as `reportOnly`
- break-glass exclusions are delivered through group membership, but must be manually maintained in the target tenant
- Any deployment should be validated in a non-production tenant first!

## Intentional placeholders

Two policy templates intentionally retain tenant-specific deployment placeholders and will be skipped until manually edited to replace the placeholders with correct values

- `policies/baseline/CA-BL-009.block-non-business-countries.json` requires `{{BUSINESS_COUNTRIES_LOCATION_ID}}`
- `policies/baseline/CA-BL-010.require-terms-of-use-for-guests.json` requires `{{TERMS_OF_USE_ID}}`

For `CA-BL-010`, there is a barebones starter document at `examples/sample-terms-of-use.md`. Export it to PDF, create the Terms of use object in the portal, then use that object ID for `{{TERMS_OF_USE_ID}}`.

Short portal path:

1. Microsoft Entra admin center
2. `Entra ID` > `Conditional Access` > `Terms of use`
3. `New terms`
4. Upload the PDF, set the name/display name, create it
5. Copy the Terms of use object ID into `CA-BL-010`

## Core paths

- `policies/` policy definitions and schema
- `groups/` target group and exclusion group model
- `src/deploy/` deployment entry points
- `src/evaluate/` export utilities
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

## Authentication examples

Client secret with export:

```dotenv
TENANT_ID=<your-tenant-id>
CLIENT_ID=<your-app-client-id>
AUTH_METHOD=ClientSecret
CLIENT_SECRET=<your-app-client-secret>
GRAPH_SCOPE=https://graph.microsoft.com/.default
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src/evaluate/Export-CAPolicies.ps1 -EnvFile .env.local
```

Client certificate with export:

```dotenv
TENANT_ID=<your-tenant-id>
CLIENT_ID=<your-app-client-id>
AUTH_METHOD=ClientCertificate
CERTIFICATE_THUMBPRINT=<your-cert-thumbprint>
GRAPH_SCOPE=https://graph.microsoft.com/.default
```

Or use a certificate file:

```dotenv
TENANT_ID=<your-tenant-id>
CLIENT_ID=<your-app-client-id>
AUTH_METHOD=ClientCertificate
CERTIFICATE_PATH=C:\path\to\graph-auth.pfx
CERTIFICATE_PASSWORD=<optional-pfx-password>
GRAPH_SCOPE=https://graph.microsoft.com/.default
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src/evaluate/Export-CAPolicies.ps1 -EnvFile .env.local
```

Delegated interactive sign-in with export:

```dotenv
TENANT_ID=<your-tenant-id>
CLIENT_ID=<your-app-client-id>
AUTH_METHOD=Delegated
GRAPH_SCOPE=https://graph.microsoft.com/.default
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src/evaluate/Export-CAPolicies.ps1 -EnvFile .env.local
```

Delegated auth requires the `Microsoft.Graph.Authentication` PowerShell module and will open an interactive `Connect-MgGraph` sign-in flow.

## Documentation 

- `docs/architecture.md`
- `docs/policy-catalog.md`
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

# Policy Catalog

## Status model

- planned
- draft
- ready
- implemented
- validated

## Naming convention

Format: `CA-<tier>-<id> - <policy name>`

Tier codes:
- `BL` baseline
- `MG` managed
- `FL` frontline
- `E5` E5-only

## Catalog

| ID | Name | Tier | Purpose | Target group | State default | License capability | Status |
|---|---|---|---|---|---|---|---|
| CA-BL-001 | Block Legacy Authentication | baseline | Block legacy auth flows | All users | reportOnly | P1 | draft |
| CA-BL-002 | Require Phishing-Resistant MFA for Admins | baseline | Protect privileged access | Built-in privileged role set | reportOnly | P1 | draft |
| CA-BL-003 | Require MFA or Managed Device Signal for Users | baseline | Raise base auth assurance with OR controls | All users | reportOnly | P1 | draft |
| CA-BL-004 | Require MFA for Security Info Registration \(Trusted Locations\) | baseline | Protect security info registration | All users | reportOnly | P1 | draft |
| CA-BL-005 | Block Device Code Flow | baseline | Block device code authentication flow | All users | reportOnly | P1 | draft |
| CA-BL-006 | Block Authentication Transfer | baseline | Block authentication transfer flow | All users | reportOnly | P1 | draft |
| CA-BL-007 | Block Unsupported Device Platforms | baseline | Deny unsupported platforms | All users | reportOnly | P1 | draft |
| CA-BL-008 | Require App Protection for Mobile | baseline | Protect mobile access paths | All users | reportOnly | P1 | draft |
| CA-BL-009 | Block Non-Business Countries (optional) | baseline | Restrict sign-ins by country model | All users | reportOnly | P1 | planned |
| CA-BL-010 | Require Terms of Use for Guests (optional) | baseline | Enforce TOU for guest access | guest/external users | reportOnly | P1 | planned |
| CA-BL-011 | Require MFA for Guests and External Users (optional) | baseline | Guest/external minimum MFA baseline | guest/external users | reportOnly | P1 | planned |
| CA-BL-012 | Block Legacy Authentication for Guests and External Users (optional) | baseline | Block legacy auth for guest/external identities | guest/external users | reportOnly | P1 | planned |
| CA-BL-013 | Require MFA for Device Registration or Join | baseline | Enforce MFA on Entra device registration/join action | All users | reportOnly | P1 | draft |
| CA-BL-014 | Block Agent Identities | baseline | Discover and later govern agent identity access | all agent identities | reportOnly | P1 | draft |
| CA-BL-015 | Block Untargeted Identities | baseline | Catch identities outside toolkit targeting groups | All users minus toolkit targeting groups | reportOnly | P1 | draft |
| CA-MG-101 | Block Unmanaged Windows Devices for M365 Browser Access | managed | Block browser access from unmanaged Windows devices | CA-Tier-P1-Managed | reportOnly | P1 | draft |
| CA-MG-102 | Block Unmanaged Windows Devices for M365 Rich Client Access | managed | Block rich client access from unmanaged Windows devices | CA-Tier-P1-Managed | reportOnly | P1 | draft |
| CA-MG-103 | Block Unmanaged Windows Devices for Sensitive Apps | managed | Block sensitive app access from unmanaged Windows devices | CA-Tier-P1-Managed | reportOnly | P1 | draft |
| CA-MG-104 | Block Unmanaged Windows Workstations for Admin Access | managed | Prevent admin access from unmanaged Windows devices | Built-in privileged role set | reportOnly | P1 | draft |
| CA-MG-105 | Restrict Unmanaged Browser Sessions | managed | Limit unmanaged browser session behavior | CA-Tier-P1-Managed | reportOnly | P1 | draft |
| CA-FL-201 | Require App Protection for Frontline Mobile | frontline | Protect frontline mobile access | CA-Tier-Frontline | reportOnly | P1 | draft |
| CA-FL-202 | Block Unmanaged Windows Devices for Frontline Access | frontline | Block frontline access from unmanaged Windows devices | CA-Tier-Frontline | reportOnly | P1 | draft |
| CA-FL-203 | Restrict Unmanaged Browser Sessions for Frontline | frontline | Apply browser session limits for frontline | CA-Tier-Frontline | reportOnly | P1 | draft |
| CA-FL-204 | Restrict Access to Frontline App Set | frontline | Scope frontline usage to approved app set | CA-Tier-Frontline | reportOnly | P1 | draft |
| CA-FL-205 | Block Unmanaged Windows Devices for Frontline Admin or Supervisor Access | frontline | Prevent elevated frontline access from unmanaged Windows devices | Built-in privileged role set | reportOnly | P1 | draft |
| CA-E5-401 | Sign-In Risk Requires MFA | e5 | Step up high/medium risky sign-ins | CA-Tier-E5 | reportOnly | P2 | draft |
| CA-E5-402 | User Risk Requires Password Change | e5 | Require remediation for high user risk | CA-Tier-E5 | reportOnly | P2 | draft |
| CA-E5-403 | Block Unmanaged Windows Workstations for Privileged Access | e5 | Prevent privileged access from unmanaged Windows devices | Built-in privileged role set | reportOnly | P2 | draft |
| CA-E5-404 | Block Unmanaged Windows Devices for High-Value Apps | e5 | Apply stronger controls to high-value apps | CA-Tier-E5 | reportOnly | P2 | draft |

## Deployment rule

All deployed policies are forced to `enabledForReportingButNotEnforced` by deployment script.

## Safety rule

Every policy includes `CA-BreakGlass-Exclude` in `conditions.users.excludeGroups` during deployment.

## Evaluation guides

Per-policy reviewer guides live under `docs/policy-evaluation/` and mirror the policy inventory by tier and policy ID.
Use [`docs/policy-evaluation/README.md`](policy-evaluation/README.md) as the entry point for authoring and reuse.






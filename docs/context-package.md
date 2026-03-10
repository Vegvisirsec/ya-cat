# Context Package Design

## Purpose

The context package is the local, privacy-respecting input set for advisory Conditional Access evaluation.

It is designed to support realistic tenant assessment without collecting raw user inventories, usernames, or unnecessary tenant detail.

## Design Principle

Collect only data that is used in an evaluation decision.

## Example Policy-Driven Requirements

### CA-BL-002 Require Phishing-Resistant MFA for Admins

Needs:
- count of privileged role members
- count of admin-focused exception groups
- tenant policy state

Reason:
- a small exclusion set may be acceptable in a large tenant
- the same exclusion ratio in a small privileged population may be material

### CA-BL-009 Block Non-Business Countries

Needs:
- named location definitions
- aggregated sign-in country distribution
- tenant policy state

Reason:
- geo-restriction should be judged against real operating geography, not just template presence

### CA-BL-014 Block Agent Identities

Needs:
- tenant policy state
- aggregated sign-in policy hits
- top impacted apps

Reason:
- the discovery value comes from report-only hit review and governance follow-up, not from static policy JSON alone

### CA-BL-015 Block Untargeted Identities

Needs:
- toolkit target group existence and member counts
- tenant policy state
- aggregated sign-in policy hits

Reason:
- this policy is useful only if it identifies identities outside the targeting model and drives group hygiene improvements

## Package Contents

### `manifest.json`

Lists files and explains why each file exists.

### `desired-state/`

- toolkit policy manifest
- raw policy JSON copied from the repository

Used for:
- desired-state reference
- local LLM input
- human review

### `tenant-state/tenant-profile.json`

Contains:
- tenant ID
- tenant display name
- verified domain summary

Used for:
- package orientation
- report metadata

### `tenant-state/user-population-summary.json`

Contains aggregated counts only:
- total users
- member users
- guest users
- enabled member users
- enabled guest users

Used for:
- proportional risk judgments
- guest policy review
- exclusion ratio interpretation

### `tenant-state/toolkit-group-summary.json`

Contains:
- standard toolkit groups
- policy-specific exclusion groups
- existence status
- member counts

Used for:
- targeting-model review
- CA-BL-015 admission-control analysis
- exclusion hygiene review

### `tenant-state/privileged-role-summary.json`

Contains:
- active role display name
- role template ID
- member count

Used for:
- admin policy review
- privileged exposure interpretation

### `tenant-state/named-locations.json`

Contains:
- named location objects

Used for:
- CA-BL-004 and CA-BL-009 review
- location-governance interpretation

### `tenant-state/tenant-policies.json`

Contains:
- exported Conditional Access policy objects

Used for:
- deterministic compare
- local LLM evaluation
- human review

### `tenant-state/sign-in-aggregate-summary.json`

Contains aggregated sign-in telemetry only:
- total sign-ins in window
- top countries
- top applications
- Conditional Access policy hit summaries by policy

Used for:
- report-only hit review
- CA-BL-009 geography context
- CA-BL-014 agent identity discovery review
- CA-BL-015 untargeted identity guardrail review

No usernames or raw sign-in rows are included.

### `llm/`

- `instructions.md`
- `findings-schema.json`

Used for:
- local advisory evaluation contract
- output validation

## Export Script

Use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File src/evaluate/Export-CAContextPackage.ps1 -EnvFile .env.local -DaysPast 30
```

## Minimum Permissions

- `Policy.Read.All`
- `Group.Read.All`
- `Directory.Read.All`
- `AuditLog.Read.All`

## Privacy Notes

- no usernames are exported
- no raw sign-in event list is exported
- no raw group membership lists are exported
- the package uses counts, summaries, and policy objects only

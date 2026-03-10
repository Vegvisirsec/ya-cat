# CA-FL-203 Evaluation Instructions

## Purpose

Evaluate `CA-FL-203 - Restrict Unmanaged Browser Sessions for Frontline` as an experienced Microsoft security consultant would.
Assess whether unmanaged frontline browser sessions are meaningfully restricted when full blocking is not used.

## Template Facts

- policy id: `CA-FL-203`
- display name: `CA-FL-203 - Restrict Unmanaged Browser Sessions for Frontline`
- source template: `policies/frontline/CA-FL-203.restrict-unmanaged-browser-sessions-for-frontline.json`
- target population: `CA-Tier-Frontline`
- expected control type: session control
- expected scope summary: apply `applicationEnforcedRestrictions` for browser access to `Office365`

## Review Evidence

Use:
- frontline browser session policies
- session restriction behavior
- unmanaged kiosk or browser scenarios

## What Good Looks Like

- unmanaged browser sessions for frontline users are materially limited
- restrictions fit the actual frontline app usage model

## Acceptable Variation

- the tenant blocks frontline browser access instead of restricting sessions
- restrictions are narrower but aligned to the actual frontline app set

## Concern Triggers

- unrestricted frontline browser sessions remain possible on unmanaged endpoints
- session restriction is used as a weak substitute for stronger needed controls
- the tenant cannot explain the frontline browser exposure model

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Focus on practical risk reduction in real frontline scenarios.

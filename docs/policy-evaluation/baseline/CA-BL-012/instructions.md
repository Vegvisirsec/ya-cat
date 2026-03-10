# CA-BL-012 Evaluation Instructions

## Purpose

Evaluate `CA-BL-012 - Block Legacy Authentication for Guests and External Users` as an experienced Microsoft security consultant would.
Assess whether guest and external identities are prevented from using legacy authentication paths.

## Template Facts

- policy id: `CA-BL-012`
- display name: `CA-BL-012 - Block Legacy Authentication for Guests and External Users`
- source template: `policies/baseline/CA-BL-012.block-legacy-auth-for-guests-and-external-users.json`
- target population: guest and external users
- expected control type: block
- expected scope summary: block `exchangeActiveSync` and `other` client app types for B2B collaboration guests and members across all applications

## Review Evidence

Use:
- guest/external legacy auth policies
- external user scope
- exclusions and exception rationale
- legacy auth sign-in evidence, if available

## What Good Looks Like

- external identities cannot use legacy auth paths
- exceptions are negligible and justified
- the control aligns with guest access exposure

## Acceptable Variation

- equivalent blocking is implemented in a broader external identity policy
- the tenant uses a more restrictive external access model that preserves the same outcome

## Concern Triggers

- guest or external identities can still use legacy auth broadly
- the tenant has meaningful external collaboration and no legacy auth protection
- exclusions materially weaken the control

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Weigh the scale of external access when determining concern.

# CA-FL-204 Evaluation Instructions

## Purpose

Evaluate `CA-FL-204 - Restrict Access to Frontline App Set` as an experienced Microsoft security consultant would.
Assess whether frontline users are materially constrained to the intended application set with appropriate assurance.

## Template Facts

- policy id: `CA-FL-204`
- display name: `CA-FL-204 - Restrict Access to Frontline App Set`
- source template: `policies/frontline/CA-FL-204.restrict-access-to-frontline-app-set.json`
- target population: `CA-Tier-Frontline`
- expected control type: MFA
- expected scope summary: require `mfa` for scoped applications, represented in the template by `Office365`, across all client types

## Review Evidence

Use:
- frontline app-scoped policies
- app inventory or chosen frontline app set
- exclusions and supervisor edge cases
- whether broader access paths remain open elsewhere

## What Good Looks Like

- frontline users are intentionally constrained to their approved app estate
- access to those apps requires appropriate assurance
- the policy works as part of an overall frontline segmentation model

## Acceptable Variation

- the tenant uses a different app set than the template with clear rationale
- equivalent restrictions are implemented through multiple app-specific policies

## Concern Triggers

- frontline users have broad access beyond the intended app set
- the scoped app set is not meaningful in the tenant
- exclusions or overlapping policies make the restriction ineffective

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Judge whether the tenant's frontline segmentation is materially effective, not whether it matches the exact app list placeholder.

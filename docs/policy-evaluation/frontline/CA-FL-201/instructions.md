# CA-FL-201 Evaluation Instructions

## Purpose

Evaluate `CA-FL-201 - Require App Protection for Frontline Mobile` as an experienced Microsoft security consultant would.
Assess whether frontline mobile access is materially limited to protected app paths.

## Template Facts

- policy id: `CA-FL-201`
- display name: `CA-FL-201 - Require App Protection for Frontline Mobile`
- source template: `policies/frontline/CA-FL-201.require-approved-app-or-app-protection-for-frontline-mobile.json`
- target population: `CA-Tier-Frontline`
- expected control type: app protection
- expected scope summary: require `compliantApplication` for Android and iOS mobile/desktop client access across all applications for frontline users

## Review Evidence

Use:
- frontline mobile CA policies
- app protection deployment evidence
- user population in the frontline tier
- exclusions and device-sharing realities

## What Good Looks Like

- frontline mobile access is materially tied to protected app paths
- shared-device realities are accounted for without opening broad unmanaged access
- exceptions are limited and justified

## Acceptable Variation

- the tenant scopes the control to the actual frontline app estate
- equivalent MAM or approved-app controls are used

## Concern Triggers

- frontline mobile access is broad and unmanaged
- app protection assumptions are not backed by deployment reality
- exclusions materially weaken the control

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Consider frontline usability constraints, but do not excuse broad unmanaged mobile exposure.

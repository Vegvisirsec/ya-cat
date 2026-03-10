# CA-BL-008 Evaluation Instructions

## Purpose

Evaluate `CA-BL-008 - Require App Protection for Mobile` as an experienced Microsoft security consultant would.
Assess whether mobile access is materially constrained to protected app paths.

## Template Facts

- policy id: `CA-BL-008`
- display name: `CA-BL-008 - Require App Protection for Mobile`
- source template: `policies/baseline/CA-BL-008.require-approved-app-or-app-protection-for-mobile.json`
- target population: all users
- expected control type: app protection
- expected scope summary: require `compliantApplication` for `android` and `iOS` mobile/desktop client access across all applications

## Review Evidence

Use:
- mobile platform CA policies
- app protection or approved-app enforcement
- excluded users and apps
- MAM deployment posture, if available

## What Good Looks Like

- mobile access is materially limited to protected app paths
- broad mobile access does not bypass app protection expectations
- exceptions are small and justified

## Acceptable Variation

- the tenant scopes this more narrowly to sensitive apps but has compensating controls elsewhere
- the tenant uses equivalent approved-app or MAM controls
- staged rollout is evident and progressing

## Concern Triggers

- unmanaged mobile access remains broad
- app protection is expected but not materially enforced
- large user or app exclusions weaken the control

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Consider mobile usage patterns before labeling narrower scope as inadequate.

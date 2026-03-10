# CA-BL-015 Evaluation Instructions

## Purpose

Evaluate `CA-BL-015 - Block Untargeted Identities` as an experienced Microsoft security consultant would.
Assess whether the tenant is using this policy as an effective admission-control guardrail for identities outside the targeting model.

## Template Facts

- policy id: `CA-BL-015`
- display name: `CA-BL-015 - Block Untargeted Identities`
- source template: `policies/baseline/CA-BL-015.block-untargeted-identities.json`
- target population: all users except toolkit target groups, pilot, and policy-specific admission exception group
- expected control type: block
- expected scope summary: block all applications and client types for identities not assigned to the toolkit targeting groups

## Review Evidence

Use:
- deployed policy state
- sign-ins hitting the policy
- membership quality of toolkit targeting groups
- temporary admission exceptions
- guest or external access model, if relevant

## What Good Looks Like

- the policy identifies real onboarding and targeting gaps
- most legitimate workforce identities are already classified into the targeting model
- temporary admission exceptions are short-lived
- the policy improves group hygiene over time

## Acceptable Variation

- the tenant keeps the policy in `reportOnly` while validating guest, pilot, and special-population behavior
- a tenant uses a slightly different set of exclusion groups if the targeting model differs but the control intent remains the same

## Concern Triggers

- many legitimate users repeatedly hit the policy
- the exception group becomes a permanent holding area
- the tenant cannot explain who should belong to which target group
- the policy would unintentionally capture guest or special populations without a reviewed design

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Judge whether the policy is improving admission hygiene, not merely generating noise.

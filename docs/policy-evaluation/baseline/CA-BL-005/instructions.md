# CA-BL-005 Evaluation Instructions

## Purpose

Evaluate `CA-BL-005 - Block Device Code Flow` as an experienced Microsoft security consultant would.
Assess whether device code authentication is materially blocked for users who should not rely on it.

## Template Facts

- policy id: `CA-BL-005`
- display name: `CA-BL-005 - Block Device Code Flow`
- source template: `policies/baseline/CA-BL-005.block-device-code-flow.json`
- target population: all users
- expected control type: block
- expected scope summary: block `deviceCodeFlow` for all users across all applications and client types

## Review Evidence

Use:
- policies targeting `authenticationFlows.transferMethods`
- exclusions and business justifications
- device code usage evidence, if available
- special device scenarios and service dependencies

## What Good Looks Like

- device code flow is broadly blocked
- any exceptions are rare and clearly justified
- there is no silent dependency that keeps the flow widely open

## Acceptable Variation

- the tenant blocks device code flow with narrower policy scope where risk is still materially reduced
- temporary exceptions exist for known operational edge cases

## Concern Triggers

- device code flow remains broadly available
- exclusions are large or undocumented
- the tenant depends on device code flow in ways that materially weaken phishing resistance

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Differentiate niche operational exceptions from meaningful exposure.

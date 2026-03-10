# CA-E5-404 Evaluation Instructions

## Purpose

Evaluate `CA-E5-404 - Block Unmanaged Windows Devices for High-Value Apps` as an experienced Microsoft security consultant would.
Assess whether the tenant materially applies stronger access conditions to its high-value application set.

## Template Facts

- policy id: `CA-E5-404`
- display name: `CA-E5-404 - Block Unmanaged Windows Devices for High-Value Apps`
- source template: `policies/e5/CA-E5-404.stronger-controls-for-high-value-apps.json`
- target population: `CA-Tier-E5`
- expected control type: block
- expected scope summary: block scoped applications, represented in the template by `Office365`, from unmanaged Windows devices for the E5 tier

## Review Evidence

Use:
- app-scoped high-value access policies
- device filter logic
- actual high-value app selection
- exclusions and population coverage

## What Good Looks Like

- the tenant has an intentional high-value app set
- those apps are materially protected from unmanaged Windows access
- scope and exceptions reflect actual business sensitivity

## Acceptable Variation

- the tenant uses a different high-value app set than the template placeholder
- stronger controls apply to a narrower app list that is clearly justified

## Concern Triggers

- the tenant has no meaningful high-value app differentiation
- unmanaged Windows access remains available for the most sensitive apps
- app scope is arbitrary or not tied to actual business value

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Focus on whether the tenant has a defensible high-value app control model, not on exact app identifiers in the template.

# CA-BL-009 Evaluation Instructions

## Purpose

Evaluate `CA-BL-009 - Block Non-Business Countries` as an experienced Microsoft security consultant would.
Assess whether geo-restriction is implemented in a realistic and governable way for the tenant.

## Template Facts

- policy id: `CA-BL-009`
- display name: `CA-BL-009 - Block Non-Business Countries`
- source template: `policies/baseline/CA-BL-009.block-non-business-countries.json`
- target population: all users
- expected control type: block
- expected scope summary: block all locations except the named business-countries location set

## Review Evidence

Use:
- named location definitions
- geo-restriction policies
- travel patterns and external workforce context, if available
- exclusions and business rationale
- rollout state and false-positive management

## What Good Looks Like

- named locations are based on real operating geography
- geo restrictions are governable and aligned with business reality
- exceptions are limited and controlled

## Acceptable Variation

- the tenant does not use this control because its operating geography makes it impractical
- the tenant uses named-location restrictions only for sensitive populations or apps
- a more targeted geo-control strategy exists

## Concern Triggers

- the tenant claims geo restriction but named locations are stale or overly broad
- exclusions undermine the control
- the control is absent in a tenant where geography-based restriction is clearly expected and feasible

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Do not treat absence as automatic failure; judge whether geo restriction is defensible for the tenant.

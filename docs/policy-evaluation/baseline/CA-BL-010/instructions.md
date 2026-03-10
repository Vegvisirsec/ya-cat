# CA-BL-010 Evaluation Instructions

## Purpose

Evaluate `CA-BL-010 - Require Terms of Use for Guests` as an experienced Microsoft security consultant would.
Assess whether guest acceptance controls are present and meaningful where guest access is in use.

## Template Facts

- policy id: `CA-BL-010`
- display name: `CA-BL-010 - Require Terms of Use for Guests`
- source template: `policies/baseline/CA-BL-010.require-terms-of-use-for-guests.json`
- target population: guest and external users
- expected control type: terms of use
- expected scope summary: require a configured Terms of Use object for B2B collaboration guests and members across all applications

## Review Evidence

Use:
- guest/external user policies
- Terms of Use objects and assignments
- guest population size
- guest access model and app exposure

## What Good Looks Like

- guest access includes an intentional acceptance or governance step where appropriate
- scope aligns with actual guest usage
- the control is not purely cosmetic

## Acceptable Variation

- the tenant omits this control because guest access is extremely limited or otherwise strongly governed
- equivalent guest governance controls exist outside this exact CA pattern

## Concern Triggers

- a large guest population exists with weak onboarding or acceptance governance
- the control is configured but not materially applied
- guest scope is broad and unmanaged

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Judge guest governance maturity, not merely the presence of a Terms of Use object.

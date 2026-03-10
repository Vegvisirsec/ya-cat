# CA-BL-011 Evaluation Instructions

## Purpose

Evaluate `CA-BL-011 - Require MFA for Guests and External Users` as an experienced Microsoft security consultant would.
Assess whether guest and external identities are materially subject to MFA before accessing tenant resources.

## Template Facts

- policy id: `CA-BL-011`
- display name: `CA-BL-011 - Require MFA for Guests and External Users`
- source template: `policies/baseline/CA-BL-011.require-mfa-for-guests-and-external-users.json`
- target population: guest and external users
- expected control type: MFA
- expected scope summary: require `mfa` for B2B collaboration guests and members across all applications

## Review Evidence

Use:
- guest/external MFA policies
- guest population size and app exposure
- exclusions and external collaboration design
- compensating controls such as cross-tenant trust, if available

## What Good Looks Like

- external identities face MFA or materially equivalent assurance before broad access
- exclusions are rare and justified
- guest access design does not rely on implicit trust alone

## Acceptable Variation

- the tenant narrows this to specific guest app sets but still materially protects external access
- cross-tenant trust or partner design justifies a slightly different control shape

## Concern Triggers

- broad guest access exists without MFA
- exclusions cover significant guest populations
- external collaboration is open without clear assurance controls

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Account for the scale and sensitivity of guest access when judging severity.

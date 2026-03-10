# CA-BL-004 Evaluation Instructions

## Purpose

Evaluate `CA-BL-004 - Require MFA for Security Info Registration (Trusted Locations)` as an experienced Microsoft security consultant would.
Assess whether security info registration is protected with appropriate sign-in assurance in the tenant's real design.

## Template Facts

- policy id: `CA-BL-004`
- display name: `CA-BL-004 - Require MFA for Security Info Registration (Trusted Locations)`
- source template: `policies/baseline/CA-BL-004.require-mfa-for-security-info-registration.json`
- target population: all users
- expected control type: MFA for user action
- expected scope summary: require `mfa` for `urn:user:registersecurityinfo` from `AllTrusted` locations

## Review Evidence

Use:
- policies covering security info registration user actions
- trusted location definitions
- alternate registration protection design
- exclusions and rollout state

## What Good Looks Like

- security info registration is protected by MFA or a materially equivalent assurance control
- trusted location logic is intentional and well understood
- exceptions are limited and documented

## Acceptable Variation

- the tenant protects registration from all locations instead of only trusted locations
- the tenant uses stronger assurance than the template
- location design differs but still materially protects the action

## Concern Triggers

- security info registration is effectively unprotected
- trusted location logic is overly broad or poorly governed
- many users can bypass the control through exclusions or alternate paths

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Pay attention to whether the trusted-location assumption is defensible in the tenant.

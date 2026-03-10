# CA-BL-002 Evaluation Instructions

## Purpose

Evaluate `CA-BL-002 - Require Phishing-Resistant MFA for Admins` as an experienced Microsoft security consultant would.
Assess whether privileged access is materially protected with stronger authentication than the standard user baseline.

## Template Facts

- policy id: `CA-BL-002`
- display name: `CA-BL-002 - Require Phishing-Resistant MFA for Admins`
- source template: `policies/baseline/CA-BL-002.require-mfa-for-admins.json`
- target population: built-in privileged role set
- expected control type: authentication strength
- expected scope summary: require `Phishing-resistant MFA` for high-value built-in admin roles across all applications and client types

## Review Evidence

Use:
- privileged-role-targeted policies
- authentication strength configuration
- excluded admin users or groups
- admin count and exclusion ratios
- alternate privileged access controls, if any

## What Good Looks Like

- privileged roles are covered by phishing-resistant MFA or a materially equivalent strong control
- exclusions are rare, justified, and time-bounded where possible
- privileged identities are not relying solely on broad standard-user MFA policy

## Acceptable Variation

- the tenant uses equivalent admin-focused authentication strength policies
- scope is split by role type or admin tier
- a very small emergency or transition exclusion set exists with clear rationale

## Concern Triggers

- privileged identities are covered only by generic MFA
- excluded admins represent meaningful exposure
- broad persistent admin exclusions exist
- stronger auth is absent for high-impact admin roles

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Treat privileged exposure as higher weight than generic user coverage gaps.

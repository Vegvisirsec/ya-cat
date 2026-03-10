# CA-E5-402 Evaluation Instructions

## Purpose

Evaluate `CA-E5-402 - User Risk Requires Password Change` as an experienced Microsoft security consultant would.
Assess whether high user risk is materially remediated with the intended recovery pattern.

## Template Facts

- policy id: `CA-E5-402`
- display name: `CA-E5-402 - User Risk Requires Password Change`
- source template: `policies/e5/CA-E5-402.user-risk-requires-password-change.json`
- target population: `CA-Tier-E5`
- expected control type: user risk remediation
- expected scope summary: require `mfa` and `passwordChange` for `high` user risk across all applications and client types

## Review Evidence

Use:
- user-risk CA policies
- self-service password reset readiness, if available
- exclusions and break/fix patterns
- licensed population scope

## What Good Looks Like

- high user risk triggers a real remediation flow
- dependencies such as password reset are operationally viable
- exclusions are minimal and documented

## Acceptable Variation

- the tenant uses an equivalent high-risk remediation design
- scope is narrower because E5 licensing is intentionally limited

## Concern Triggers

- high user risk does not trigger remediation
- the configured response is nonfunctional in practice
- exclusions materially undermine the control

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Judge whether the remediation flow is actually usable, not merely configured.

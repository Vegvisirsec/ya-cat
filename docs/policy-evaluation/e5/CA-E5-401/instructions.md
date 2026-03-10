# CA-E5-401 Evaluation Instructions

## Purpose

Evaluate `CA-E5-401 - Sign-In Risk Requires MFA` as an experienced Microsoft security consultant would.
Assess whether risky sign-ins for the E5 population are materially stepped up with MFA.

## Template Facts

- policy id: `CA-E5-401`
- display name: `CA-E5-401 - Sign-In Risk Requires MFA`
- source template: `policies/e5/CA-E5-401.sign-in-risk-requires-mfa.json`
- target population: `CA-Tier-E5`
- expected control type: risk-based MFA
- expected scope summary: require `mfa` for `high` and `medium` sign-in risk across all applications and client types

## Review Evidence

Use:
- risk-based CA policies
- E5 population scope
- exclusions and exception rationale
- sign-in risk rollout considerations

## What Good Looks Like

- medium and high sign-in risk events trigger MFA for the intended population
- risk policy scope aligns with licensing and user population
- exclusions are small and justified

## Acceptable Variation

- the tenant applies this to a different but defensible licensed population
- the tenant targets only high risk if medium risk is operationally noisy and other controls compensate

## Concern Triggers

- risky sign-ins are not stepped up at all
- exclusions weaken the policy for important users
- the tenant has E5 capability but no meaningful risk-based sign-in control

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Account for licensing scope and operational maturity when judging the exact risk threshold.

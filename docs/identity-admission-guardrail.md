# Identity Admission Guardrail

## Purpose

Use a catch-all report-only block policy to surface identities that are not mapped into the repository targeting model.

Policy reference:
- `CA-BL-015 - Block Untargeted Identities`

## Intent

If an identity is not placed into one of the toolkit targeting groups, it should not silently fall through operating assumptions.

The policy acts as:
- an onboarding hygiene signal
- a targeting gap detector
- a trigger to assign the identity to the correct group

## Initial Operating Model

- deploy in `reportOnly`
- monitor hits weekly
- identify whether the identity should belong to `CA-Tier-Baseline`, `CA-Tier-P1-Managed`, `CA-Tier-Frontline`, `CA-Tier-E5`, or another approved path
- fix targeting rather than normalize long-term exceptions

## Exclusions

The template excludes:
- `CA-BreakGlass-Exclude`
- toolkit tier groups
- `CA-Pilot`
- `CA-EXC-BL-015-UntargetedIdentityAdmission`

Use `CA-EXC-BL-015-UntargetedIdentityAdmission` only for short-lived onboarding or classification gaps.

## Important Caveat

Before enforcement, validate how this policy interacts with:
- guest and external identities
- pilot users
- service-linked edge cases
- identity populations not yet modeled in the toolkit

## Recommended Triage Flow

1. identify the triggering identity
2. confirm whether the sign-in is legitimate
3. place the identity in the correct target group
4. re-test sign-in behavior
5. remove any temporary admission exception

## Design Principle

This policy should drive better targeting hygiene, not become a permanent exception bucket.

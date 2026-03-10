# CA-BL-013 Evaluation Instructions

## Purpose

Evaluate `CA-BL-013 - Require MFA for Device Registration or Join` as an experienced Microsoft security consultant would.
Assess whether device registration and join actions are materially protected against weak sign-in assurance.

## Template Facts

- policy id: `CA-BL-013`
- display name: `CA-BL-013 - Require MFA for Device Registration or Join`
- source template: `policies/baseline/CA-BL-013.require-mfa-for-device-registration-or-join.json`
- target population: all users
- expected control type: MFA for user action
- expected scope summary: require `mfa` for `urn:user:registerdevice`

## Review Evidence

Use:
- user-action CA policies for device registration
- device onboarding model
- exclusions and operational exceptions
- registration volume or edge-case workflows, if available

## What Good Looks Like

- users cannot register or join devices without MFA or equivalent assurance
- exceptions are rare and intentional
- onboarding processes do not create an easy bypass path

## Acceptable Variation

- the tenant uses stronger or broader control than the template
- implementation is split by device scenario but preserves effective assurance

## Concern Triggers

- device registration is effectively open without MFA
- exclusions are broad or undocumented
- onboarding exceptions create material exposure

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Focus on real registration assurance, not exact user-action syntax matching.

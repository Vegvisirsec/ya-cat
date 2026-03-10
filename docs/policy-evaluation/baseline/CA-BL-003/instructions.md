# CA-BL-003 Evaluation Instructions

## Purpose

Evaluate `CA-BL-003 - Require MFA or Managed Device Signal for Users` as an experienced Microsoft security consultant would.
Assess whether the tenant has a materially effective baseline user access control that raises authentication assurance.

## Template Facts

- policy id: `CA-BL-003`
- display name: `CA-BL-003 - Require MFA or Managed Device Signal for Users`
- source template: `policies/baseline/CA-BL-003.require-mfa-for-users.json`
- target population: all users
- expected control type: MFA or managed device signal
- expected scope summary: require `mfa` or `domainJoinedDevice` or `compliantDevice` for all users across all applications and client types

## Review Evidence

Use:
- broad user MFA policies
- device-based access controls
- exclusions and assignment scope
- tenant size and excluded population percentage
- compensating controls for unmanaged access

## What Good Looks Like

- most workforce users are covered by a baseline control that materially raises sign-in assurance
- exclusions are limited and justified
- the tenant does not leave broad unmanaged access paths open without compensation

## Acceptable Variation

- equivalent user coverage is split across app or persona-specific policies
- the tenant requires MFA everywhere without device-based OR logic
- phased rollout remains in `reportOnly` with evidence of progression

## Concern Triggers

- large parts of the workforce are outside baseline assurance controls
- exclusions are broad relative to tenant size
- privileged or sensitive populations depend only on weak baseline coverage
- unmanaged access remains widely possible without compensating controls

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Judge material population coverage, not exact grant-control parity.

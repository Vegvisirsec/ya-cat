# CA-BL-007 Evaluation Instructions

## Purpose

Evaluate `CA-BL-007 - Block Unsupported Device Platforms` as an experienced Microsoft security consultant would.
Assess whether unsupported or unknown device platforms are materially denied access.

## Template Facts

- policy id: `CA-BL-007`
- display name: `CA-BL-007 - Block Unsupported Device Platforms`
- source template: `policies/baseline/CA-BL-007.block-unsupported-device-platforms.json`
- target population: all users
- expected control type: block
- expected scope summary: include all platforms, exclude known supported platforms, and block access to all applications for all users

## Review Evidence

Use:
- platform-targeted policies
- supported platform list
- exclusions and exception groups
- sign-in evidence for unknown or unsupported platforms, if available

## What Good Looks Like

- unsupported or unknown platforms are denied by policy
- supported platform definitions are intentional and current
- exceptions are limited and justified

## Acceptable Variation

- the tenant uses alternate platform scoping that still blocks unsupported platforms
- app-specific implementation achieves the same practical result for the main risk surface

## Concern Triggers

- unknown platforms are effectively allowed
- platform scope is incomplete or outdated
- exclusions create material blind spots

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Pay attention to whether unsupported platforms can still reach important apps.

# CA-FL-202 Evaluation Instructions

## Purpose

Evaluate `CA-FL-202 - Block Unmanaged Windows Devices for Frontline Access` as an experienced Microsoft security consultant would.
Assess whether frontline access from unmanaged Windows devices is materially prevented where Windows use is relevant.

## Template Facts

- policy id: `CA-FL-202`
- display name: `CA-FL-202 - Block Unmanaged Windows Devices for Frontline Access`
- source template: `policies/frontline/CA-FL-202.require-compliant-shared-device-for-frontline-access.json`
- target population: `CA-Tier-Frontline`
- expected control type: block
- expected scope summary: block all applications and client types from unmanaged Windows devices for frontline users

## Review Evidence

Use:
- frontline Windows device policies
- shared device and kiosk context
- Windows device filter logic
- exclusions and operational exceptions

## What Good Looks Like

- frontline Windows usage is tied to managed/shared corporate devices
- unmanaged Windows access is not broadly possible
- exceptions are limited and documented

## Acceptable Variation

- the tenant has minimal frontline Windows usage and uses narrower control scope
- equivalent compliant-device or shared-device control exists

## Concern Triggers

- unmanaged Windows access remains broad for frontline users
- kiosk or shared-device models are poorly aligned with CA scope
- exclusions significantly reduce effectiveness

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Judge the control in the context of actual frontline Windows use, not assumed use.

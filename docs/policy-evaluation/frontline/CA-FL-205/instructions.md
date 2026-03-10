# CA-FL-205 Evaluation Instructions

## Purpose

Evaluate `CA-FL-205 - Block Unmanaged Windows Devices for Frontline Admin or Supervisor Access` as an experienced Microsoft security consultant would.
Assess whether elevated frontline access from unmanaged Windows devices is materially prevented.

## Template Facts

- policy id: `CA-FL-205`
- display name: `CA-FL-205 - Block Unmanaged Windows Devices for Frontline Admin or Supervisor Access`
- source template: `policies/frontline/CA-FL-205.require-managed-device-for-frontline-admin-or-supervisor-access.json`
- target population: built-in privileged role set
- expected control type: block
- expected scope summary: block all applications and client types from unmanaged Windows devices for privileged frontline admin or supervisor access

## Review Evidence

Use:
- privileged frontline access policies
- Windows device filter logic
- excluded supervisors or admins
- device model for elevated frontline work

## What Good Looks Like

- elevated frontline access requires managed Windows devices
- privileged exceptions are rare and justified
- frontline supervisory workflows do not create unmanaged privileged access paths

## Acceptable Variation

- the tenant uses dedicated admin workstation controls that are stronger than this template
- the implementation is split between supervisor and admin populations but preserves the same outcome

## Concern Triggers

- elevated frontline access is possible from unmanaged Windows devices
- exclusions are broad or persistent
- the tenant treats generic frontline controls as sufficient for elevated access

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Treat privileged frontline exposure as high impact even in small populations.

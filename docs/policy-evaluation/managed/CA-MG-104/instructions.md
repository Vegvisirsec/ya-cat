# CA-MG-104 Evaluation Instructions

## Purpose

Evaluate `CA-MG-104 - Block Unmanaged Windows Workstations for Admin Access` as an experienced Microsoft security consultant would.
Assess whether privileged access from unmanaged Windows devices is materially prevented.

## Template Facts

- policy id: `CA-MG-104`
- display name: `CA-MG-104 - Block Unmanaged Windows Workstations for Admin Access`
- source template: `policies/managed/CA-MG-104.require-managed-workstation-for-admin-access.json`
- target population: built-in privileged role set
- expected control type: block
- expected scope summary: block all applications and client types from unmanaged Windows devices for privileged roles

## Review Evidence

Use:
- privileged device-based access policies
- Windows device filter logic
- excluded admins and exclusion ratios
- alternate admin workstation model

## What Good Looks Like

- admins cannot access tenant resources from unmanaged Windows devices
- privileged exceptions are rare and strongly justified
- admin workstation expectations are clear and enforceable

## Acceptable Variation

- the tenant uses stronger dedicated admin workstation controls
- implementation is split across role tiers or app families while preserving effective protection

## Concern Triggers

- admins can work broadly from unmanaged Windows devices
- exclusion scope includes meaningful privileged exposure
- generic user policies are being treated as sufficient admin protection

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Treat even small privileged gaps as potentially high impact.

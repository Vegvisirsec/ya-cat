# CA-MG-102 Evaluation Instructions

## Purpose

Evaluate `CA-MG-102 - Block Unmanaged Windows Devices for M365 Rich Client Access` as an experienced Microsoft security consultant would.
Assess whether rich client access to Microsoft 365 is materially blocked from unmanaged Windows devices for managed users.

## Template Facts

- policy id: `CA-MG-102`
- display name: `CA-MG-102 - Block Unmanaged Windows Devices for M365 Rich Client Access`
- source template: `policies/managed/CA-MG-102.require-compliant-device-for-m365-rich-client-access.json`
- target population: `CA-Tier-P1-Managed`
- expected control type: block
- expected scope summary: block `mobileAppsAndDesktopClients` access to `Office365` from unmanaged Windows devices

## Review Evidence

Use:
- rich client CA policies
- Windows device filter logic
- exclusions and business exceptions
- app and user scope alignment

## What Good Looks Like

- managed users cannot use rich clients against M365 from unmanaged Windows devices
- exceptions are minimal and justified
- alternate access paths do not undermine the control

## Acceptable Variation

- the tenant enforces compliant or hybrid-joined device requirements instead of this exact block pattern
- equivalent protection is split across app families

## Concern Triggers

- unmanaged Windows rich client access remains broad
- exclusions cover a meaningful share of managed users
- the tenant cannot explain why unmanaged clients remain allowed

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Evaluate effective unmanaged Windows rich-client restriction, not template literal matching.

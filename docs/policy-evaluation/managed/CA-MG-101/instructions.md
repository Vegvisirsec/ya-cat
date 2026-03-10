# CA-MG-101 Evaluation Instructions

## Purpose

Evaluate `CA-MG-101 - Block Unmanaged Windows Devices for M365 Browser Access` as an experienced Microsoft security consultant would.
Assess whether managed-user browser access to Microsoft 365 is materially restricted from unmanaged Windows devices.

## Template Facts

- policy id: `CA-MG-101`
- display name: `CA-MG-101 - Block Unmanaged Windows Devices for M365 Browser Access`
- source template: `policies/managed/CA-MG-101.require-compliant-device-for-m365-browser-access.json`
- target population: `CA-Tier-P1-Managed`
- expected control type: block
- expected scope summary: block browser access to `Office365` from Windows devices that are neither `AzureAD` nor `ServerAD` trusted

## Review Evidence

Use:
- managed-user browser policies
- Windows device filter logic
- population assigned to the managed tier
- exclusions and app scope rationale

## What Good Looks Like

- managed users cannot browse M365 from unmanaged Windows devices
- exclusions are limited and justified
- app scope matches the intended managed-user baseline

## Acceptable Variation

- the tenant uses compliant-device requirements instead of block-on-filter logic
- app coverage is split across multiple M365 services but preserves the same result

## Concern Triggers

- managed users retain broad browser access from unmanaged Windows devices
- device filter scope is ineffective or stale
- exclusions materially weaken the control

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Judge whether unmanaged Windows browser access is materially constrained for the intended managed population.

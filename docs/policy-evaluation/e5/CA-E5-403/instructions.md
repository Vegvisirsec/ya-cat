# CA-E5-403 Evaluation Instructions

## Purpose

Evaluate `CA-E5-403 - Block Unmanaged Windows Workstations for Privileged Access` as an experienced Microsoft security consultant would.
Assess whether privileged access is materially restricted to managed Windows workstations for the targeted high-assurance population.

## Template Facts

- policy id: `CA-E5-403`
- display name: `CA-E5-403 - Block Unmanaged Windows Workstations for Privileged Access`
- source template: `policies/e5/CA-E5-403.require-managed-workstation-for-privileged-access.json`
- target population: built-in privileged role set
- expected control type: block
- expected scope summary: block all applications and client types from unmanaged Windows devices for privileged roles

## Review Evidence

Use:
- privileged Windows workstation policies
- device filter logic
- excluded privileged users
- PAW or admin workstation strategy, if available

## What Good Looks Like

- privileged access is confined to managed Windows workstations
- exceptions are minimal and tightly governed
- the control aligns with a clear privileged workstation model

## Acceptable Variation

- the tenant uses stronger dedicated privileged workstation controls
- scope is split across admin tiers while preserving the same protection outcome

## Concern Triggers

- privileged access from unmanaged Windows devices remains broadly possible
- exclusion scope is meaningful relative to the small privileged population
- the tenant lacks a coherent workstation model for privileged work

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Because the affected population is small and sensitive, even limited gaps may be material.

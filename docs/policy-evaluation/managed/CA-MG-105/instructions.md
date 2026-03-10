# CA-MG-105 Evaluation Instructions

## Purpose

Evaluate `CA-MG-105 - Restrict Unmanaged Browser Sessions` as an experienced Microsoft security consultant would.
Assess whether unmanaged browser usage is materially constrained through session controls for managed users.

## Template Facts

- policy id: `CA-MG-105`
- display name: `CA-MG-105 - Restrict Unmanaged Browser Sessions`
- source template: `policies/managed/CA-MG-105.restrict-unmanaged-browser-sessions.json`
- target population: `CA-Tier-P1-Managed`
- expected control type: session control
- expected scope summary: apply `applicationEnforcedRestrictions` for browser access to `Office365`

## Review Evidence

Use:
- session-control CA policies
- unmanaged browser access paths
- SharePoint/Exchange session behavior, if available

## What Good Looks Like

- unmanaged browser sessions are materially limited where full block is not intended
- scope matches real unmanaged browser risk

## Acceptable Variation

- the tenant uses stronger blocking instead of session restriction
- restrictions are limited to the apps where session control is technically meaningful

## Concern Triggers

- unrestricted unmanaged browser sessions remain possible for sensitive content
- session controls are configured but not materially aligned with business risk
- the tenant relies on session restrictions where stronger controls are warranted

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Judge whether session restriction is materially reducing risk or only creating the appearance of control.

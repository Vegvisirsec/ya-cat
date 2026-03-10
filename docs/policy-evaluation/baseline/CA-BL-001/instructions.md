# CA-BL-001 Evaluation Instructions

## Purpose

Evaluate `CA-BL-001 - Block Legacy Authentication` as an experienced Microsoft security consultant would.
Assess whether legacy authentication is materially blocked for the intended tenant population.

## Template Facts

- policy id: `CA-BL-001`
- display name: `CA-BL-001 - Block Legacy Authentication`
- source template: `policies/baseline/CA-BL-001.block-legacy-authentication.json`
- target population: all users
- expected control type: block
- expected scope summary: block `exchangeActiveSync` and `other` client app types for all users across all applications

## Review Evidence

Use:
- deployed tenant policies targeting legacy auth client app types
- policy state and exclusions
- break-glass handling
- legacy auth sign-in evidence, if available
- tenant size and excluded population size

## What Good Looks Like

- legacy authentication is blocked for nearly all normal users
- any exclusions are tightly limited and justified
- break-glass accounts remain excluded only where intended
- there is no broad legacy auth allowance left through alternate policies

## Acceptable Variation

- equivalent blocking is split across multiple policies
- a very small documented exclusion set exists for temporary operational reasons
- rollout remains in `reportOnly` if there is evidence of active validation

## Concern Triggers

- no effective legacy auth block exists
- exclusions materially weaken protection
- guest or special populations are left open without justification
- the tenant still shows substantial legacy auth activity without a containment plan

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Focus on whether legacy auth is materially blocked, not whether the tenant copied this exact template.

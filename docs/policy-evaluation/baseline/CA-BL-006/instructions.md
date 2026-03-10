# CA-BL-006 Evaluation Instructions

## Purpose

Evaluate `CA-BL-006 - Block Authentication Transfer` as an experienced Microsoft security consultant would.
Assess whether authentication transfer is appropriately restricted in the tenant's actual operating model.

## Template Facts

- policy id: `CA-BL-006`
- display name: `CA-BL-006 - Block Authentication Transfer`
- source template: `policies/baseline/CA-BL-006.block-authentication-transfer.json`
- target population: all users
- expected control type: block
- expected scope summary: block `authenticationTransfer` for all users across all applications and client types

## Review Evidence

Use:
- policies targeting authentication transfer flows
- exclusions and known business scenarios
- mobile and device onboarding dependencies
- rollout state and exception rationale

## What Good Looks Like

- authentication transfer is blocked or tightly controlled
- exceptions are rare and documented
- the tenant does not leave a broad transfer-based bypass path open

## Acceptable Variation

- the tenant narrows the block to high-risk populations or apps while still materially reducing exposure
- limited temporary exclusions exist with review plans

## Concern Triggers

- authentication transfer remains broadly allowed
- exclusion scope is large relative to tenant size
- the tenant cannot explain why the flow remains open

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Focus on whether this flow creates a realistic bypass path in the tenant.

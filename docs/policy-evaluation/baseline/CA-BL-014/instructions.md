# CA-BL-014 Evaluation Instructions

## Purpose

Evaluate `CA-BL-014 - Block Agent Identities` as an experienced Microsoft security consultant would.
Assess whether the tenant is using the policy effectively as an agent-identity discovery and governance control.

## Template Facts

- policy id: `CA-BL-014`
- display name: `CA-BL-014 - Block Agent Identities`
- source template: `policies/baseline/CA-BL-014.block-agent-identities.json`
- target population: all agent identities
- expected control type: block
- expected scope summary: block `All` agent identities across all applications, intended to run in `reportOnly` first for visibility

## Review Evidence

Use:
- deployed policy state
- agent-identity policy hits or reports
- any tenant-local approval register
- ownership and business-purpose documentation
- evidence of review cadence

## What Good Looks Like

- the tenant has visibility into agent identity activity
- report-only hits are reviewed on a defined cadence
- the organization is moving toward an explicit approval model
- tenant-local approvals are documented outside portable source policy JSON

## Acceptable Variation

- the tenant keeps the policy in report-only longer while building inventory and approval criteria
- the tenant narrows initial enforcement scope after discovery if supported by a justified governance model

## Concern Triggers

- agent identities are active but unreviewed
- there is no ownership or approval record for observed agents
- the policy exists but nobody uses its telemetry
- the tenant plans to hardcode approved agent IDs into portable source policy files

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Judge governance maturity and visibility value, not just whether a block exists.

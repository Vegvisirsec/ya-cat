# <POLICY ID> Evaluation Instructions

## Purpose

Evaluate the tenant implementation of `<POLICY ID> - <POLICY NAME>` as an experienced Microsoft security consultant would.

Assess realistic control effectiveness against the repository template.
Do not reduce the review to exact JSON parity.

## Template Facts

- policy id: `<POLICY ID>`
- display name: `<DISPLAY NAME>`
- source template: `<POLICY JSON PATH>`
- target population: `<TARGET POPULATION>`
- expected control type: `<BLOCK | MFA | APP PROTECTION | SESSION CONTROL | TERMS OF USE | OTHER>`
- expected scope summary: `<SCOPE SUMMARY>`

## Review Evidence

Use available tenant context such as:
- deployed tenant policy or equivalent policies
- included and excluded users, groups, or roles
- affected applications, platforms, client types, locations, or risk conditions
- policy state and rollout notes
- tenant size and relevant population counts
- documented exceptions and compensating controls

## What Good Looks Like

- the tenant has this control or a materially equivalent implementation
- scope covers the intended population with limited justified exclusions
- privileged exposure is treated with higher scrutiny where relevant
- rollout state is defensible for tenant maturity
- deviations from template are explainable and do not materially weaken protection

## Acceptable Variation

Examples of acceptable variation:
- the tenant splits this control into multiple narrower policies
- exclusions are small, documented, and justified
- an alternate but materially equivalent control exists
- the policy remains in `reportOnly` during an active staged rollout with evidence of progress

## Concern Triggers

Escalate concern when:
- the target population is materially uncovered
- exclusions are broad, undocumented, or high-impact
- privileged identities are weakly protected
- the policy is disabled or effectively bypassed without a compensating control
- rollout state appears abandoned

## Output Requirements

Use [`policy-assessment-schema.json`](policy-assessment-schema.json) for structured results.

State:
- evidence used
- tenant context used
- why the implementation is acceptable or concerning
- recommended action
- assumptions and confidence

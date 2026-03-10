# Policy Evaluation Guides

This folder contains reusable instructions for evaluating individual Conditional Access policy templates.

## Purpose

Use these guides when:
- reviewing one deployed tenant policy against one repository template
- creating evaluation guidance for newly added policy templates

## Reusable Assets

- [`TEMPLATE.instructions.md`](TEMPLATE.instructions.md): base structure for new per-policy instructions
- [`policy-assessment-schema.json`](policy-assessment-schema.json): output contract for policy-level findings

## Authoring Rules

When adding a new policy template:

1. create a matching folder under `docs/policy-evaluation/<tier>/<policy-id>/`
2. add `instructions.md` using the template in this folder
3. mirror the real policy JSON in `policies/`
4. keep the evaluation focused on material protection outcomes
5. document acceptable tenant-specific variation
6. document concern triggers that should raise review priority

## Required Sections For Each Policy Guide

- purpose
- template facts
- review evidence
- what good looks like
- acceptable variation
- concern triggers
- output requirements

## Evaluation Principle

Per-policy review must assess realistic effectiveness, not exact string-level parity.
Equivalent controls, split implementations, and justified exclusions can be acceptable when they preserve material protection.

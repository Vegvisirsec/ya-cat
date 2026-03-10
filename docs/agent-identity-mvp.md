# Agent Identity Discovery and Approval MVP

## Purpose

Use a report-only Conditional Access block policy to measure agent identity adoption before introducing an approval workflow.

Policy reference:
- `CA-BL-014 - Block Agent Identities`

## Preview note

This policy depends on the Microsoft Entra agent identity Conditional Access preview surface and Microsoft Graph beta policy shape.

## Initial Operating Model

- deploy in `reportOnly`
- review policy hits regularly
- identify agent identities, owning team, app path, and business purpose
- do not approve by exception in source-controlled policy JSON

## Why Report-Only First

- provides visibility into real adoption
- avoids breaking early experiments while governance is undefined
- creates a factual inventory before designing approval criteria

## MVP Approval Workflow

Suggested first version:

1. requester submits a SharePoint form
2. form captures agent name, owner, business purpose, target apps, data handled, and expected run model
3. Power Automate routes approval to security and service owner
4. approved entries are recorded in a tenant-local register
5. a tenant-local allow mechanism is created outside portable source policy definitions

## Minimum Approval Fields

- agent identity name
- app or workload owner
- business justification
- target applications
- data sensitivity
- human sponsor
- expiry or review date
- compensating controls

## Design Constraints

- do not hardcode tenant-specific agent object IDs in source-controlled policy files
- keep approval records tenant-local
- treat this as governance discovery first, enforcement later
- prefer explicit expiry and review dates for approvals

## Future Direction

- add approval register export to context packages
- add advisory evaluation for approved versus unapproved agent identities
- define tenant-local automation for approved exceptions after the discovery phase is stable

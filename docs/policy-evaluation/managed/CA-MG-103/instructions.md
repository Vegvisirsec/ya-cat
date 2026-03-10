# CA-MG-103 Evaluation Instructions

## Purpose

Evaluate `CA-MG-103 - Block Unmanaged Windows Devices for Sensitive Apps` as an experienced Microsoft security consultant would.
Assess whether sensitive app access is materially denied from unmanaged Windows devices for managed users.

## Template Facts

- policy id: `CA-MG-103`
- display name: `CA-MG-103 - Block Unmanaged Windows Devices for Sensitive Apps`
- source template: `policies/managed/CA-MG-103.require-managed-device-for-sensitive-apps.json`
- target population: `CA-Tier-P1-Managed`
- expected control type: block
- expected scope summary: block all client types to scoped applications from unmanaged Windows devices for the managed tier

## Review Evidence

Use:
- sensitive app CA policies
- device filter and app scope
- managed-tier membership
- exclusions and app criticality

## What Good Looks Like

- sensitive apps are not reachable from unmanaged Windows devices by the intended population
- app scope matches actual sensitive business resources
- exceptions are small and justified

## Acceptable Variation

- the tenant uses a different sensitive-app set with clear rationale
- stronger per-app controls exist outside this exact template shape

## Concern Triggers

- sensitive apps remain accessible from unmanaged Windows devices
- app scope is overly broad or too narrow to be meaningful
- exclusions create real exposure to important apps

## Output Requirements

Use [`policy-assessment-schema.json`](../../policy-assessment-schema.json).
Pay particular attention to whether the tenant's chosen app scope is defensible.

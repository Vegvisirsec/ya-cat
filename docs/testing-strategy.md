# Testing Strategy

## Tenant type

Use a non-production test tenant for build validation.

## Test personas

- E5 test user
- E3 or Business Premium test user
- F3 or F1 test user
- admin test user
- break-glass account
- pilot user

## Test device patterns

- compliant managed device
- unmanaged device
- shared frontline device
- mobile device with app protection scenario

## MVP test areas

- manifest validation
- group mapping validation
- policy creation in report-only state
- idempotent re-apply behavior
- export and comparison behavior
- exclusion preservation

## Required rollout checks

- break-glass exclusion remains intact
- policy state is report-only unless explicitly changed
- target groups resolve correctly
- tenant export completes before mutation

## Not covered in the first phase

- production rollout
- automatic rollback
- semantic match for all policy edge cases
- trustworthy autonomous remediation

# Conditional Access Exclusion Test Pack

These scripts are short operator helpers for testing Conditional Access exclusions in a dev tenant.

- `CA-BL-001 - Block Legacy Authentication`
- `CA-BL-003 - Require MFA or Managed Device Signal for Users`
- `CA-BL-005 - Block Device Code Flow`
- `CA-BL-006 - Block Authentication Transfer`

## Usage Model

Run each script while signed in as the intended excluded test user for that policy. For location-sensitive tests, change VPN location between runs and compare the sign-in outcomes and report-only hits in Entra.

## Notes

- `CA-BL-001` may be configured as a direct user exclusion in the tenant under test.
- `CA-BL-003`, `CA-BL-005`, and `CA-BL-006` may use existing exclusion groups in the tenant under test.
- `CA-BL-001` legacy-auth testing is inherently imperfect in modern Microsoft 365 tenants because many legacy protocols are already deprecated service-side. The script still attempts a legacy-style auth flow to generate a useful sign-in event when possible.
- `CA-BL-006` authentication transfer testing is only partially scriptable. The helper script launches the browser entry point and prints the manual transfer steps to follow.

## Non-Production Warning

- These scripts are test helpers only.
- The related complementary-policy recommendation workflow is not trustworthy enough for production use at this time.
- Use these scripts only in disposable or explicitly approved non-production tenants.

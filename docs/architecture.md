# Architecture

## Objective

Represent Entra Conditional Access policy baselines as portable policy definitions that can be exported, compared, locally evaluated, and deployed through Microsoft Graph.

## MVP context and safety

- Built and validated in a private repository.
- Uses a non-production disposable test tenant only (no sensitive data).
- Secrets are local (`.env.local`) and are not committed to source control.
- Deployment safety is mandatory:
  - policies deploy as `reportOnly` by default
  - non-report-only state requires an explicit override path (for example, custom folder deploy options)

## Authentication methods

The toolbox supports pluggable authentication through `src/common/Authentication.ps1`:

### Client Secret (current default)
- Method: Service principal with client ID and secret
- Scope: Production-ready; suitable for automation
- Setup: Store `CLIENT_ID` and `CLIENT_SECRET` in `.env.local`
- Rotation: Requires secret updates in environment
- Trade-offs: Simple; secret rotation overhead in multi-tenant scenarios

### Client Certificate
- Method: Service principal with client ID and certificate-based assertion
- Scope: Recommended for multi-tenant deployments
- Setup: Provide certificate thumbprint or path; optional password for encrypted certs
- Rotation: Certificate auto-rotates via standard PKI workflow
- Trade-offs: Requires certificate infrastructure; better for compliance and multi-tenant

### Delegated (user-context auth)
- Method: Interactive OAuth2 flow using MSAL.PS
- Scope: Audit, evaluation, and compliance scenarios
- Setup: Requires interactive user sign-in; user context appears in logs
- Rotation: No credential rotation needed; uses signed-in user's token
- Trade-offs: Not suitable for unattended automation; requires MSAL.PS module

**Using different auth methods:**

Each script accepts `Get-GraphToken` calls that are compatible across all three methods. To switch methods, modify your `.env.local` file or pass appropriate parameters. Details on per-script configuration are in [src/graph/README.md](../src/graph/README.md) and deployment scripts.

## Multi-tenant considerations

When using this toolbox across multiple tenants:

- **Tenant identity**: Never hardcode tenant object IDs in policy definitions; use environment variables or configuration files
- **Permission scoping**: Each tenant requires appropriate app registration with `Policy.ReadWrite.ConditionalAccess` permission
- **Certificate-based auth**: Strongly recommended for multi-tenant; one app registration with certificates deployed to each tenant
- **Policy safety model**: The default `reportOnly` state applies per tenant; verify before enabling enforcement in new tenants
- **Exclusion groups**: Tenant-specific exclusion groups (like `CA-BreakGlass-Exclude`) must exist in each target tenant
- **Audit trail**: When using delegated auth, each deployment/evaluation shows authenticated user in tenant logs

**Single app registration across multiple tenants:**
- Requires multi-tenanted app registration in Azure AD
- Same client ID used across all target tenants
- Use certificate auth for credential management
- Store tenant-specific configuration separately (e.g., group mappings, scopes)
- Test thoroughly in non-production tenant first

## Core design

The project is split into four layers:

1. policy definitions
2. target group model
3. deployment engine
4. evaluation engine

The evaluation engine now has two parts:

1. deterministic export and comparison
2. local advisory interpretation using a context package

## Policy tiers

### Baseline
Applies to all covered users.

Examples:
- block legacy authentication
- require MFA for admins
- require MFA for users
- require MFA for security info registration

### Managed
Applies to managed information-worker populations.

Examples:
- block unmanaged Windows devices for selected access
- restrict unmanaged browser sessions
- block unmanaged Windows devices for sensitive apps

### Frontline
Applies to shared-device, mobile-first, or kiosk-style populations.

Examples:
- block unmanaged Windows devices where applicable
- require app protection for mobile
- narrow app scope and session behavior

### E5
Applies to populations with P2-backed capability.

Examples:
- sign-in risk policy
- user risk policy
- block unmanaged Windows workstations for privileged access

## Grouping model

Preferred tiers:
- `CA-BreakGlass-Exclude`
- `CA-Tier-Baseline`
- `CA-Tier-P1-Managed`
- `CA-Tier-Frontline`
- `CA-Tier-E5`
- `CA-Pilot`

Privileged policy targeting uses built-in Entra role template IDs (not `CA-Admins` group).

## Deployment model

Current implementation:
- read policy definition files
- resolve group mappings
- deploy policies in report-only state by default
- support dry-run and diff output
- preserve explicit exclusions
- support guest/external MVP profile toggle
- support preview-oriented agent identity policy definitions through Graph beta policy operations
- support backup export and deploy-from-folder workflows

## Evaluation model

Current evaluation model:
- fetch existing tenant policies
- compare key policy behavior to project definitions
- summarize coverage, exclusions, and state differences
- export report artifacts (CSV, JSON, or HTML)

Advisory evaluation direction:
- generate a tenant context package from exported policy state and supporting tenant metadata
- use repository policy definitions as the desired-state reference
- provide the context package to a local LLM under [`instructions.md`](../instructions.md)
- validate structured findings against [`findings-schema.json`](../findings-schema.json)
- treat the model as an interpretation and recommendation layer, not as the factual comparison engine

Compare mode status:
- `Compare` mode is currently experimental and not yet reliable for exact equivalence reporting.
- Treat `Compare` output as directional coverage only, not as a deployment or compliance gate.

Target context package contents:
- desired-state policy set
- exported tenant policy set
- normalized summaries and comparison output
- tenant size and population shape
- privileged role and break-glass context
- exclusion and assignment ratios
- agent identity governance context, when present
- named location and other relevant CA metadata

## Utility Scripts

The project includes helper scripts for supporting tasks:

### Discover-SignInLocations.ps1
Analyzes sign-in logs to identify geographic locations of user activity and optionally creates named locations for Conditional Access policies. Useful for:
- Understanding where your tenant's users are signing in from
- Establishing baseline geography for location-based policies
- Creating data-driven named locations based on actual usage patterns
- Privacy-preserving (extracts only location data, not user identities)
- Named location default naming: `<tenant>-operating-locations-<year>` (override with `-NamedLocationName`)
- Provenance is written to `created-named-location-metadata.json` when `-CreateNamedLocation` is used
- `countryNamedLocation` supports `displayName`; provenance/creation details are stored locally (no writable description field in create payload)

See `src/graph/README.md` for full documentation and usage.

### Query-CAPolicyImpact.ps1
Analyzes the real-world impact of a Conditional Access policy by querying sign-in logs and filtering them against the policy's conditions. Useful for:
- Report-only impact analysis: See which users/locations would be blocked by a geo-location policy
- Policy validation: Before enabling a policy, verify the scope of affected users or locations
- Incident investigation: Determine which sign-ins triggered a security policy
- Compliance reporting: Export sign-in data for audit and governance (privacy-respecting by default: no usernames unless explicitly requested)

See `src/graph/README.md` for full documentation and usage.

## Non-goals for MVP

- exact exclusion parity analysis
- full semantic policy equivalence
- full license inference from overlapping service plans
- autonomous remediation
- production orchestration

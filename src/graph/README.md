# Graph Utilities

This folder contains PowerShell scripts for interacting with Microsoft Graph API in the context of Entra CA policy management.

## Discover-SignInLocations.ps1

Discovers geographic locations from sign-in logs and optionally creates named locations in Conditional Access.

### Purpose

- Analyzes sign-in logs from the past N days
- Extracts **location data only** (for privacy) — no usernames, email addresses, or user details
- Aggregates all unique geographic locations with sign-in counts
- Exports results for review and policy creation
- *(Experimental)* Optionally creates named location policy rules from discovered locations

### Status

✅ **Location Discovery**: Fully functional and tested  
✅ **Named Location Creation**: Fully functional and tested

### Privacy-First Design

This script is designed with privacy as a core principle:
- Only location data is extracted from sign-in logs (city, state, country)
- No user identities, email addresses, or other user data is processed
- Results are anonymized and aggregated
- No personally identifiable information (PII) is logged or exported

### Prerequisites

1. Azure app registration with the following **Application** permissions:

| Permission | Type | Reason |
|-----------|------|--------|
| `AuditLog.Read.All` | Application | Query sign-in logs to extract location data |
| `Directory.Read.All` | Application | Read directory data for context (supporting) |
| `Policy.ReadWrite.ConditionalAccess` | Application | Create and manage conditional access named locations |

2. Environment variables configured in `.env.local`:
   ```
   TENANT_ID=<your-tenant-id>
   CLIENT_ID=<your-app-client-id>
   AUTH_METHOD=ClientSecret
   CLIENT_SECRET=<your-app-client-secret>
   ```

   For certificate auth, set `AUTH_METHOD=ClientCertificate` and provide `CERTIFICATE_THUMBPRINT` or `CERTIFICATE_PATH` (+ `CERTIFICATE_PASSWORD` if needed). For interactive sign-in, set `AUTH_METHOD=Delegated`.

3. **Authentication**: This script supports multiple authentication methods (client secret, certificate, delegated). See [../common/README.md](../common/README.md) for setup details and alternatives to client secret authentication.

### Usage

#### Basic usage - Report only
```powershell
.\Discover-SignInLocations.ps1
```

#### Discover locations from past 60 days
```powershell
.\Discover-SignInLocations.ps1 -DaysPast 60
```

#### Create a named location from discoveries
```powershell
.\Discover-SignInLocations.ps1 -CreateNamedLocation
```

#### Include unknown locations (not recommended for analysis)
```powershell
.\Discover-SignInLocations.ps1 -IncludeUnknownLocations
```

#### Specify custom output folder
```powershell
.\Discover-SignInLocations.ps1 -OutputFolder 'C:\Reports\LocationAnalysis'
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `EnvFile` | string | `.env.local` | Path to environment variables file |
| `DaysPast` | int | 30 | Number of days to look back in sign-in logs |
| `OutputFolder` | string | `output/sign-in-locations-<timestamp>` | Where to save results |
| `CreateNamedLocation` | switch | false | Create a named location after discovery |
| `NamedLocationName` | string | `<tenant>-operating-locations-<year>` | Optional override for display name of the created named location |
| `IncludeUnknownLocations` | switch | false | Include entries where location cannot be determined |

### Output

The script generates the following files in the output folder:

#### `discovered-locations.json`
Summary of all discovered locations:
```json
{
  "discoveredAt": "2026-03-07T15:30:00Z",
  "daysPast": 30,
  "locationCount": 42,
  "locations": {
    "Seattle, WA, United States": {
      "city": "Seattle",
      "state": "WA",
      "countryOrRegion": "United States",
      "count": 127
    },
    ...
  }
}
```

#### `created-named-location.json` (if `-CreateNamedLocation` is used)
Details of the created named location policy:
```json
{
  "id": "<policy-id>",
  "displayName": "contoso-operating-locations-2026",
  "countriesAndRegions": ["US", "CA"],
  "@odata.type": "#microsoft.graph.countryNamedLocation"
}
```

#### `created-named-location-metadata.json` (if `-CreateNamedLocation` is used)
Local provenance metadata for how the named location was generated:
```json
{
  "generatedNamedLocationName": "contoso-operating-locations-2026",
  "tenantDisplayName": "Contoso Ltd",
  "tenantId": "<tenant-id>",
  "generatedAt": "2026-03-07T12:00:00Z",
  "daysPast": 30,
  "includeUnknownLocations": false,
  "provenanceNote": "Auto-generated from sign-in log location discovery..."
}
```

### Named Location Types

The script creates a **country-based named location** (`countryNamedLocation`). This is useful for:
- Geographic-based Conditional Access policies
- Restricting access by country
- Blocking or requiring MFA for specific regions

`countryNamedLocation` does not expose a writable `description` field in the Graph create payload. This script stores provenance in `created-named-location-metadata.json` instead.

If you need IP-based locations instead, you can manually convert the results or modify the script.

### Examples

#### Scenario 1: Discover locations for policy baseline
```powershell
# Discover locations from the past 90 days
.\Discover-SignInLocations.ps1 -DaysPast 90

# Review the discovered-locations.json file
# Use this data to inform your named location policy
```

#### Scenario 2: Auto-create named location for conditional access rule
```powershell
# Discover and create named location in one step
.\Discover-SignInLocations.ps1 -CreateNamedLocation `
  -NamedLocationName 'Org-Primary-Locations' `
  -DaysPast 60

# The named location can now be used in Conditional Access rules
```

#### Scenario 3: Regular monitoring for new locations
```powershell
# Weekly discovery to track emerging locations
.\Discover-SignInLocations.ps1 -OutputFolder 'weekly-reports'

# Compare results across weeks for patterns
```

### Limitations & Considerations

1. **Sign-in logs retention**: Azure sign-in logs are typically retained for 30 days (free) or 90 days (premium). Requesting data beyond retention returns empty results.

2. **Location accuracy**: The location data is derived from IP geolocation and may have limited accuracy, especially for VPN/proxy traffic.

3. **Unknown locations**: By default, entries with unknown location data are filtered out. Use `-IncludeUnknownLocations` to include them in analysis.

4. **Named locations limits**: Entra ID supports up to 150 named locations. Consider consolidating locations before creating policies.

5. **Permissions**: The service principal/app must have sufficient permissions in your tenant (see Prerequisites table).

### Troubleshooting

#### "Missing required env var: TENANT_ID"
Ensure `.env.local` file exists and contains valid credentials. See [Configuration](../docs/architecture.md) for setup.

#### "Failed to acquire Graph access token"
Check that:
- `.env.local` matches the selected `AUTH_METHOD`
- Client secret or certificate material is valid if using app-only auth
- The app registration has not expired and is not disabled in Azure AD
- `Microsoft.Graph.Authentication` is installed if using delegated auth

#### "No locations found in sign-in logs"
Possible causes:
- No sign-in activity in the specified period
- Sign-in logs have expired (beyond retention)
- Insufficient permissions to read audit logs

#### Graph API rate limiting
If processing very large tenants, the script may hit rate limits. Re-run after a delay. The script includes automatic retry logic with exponential backoff.

### Next Steps

1. Run the script to discover locations from sign-in logs
2. Review the generated `discovered-locations.json` file with location data and counts
3. Use `-CreateNamedLocation` to automatically create a named location in Conditional Access
4. The created named location can immediately be referenced in Conditional Access policy rules
5. Test policies in report-only mode before enabling

### Related Files

- [Architecture Documentation](../docs/architecture.md)
- [Example Conditional Access Policies](../policies/baseline/)
- [Deployment Script](../deploy/Deploy-CAPolicies.ps1)

---

## Query-CAPolicyImpact.ps1

Queries sign-in logs and analyzes which sign-ins would be affected by a specific Conditional Access policy.

### Purpose

- Lists all Conditional Access policies in the tenant
- Provides interactive menu to select a policy for analysis
- Retrieves all sign-in records for a configurable time window
- Filters sign-ins against the policy's conditions
- Exports matching records to CSV with:
  - **By default (privacy-respecting)**: Location, Timestamp, Application, Protocol, Device info, IP address
  - **Optional (with `-IncludeUsername`)**: User Principal Name

### Use Cases

- **Report-only impact analysis**: When a geo-block policy is in report-only mode, quickly identify all login locations that would have been blocked
- **Policy validation**: Before enabling a policy, verify the scope of users or locations affected
- **Incident investigation**: Analyze which users and locations triggered a security policy
- **Compliance reporting**: Export policy impact data for audit and compliance documentation

### Status

✅ **Policy Selection & Querying**: Fully functional  
✅ **Privacy-First Defaults**: No PII without explicit opt-in  
✅ **CSV Export**: Fully functional

### Privacy-First Design

By default, the script respects privacy:
- No usernames exported unless explicitly requested with `-IncludeUsername`
- Focus on technical impact factors: locations, applications, devices, protocols
- Aggregated output suitable for infosec review without exposing individual user identity

### Prerequisites

1. Azure app registration with the following **Application** permissions:

| Permission | Type | Reason |
|-----------|------|--------|
| `Policy.Read.All` | Application | Query Conditional Access policy definitions |
| `AuditLog.Read.All` | Application | Query sign-in logs for impact analysis |
| `Directory.Read.All` | Application | Read directory data for context |

2. Environment variables configured in `.env.local`:
   ```
   TENANT_ID=<your-tenant-id>
   CLIENT_ID=<your-app-client-id>
   AUTH_METHOD=ClientSecret
   CLIENT_SECRET=<your-app-client-secret>
   ```

   For certificate auth, set `AUTH_METHOD=ClientCertificate` and provide `CERTIFICATE_THUMBPRINT` or `CERTIFICATE_PATH` (+ `CERTIFICATE_PASSWORD` if needed). For interactive sign-in, set `AUTH_METHOD=Delegated`.

3. **Authentication**: This script supports multiple authentication methods (client secret, certificate, delegated). See [../common/README.md](../common/README.md) for setup details and alternatives to client secret authentication.

### Usage

#### Basic usage - Interactive policy selection
```powershell
.\Query-CAPolicyImpact.ps1
```
The script displays a menu of all policies and prompts you to select one.

#### Filter policies by name or ID
```powershell
.\Query-CAPolicyImpact.ps1
# At the filter prompt, type part of a policy name or ID
```

#### Analyze past 60 days instead of default 30
```powershell
.\Query-CAPolicyImpact.ps1 -DaysPast 60
```

#### Include username in the output (privacy opt-in)
```powershell
.\Query-CAPolicyImpact.ps1 -IncludeUsername
```

#### Specify policy by ID directly (skip menu)
```powershell
.\Query-CAPolicyImpact.ps1 -PolicyId "f6872b45-abcd-1234-efgh-5678ijklmnop"
```

#### Specify custom output folder
```powershell
.\Query-CAPolicyImpact.ps1 -OutputFolder 'C:\Reports\CAPolicyAnalysis'
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `EnvFile` | string | `.env.local` | Path to environment variables file |
| `DaysPast` | int | 30 | Number of days to look back in sign-in logs |
| `PolicyId` | string | (empty) | Azure object ID or display name of policy; skips menu if provided |
| `OutputFolder` | string | `output` | Where to save CSV results |
| `IncludeUsername` | switch | false | Include UserPrincipalName in CSV output; default is privacy-respecting |

### Output

Generates a CSV file named `CA-<PolicyName>-Impact-<YYYYMMDD>.csv` with columns:

| Column | Description | Always Included |
|--------|-----------|-----------------|
| `Timestamp` | Sign-in time (UTC) | ✓ |
| `City` | City from IP geolocation | ✓ |
| `State` | State/Province from IP geolocation | ✓ |
| `Country` | Country from IP geolocation | ✓ |
| `Application` | Friendly name of accessed application | ✓ |
| `AppId` | App registration object ID | ✓ |
| `Protocol` | Client app type (Browser, Mobile, etc.) | ✓ |
| `DeviceOS` | Operating system of device | ✓ |
| `DeviceBrowser` | Browser/client name and version | ✓ |
| `IPAddress` | Source IP address of sign-in | ✓ |
| `SignInStatus` | Status code (success, error type) | ✓ |
| `UserPrincipalName` | User email/UPN | ✗ (opt-in only) |

### Examples

#### Scenario 1: Analyze geo-block policy impact
```powershell
# Monday morning: review what would have been blocked over the weekend
.\Query-CAPolicyImpact.ps1 -DaysPast 3

# Select "Block High-Risk Countries" from the menu
# Review the CSV to see which locations would have been blocked
# Share anonymized report with security team
```

#### Scenario 2: Before enabling a new policy
```powershell
# Test a new MFA policy in report-only for a week
# Then analyze its impact
.\Query-CAPolicyImpact.ps1 -PolicyId "CA-MFA-NewPilot" -DaysPast 7

# Open the CSV and validate that only intended users/apps are affected
```

#### Scenario 3: Compliance audit with usernames
```powershell
# Export report with full user information for compliance team
.\Query-CAPolicyImpact.ps1 `
  -PolicyId "CA-BL-001-BlockLegacyAuth" `
  -DaysPast 90 `
  -IncludeUsername `
  -OutputFolder 'C:\Compliance\Q1-2026\Reports'

# Results can be used for audit trail and governance
```

#### Scenario 4: Investigate specific time period
```powershell
# Incident occurred 5 days ago; get details
.\Query-CAPolicyImpact.ps1 -DaysPast 5

# Review sign-in patterns and device info
# No usernames exported by default—safe to share with NOC team
```

### How Policy Matching Works

The script evaluates sign-ins against policy conditions:

1. **Application filtering**: Checks if the accessed app matches the policy's included applications
2. **Client app type filtering**: Validates browser vs. mobile vs. desktop client requirements
3. **Additional conditions**: Architecture supports extension for user, group, risk, and location conditions

**Note**: The current implementation provides basic matching for common conditions. For complex policies with nested conditions or custom logic, manual review of the CSV may be needed alongside the policy definition.

### Limitations & Considerations

1. **Sign-in log retention**: Azure sign-in logs are typically retained for 30 days (free) or 90 days (premium). Requesting older data returns empty or partial results.

2. **Policy condition complexity**: Policies with complex nested conditions or custom rules may not perfectly match; review CSV output to validate the filtering.

3. **Timestamp accuracy**: Sign-in timestamps are in UTC; adjust interpretation for local time zones as needed.

4. **Location accuracy**: IP-based geolocation may have limited accuracy for VPN/proxy traffic.

5. **Performance**: Large tenants with millions of sign-ins may require multiple API calls; the script includes automatic pagination and rate-limit handling.

### Troubleshooting

#### "No policies found in tenant"
- Verify the service principal has `Policy.Read.All` permission
- Check that policies exist in the tenant

#### "No matching sign-ins found"
- The policy conditions simply did not match any sign-ins in the time window
- Try increasing `-DaysPast` or verify the policy's conditions are not overly restrictive

#### "Rate limited (429)"
- The tenant has many sign-in records; the script automatically retries
- If errors persist, re-run the script after waiting a few minutes

#### "Failed to authenticate"
- Verify `.env.local` contains the correct values for the selected `AUTH_METHOD`
- Ensure the app registration and secret/certificate have not expired
- Install `Microsoft.Graph.Authentication` if you are using delegated interactive auth

### Next Steps

1. Run the script to identify a policy of interest
2. Review the generated CSV to understand the policy's impact
3. Share the results (with or without usernames) with stakeholders
4. If needed, modify policy conditions and re-run to iterate on scope

### Related Files

- [Architecture Documentation](../docs/architecture.md)
- [Discover-SignInLocations.ps1](./Discover-SignInLocations.ps1)
- [Deployment Script](../deploy/Deploy-CAPolicies.ps1)
- [Policy Catalog](../docs/policy-catalog.md)

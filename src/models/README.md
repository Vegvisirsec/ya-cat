# Policy Validation Framework

## Overview

The policy validation framework provides automated quality assurance for all CA policy definitions. It performs structural validation, enforces safety rules, and ensures consistency across the policy catalog.

## Components

### JSON Schema (`policies/schema/policy-schema.json`)
Defines the formal structure of policy files, including:
- Required fields (id, displayName, tier, conditions)
- Field types and allowed values
- Pattern validation for IDs and UUIDs
- Documentation for each property

**VS Code Integration**: If you have JSON Schema support enabled, open any policy file and VS Code will highlight schema violations in real-time.

### Validator Script (`src/models/Validate-Policies.ps1`)
PowerShell script that performs comprehensive validation including:
- JSON syntax and schema compliance
- Safety rule enforcement (break-glass exclusions, no hardcoded IDs)
- ID format and uniqueness checks
- Tier/folder placement consistency
- File naming conventions
- Group reference validation

## Usage

### Run from repository root:

#### Basic validation
```powershell
.\src\models\Validate-Policies.ps1
```

#### Verbose output (show all passes)
```powershell
.\src\models\Validate-Policies.ps1 -Verbose
```

#### Strict mode (fail on warnings, not just errors)
```powershell
.\src\models\Validate-Policies.ps1 -Strict
```

#### Custom paths
```powershell
.\src\models\Validate-Policies.ps1 -PolicyPath ./custom/policies -SchemaPath ./custom/schema.json
```

## Exit Codes

- **0**: All checks passed
- **1**: One or more errors or warnings (with -Strict)

## Validation Checks

### 1. Schema Validation ✓
- **Check**: JSON structure matches schema definition
- **Catches**: Missing required fields, invalid types, malformed arrays
- **Example Fail**: Missing `conditions` object

### 2. ID Format ✓
- **Check**: Policy ID must match pattern `CA-XX-NNN`
- **Catches**: Typos, invalid tier codes, non-numeric IDs
- **Example Fail**: `CA-BL-1` (missing leading zero), `CA-BASELINE-001` (invalid tier code)

### 3. Tier Validity ✓
- **Check**: Tier must be one of: baseline, managed, frontline, e5
- **Catches**: New tiers added without this validation updating
- **Example Fail**: `"tier": "premium"` (not a valid tier)

### 4. Tier/Folder Placement ✓✗
- **Check**: `CA-BL-*` files in `policies/baseline/`, `CA-MG-*` in `policies/managed/`, etc.
- **Catches**: Files in wrong tier folders
- **Example Fail**: `policies/managed/CA-BL-001.json` (baseline policy in managed folder)

### 5. File Naming ✓
- **Check**: Filename matches pattern `CA-XX-NNN.*.json`
- **Catches**: Misnamed files that won't be deployed
- **Example Fail**: `policies/baseline/block-legacy.json` (ID prefix required)

### 6. Break-Glass Exclusion ✓✗
- **Check**: Policy must include `CA-BreakGlass-Exclude` in exclusions
- **Catches**: Policies that would block all admins (safety rule)
- **Example Fail**: Missing break-glass group from `conditions.users.excludeGroups` or `target.excludeGroupNames`

### 7. Hardcoded Tenant IDs ⚠
- **Check**: Scans for hardcoded Microsoft Entra IDs (common vulnerability)
- **Catches**: Tenant-specific object IDs that shouldn't be in portable policy files
- **Note**: Warnings only; role template IDs in `includeRoleTemplateIds` are expected

### 8. ID Uniqueness ✓
- **Check**: No two policies have the same ID
- **Catches**: Copy-paste errors creating duplicate IDs
- **Example Fail**: Two files both defining `CA-BL-001`

### 9. Role Template ID Format ⚠
- **Check**: Role template IDs must be valid UUID format
- **Catches**: Malformed UUIDs in privileged policy targeting
- **Note**: Warnings only; allows valid UUID formats

### 10. Group References ⚠
- **Check**: Referenced groups are in standard set or follow naming convention
- **Catches**: Typos in group names, undefined groups
- **Standard Groups**: 
  - `CA-BreakGlass-Exclude`
  - `CA-Tier-Baseline`
  - `CA-Tier-P1-Managed`
  - `CA-Tier-Frontline`
  - `CA-Tier-E5`
  - Custom exclusion groups: `CA-EXC-*`

### 11. Grant/Session Controls
- **Check**: If present, controls are properly structured
- **Catches**: Malformed operator values, invalid control types

## Example Output

```
Policy Validation Report
═══════════════════════════════════════

Found 27 policy file(s)

Schema loaded: policies/schema/policy-schema.json

Validating: policies/baseline/CA-BL-001.block-legacy-authentication.json
  ✓ PASS: [policies/baseline/CA-BL-001.block-legacy-authentication.json] Schema structure valid
  ❌ ERROR: [policies/baseline/CA-BL-001.block-legacy-authentication.json] Missing break-glass exclusion (CA-BreakGlass-Exclude)
  ✓ PASS: [policies/baseline/CA-BL-001.block-legacy-authentication.json] Filename follows naming convention
  ✓ PASS: [policies/baseline/CA-BL-001.block-legacy-authentication.json] Tier placement correct (baseline folder)

Validating: policies/baseline/CA-BL-002.require-mfa-for-admins.json
  ✓ PASS: [policies/baseline/CA-BL-002.require-mfa-for-admins.json] Schema structure valid
  ✓ PASS: [policies/baseline/CA-BL-002.require-mfa-for-admins.json] Break-glass exclusion present
  ✓ PASS

Validation Summary
═══════════════════════════════════════
Policies processed: 27
Policies valid: 26
Errors: 1
Warnings: 0

✓ All validation checks passed
```

## Common Issues & Fixes

| Issue | Error Message | Fix |
|-------|---------------|-----|
| Missing break-glass | "Missing break-glass exclusion" | Add `"CA-BreakGlass-Exclude"` to `target.excludeGroupNames` |
| Wrong folder | "Tier placement incorrect" | Move file to correct tier folder and update `path` field |
| Duplicate ID | "Duplicate policy ID" | Verify IDs are unique across all policy files |
| Bad UUID | "Invalid role template ID format" | Ensure role template IDs are valid 8-4-4-4-12 format |
| Unknown group | "References unknown groups" | Verify group name is standard or follows `CA-EXC-*` pattern |

## Integration Points

### Pre-deployment Validation
The `Deploy-CAPolicies.ps1` script can be enhanced to run this validation before deployment:
```powershell
& .\src\models\Validate-Policies.ps1 -Strict
if ($LASTEXITCODE -ne 0) {
    Write-Error "Policy validation failed. Fix errors before deploying."
    exit 1
}
```

### IDE Support
VS Code users can enable JSON Schema validation:
1. Install the "JSON" extension (usually built-in)
2. Add to `.vscode/settings.json`:
```json
{
  "json.schemas": [
    {
      "fileMatch": ["policies/**/*.json"],
      "url": "./policies/schema/policy-schema.json"
    }
  ]
}
```

## Future Enhancements

- [ ] Catalog consistency checks (verify catalog.md matches JSON files)
- [ ] License requirement validation (P1 vs P2)
- [ ] Policy equivalence linting
- [ ] Automated fixes (--fix flag)
- [ ] Add to CI/CD pipeline
- [ ] HTML report generation

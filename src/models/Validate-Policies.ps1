<#
.SYNOPSIS
    Validates CA policy definitions against schema and safety rules.

.DESCRIPTION
    Performs comprehensive validation of all policy files including:
    - JSON schema compliance
    - Safety rules (break-glass exclusions, no hardcoded IDs)
    - ID format and uniqueness
    - Tier/folder placement consistency
    - File naming conventions

.PARAMETER PolicyPath
    Root path to policies directory. Default: policies/

.PARAMETER Strict
    Fail on warnings, not just errors.

.PARAMETER SchemaPath
    Path to JSON schema file. Default: policies/schema/policy-schema.json

.EXAMPLE
    .\Validate-Policies.ps1
    .\Validate-Policies.ps1 -PolicyPath ./policies -Strict
    .\Validate-Policies.ps1 -VerboseOutput

.OUTPUTS
    Returns custom object with validation results and exit code (0 = pass, 1 = fail)
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$PolicyPath = "policies",
    
    [Parameter(Mandatory = $false)]
    [string]$SchemaPath = "policies/schema/policy-schema.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$Strict,
    
    [Parameter(Mandatory = $false)]
    [switch]$VerboseOutput
)

$ErrorActionPreference = 'Continue'
$script:ErrorCount = 0
$script:WarningCount = 0
$script:ValidPolicies = @()
$script:AllPolicies = @()
$script:IdIndex = @{}

# Known standard groups
$StandardGroups = @(
    'CA-BreakGlass-Exclude',
    'CA-Tier-Baseline',
    'CA-Tier-P1-Managed',
    'CA-Tier-Frontline',
    'CA-Tier-E5',
    'CA-Admins',
    'CA-Pilot'
)

# Expected tier-to-folder mapping
$TierFolderMap = @{
    'baseline'  = 'baseline'
    'managed'   = 'managed'
    'frontline' = 'frontline'
    'e5'        = 'e5'
}

function Write-ValidationError {
    param([string]$Message, [string]$File)
    $prefix = if ($File) { "[$File]" } else { "[GENERAL]" }
    Write-Host "  [ERROR] $prefix $Message" -ForegroundColor Red
    $script:ErrorCount++
}

function Write-ValidationWarning {
    param([string]$Message, [string]$File)
    $prefix = if ($File) { "[$File]" } else { "[GENERAL]" }
    Write-Host "  [WARNING] $prefix $Message" -ForegroundColor Yellow
    $script:WarningCount++
}

function Write-ValidationPass {
    param([string]$Message, [string]$File)
    $prefix = if ($File) { "[$File]" } else { "[GENERAL]" }
    if ($VerboseOutput) {
        Write-Host "  [PASS] $prefix $Message" -ForegroundColor Green
    }
}

function Test-JsonAgainstSchema {
    param(
        [object]$JsonObject,
        [string]$SchemaPath,
        [string]$FilePath
    )
    
    if (-not (Test-Path $SchemaPath)) {
        Write-ValidationWarning "Schema file not found: $SchemaPath" $FilePath
        return $true
    }
    
    try {
        $schema = Get-Content $SchemaPath | ConvertFrom-Json
        
        # Basic schema validation checks
        $requiredFields = $schema.required
        foreach ($field in $requiredFields) {
            if ([string]::IsNullOrEmpty($JsonObject.$field)) {
                Write-ValidationError "Missing required field: $field" $FilePath
                return $false
            }
        }
        
        # Validate ID format
        if (-not ($JsonObject.id -match '^CA-[A-Z]{2}-[0-9]{3}$')) {
            Write-ValidationError "Invalid ID format (expect CA-XX-NNN): $($JsonObject.id)" $FilePath
            return $false
        }
        
        # Validate tier value
        if ($JsonObject.tier -notin @('baseline', 'managed', 'frontline', 'e5')) {
            Write-ValidationError "Invalid tier: $($JsonObject.tier)" $FilePath
            return $false
        }
        
        # Validate role template IDs if present
        if ($null -ne $JsonObject.target.includeRoleTemplateIds) {
            foreach ($rtId in $JsonObject.target.includeRoleTemplateIds) {
                if (-not ($rtId -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) {
                    Write-ValidationWarning "Invalid role template ID format: $rtId" $FilePath
                }
            }
        }
        
        Write-ValidationPass "Schema structure valid" $FilePath
        return $true
    }
    catch {
        Write-ValidationError "Schema validation failed: $($_.Exception.Message)" $FilePath
        return $false
    }
}

function Test-SafetyRules {
    param(
        [object]$Policy,
        [string]$FilePath
    )
    
    $isValid = $true
    
    $isAgentIdentityPolicy = $false
    if ($null -ne $Policy.conditions.clientApplications.includeAgentIdServicePrincipals) {
        $isAgentIdentityPolicy = $true
    }

    # Rule 1: Break-glass exclusion must be present for user-scoped policies
    $hasBreakGlass = $false
    
    # Check in conditions.users.excludeGroups (by name or ID reference)
    if ($null -ne $Policy.conditions.users.excludeGroups) {
        if ('CA-BreakGlass-Exclude' -in $Policy.conditions.users.excludeGroups -or
            $Policy.conditions.users.excludeGroups -match '.*BreakGlass.*') {
            $hasBreakGlass = $true
        }
    }
    
    # Check in target.excludeGroupNames
    if ($null -ne $Policy.target.excludeGroupNames) {
        if ('CA-BreakGlass-Exclude' -in $Policy.target.excludeGroupNames) {
            $hasBreakGlass = $true
        }
    }
    
    if ($isAgentIdentityPolicy) {
        Write-ValidationPass "Break-glass exclusion not required for agent-identity-scoped policy" $FilePath
    }
    elseif (-not $hasBreakGlass) {
        Write-ValidationError "Missing break-glass exclusion (CA-BreakGlass-Exclude)" $FilePath
        $isValid = $false
    }
    else {
        Write-ValidationPass "Break-glass exclusion present" $FilePath
    }
    
    # Rule 2: No hardcoded tenant IDs (common patterns)
    $policyJson = $Policy | ConvertTo-Json -Depth 10
    if ($policyJson -match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') {
        # Check if it's a role template ID or other known safe UUID
        $suspiciousUuids = @()
        
        [regex]::Matches($policyJson, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') | ForEach-Object {
            $uuid = $_.Value
            # Exclude known safe ones (role template IDs)
            if ($uuid -notin $Policy.target.includeRoleTemplateIds -and 
                $uuid -notin $Policy.target.excludeRoleTemplateIds) {
                $suspiciousUuids += $uuid
            }
        }
        
        if ($suspiciousUuids.Count -gt 0) {
            Write-ValidationWarning "Found UUIDs that may be hardcoded IDs (verify they're not tenant-specific): $($suspiciousUuids -join ', ')" $FilePath
        }
    }
    
    # Rule 3: report-only default (if policy has state/enabled field, warn if not report-only)
    if ($null -ne $Policy.state -and $Policy.state -ne 'reportOnly') {
        Write-ValidationWarning "Policy state is not reportOnly: $($Policy.state)" $FilePath
    }
    
    return $isValid
}

function Test-FileNaming {
    param(
        [string]$FilePath,
        [object]$Policy
    )
    
    $filename = Split-Path -Leaf $FilePath
    $expectedPattern = "$($Policy.id)\..*\.json"
    
    if ($filename -match $expectedPattern) {
        Write-ValidationPass "Filename follows naming convention" $FilePath
        return $true
    }
    else {
        Write-ValidationWarning "Filename doesn't match expected pattern (CA-XX-NNN.*.json): $filename" $FilePath
        return $false
    }
}

function Test-TierPlacement {
    param(
        [string]$FilePath,
        [object]$Policy
    )
    
    $tier = $Policy.tier.ToLower()
    $expectedFolder = $TierFolderMap[$tier]
    
    if ($FilePath -match "(/$expectedFolder/|\\$expectedFolder\\)") {
        Write-ValidationPass "Tier placement correct ($tier) folder" $FilePath
        return $true
    }
    else {
        Write-ValidationError "Tier placement incorrect: $tier policy in wrong folder" $FilePath
        return $false
    }
}

function Test-GroupReferences {
    param(
        [object]$Policy,
        [string]$FilePath
    )
    
    $isValid = $true
    $unknownGroups = @()
    
    # Check includeGroupNames
    if ($null -ne $Policy.target.includeGroupNames) {
        foreach ($group in $Policy.target.includeGroupNames) {
            if ($group -notin $StandardGroups -and -not ($group -match '^CA-EXC-')) {
                $unknownGroups += $group
            }
        }
    }
    
    # Check excludeGroupNames
    if ($null -ne $Policy.target.excludeGroupNames) {
        foreach ($group in $Policy.target.excludeGroupNames) {
            if ($group -notin $StandardGroups -and -not ($group -match '^CA-EXC-')) {
                $unknownGroups += $group
            }
        }
    }
    
    if ($unknownGroups.Count -gt 0) {
        Write-ValidationWarning "References unknown groups (verify they exist): $($unknownGroups -join ', ')" $FilePath
    }
    
    return $isValid
}

# Main validation logic
function Invoke-PolicyValidation {
    Write-Host ""
    Write-Host "Policy Validation Report" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    # Find all policy files
    $policyFiles = @()
    if (Test-Path $PolicyPath -PathType Container) {
        $policyFiles = Get-ChildItem -Path $PolicyPath -Filter "CA-*.json" -Recurse
    }
    else {
        Write-ValidationError "Policy path not found: $PolicyPath"
        return @{
            Success = $false
            Errors = $script:ErrorCount
            Warnings = $script:WarningCount
        }
    }
    
    if ($policyFiles.Count -eq 0) {
        Write-ValidationWarning "No policy files found in $PolicyPath"
    }
    
    Write-Host "Found $($policyFiles.Count) policy file(s)"
    Write-Host ""
    
    # Load schema
    $schema = $null
    if (Test-Path $SchemaPath) {
        try {
            $schema = Get-Content $SchemaPath | ConvertFrom-Json
            Write-Host "Schema loaded: $SchemaPath" -ForegroundColor Green
        }
        catch {
            Write-ValidationError "Failed to load schema: $($_.Exception.Message)"
        }
    }
    Write-Host ""
    
    # Validate each file
    foreach ($file in $policyFiles) {
        $relativePath = (Resolve-Path $file.FullName -Relative) -replace '^\.\\', ''
        Write-Host "Validating: $relativePath"
        
        try {
            $policy = Get-Content $file.FullName | ConvertFrom-Json
            
            $script:AllPolicies += $policy
            
            # Run validation checks
            $schemaValid = Test-JsonAgainstSchema -JsonObject $policy -SchemaPath $SchemaPath -FilePath $relativePath
            $safetyValid = Test-SafetyRules -Policy $policy -FilePath $relativePath
            $fileNameValid = Test-FileNaming -FilePath $relativePath -Policy $policy
            $tierValid = Test-TierPlacement -FilePath $relativePath -Policy $policy
            Test-GroupReferences -Policy $policy -FilePath $relativePath | Out-Null
            
            if ($schemaValid -and $safetyValid -and $fileNameValid -and $tierValid) {
                $script:ValidPolicies += $policy
                Write-Host "  [PASS]" -ForegroundColor Green
            }
            
            # Track ID for uniqueness check
            if ($null -ne $policy.id) {
                if ($script:IdIndex.ContainsKey($policy.id)) {
                    Write-ValidationError "Duplicate policy ID: $($policy.id)" $relativePath
                }
                else {
                    $script:IdIndex[$policy.id] = $relativePath
                }
            }
        }
        catch {
            Write-ValidationError "Failed to parse JSON: $($_.Exception.Message)" $relativePath
        }
        
        Write-Host ""
    }
    
    # Summary report
    Write-Host "Validation Summary" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Policies processed: $($policyFiles.Count)"
    Write-Host "Policies valid: $($script:ValidPolicies.Count)"
    Write-Host "Errors: $($script:ErrorCount)" -ForegroundColor $(if ($script:ErrorCount -gt 0) { 'Red' } else { 'Green' })
    Write-Host "Warnings: $($script:WarningCount)" -ForegroundColor $(if ($script:WarningCount -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host ""
    
    $hasErrors = $script:ErrorCount -gt 0
    $hasWarnings = $script:WarningCount -gt 0 -and $Strict
    $exitCode = $(if ($hasErrors -or $hasWarnings) { 1 } else { 0 })
    
    if ($exitCode -eq 0) {
        Write-Host "[PASS] All validation checks passed" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] Validation failed" -ForegroundColor Red
    }
    Write-Host ""
    
    return @{
        Success = ($exitCode -eq 0)
        ErrorCount = $script:ErrorCount
        WarningCount = $script:WarningCount
        ValidPolicies = $script:ValidPolicies
        AllPolicies = $script:AllPolicies
        ExitCode = $exitCode
    }
}

# Execute validation
$result = Invoke-PolicyValidation

exit $result.ExitCode

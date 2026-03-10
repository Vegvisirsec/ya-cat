[CmdletBinding()]
param(
  [ValidateSet('Evaluate','Deploy','Remove','Compare')] [string]$Mode = 'Evaluate',
  [string]$EnvFile = '.env.local',
  [string]$PoliciesRoot = 'policies',
  [string]$BreakGlassGroupName = 'CA-BreakGlass-Exclude',
  [string]$ExclusionGroupsFile = 'groups/policy-exclusion-groups.json',
  [string]$DynamicGroupsFile = 'groups/dynamic-group-rules.json',
  [ValidateSet('baseline','managed','frontline','e5')] [string[]]$Tier,
  [string[]]$PolicyId,
  [ValidateSet('Csv','Html','Json')] [string]$ReportFormat = 'Csv',
  [string]$ReportPath,
  [string]$ExportFolder = '',
  [string]$LogPath = '',
  [switch]$ContinueOnError,
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$script:RunLogPath = $null

# Source shared authentication module
$authModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'common' | Join-Path -ChildPath 'Authentication.ps1'
. $authModulePath

$script:ConditionalAccessApiBase = 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies'

function Show-TierSelectionMenu {
  param()
  
  Write-Host "`n=== Tier Selection Menu ===" -ForegroundColor Cyan
  Write-Host "Select which tiers to deploy (or press Enter for all):`n"
  Write-Host "  [0] All tiers (baseline, managed, frontline, e5)" -ForegroundColor Green
  Write-Host "  [1] Baseline only"
  Write-Host "  [2] Managed only"
  Write-Host "  [3] Frontline only"
  Write-Host "  [4] E5 only"
  Write-Host "  [5] Custom selection"
  Write-Host ""
  
  $choice = Read-Host "Enter your choice (0-5, or press Enter for all)"
  
  if ([string]::IsNullOrWhiteSpace($choice) -or $choice -eq "0") {
    return @('baseline','managed','frontline','e5')
  }
  
  switch ($choice) {
    "1" { return @('baseline') }
    "2" { return @('managed') }
    "3" { return @('frontline') }
    "4" { return @('e5') }
    "5" {
      Write-Host "`nSelect multiple tiers (comma-separated): baseline, managed, frontline, e5"
      $custom = Read-Host "Enter tiers"
      $selectedTiers = @($custom -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -in @('baseline','managed','frontline','e5') })
      if ($selectedTiers.Count -eq 0) {
        Write-Host "No valid tiers selected. Using all tiers." -ForegroundColor Yellow
        return @('baseline','managed','frontline','e5')
      }
      return $selectedTiers
    }
    default {
      Write-Host "Invalid choice. Using all tiers." -ForegroundColor Yellow
      return @('baseline','managed','frontline','e5')
    }
  }
}

function Initialize-RunLog {
  param([string]$Path, [string]$ModeName)
  if ([string]::IsNullOrWhiteSpace($Path)) {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Path = Join-Path -Path 'output' -ChildPath "ca-$($ModeName.ToLower())-log-$ts.txt"
  }
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $script:RunLogPath = $Path
  Set-Content -Path $script:RunLogPath -Value ""
}

function Write-RunLog {
  param(
    [ValidateSet('INFO','WARN','ERROR')] [string]$Level,
    [string]$Message
  )
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 's'), $Level, $Message
  Add-Content -Path $script:RunLogPath -Value $line
  Write-Host $line
}

function Load-EnvFile {
  param([string]$Path)
  if (-not (Test-Path $Path)) { throw "Env file not found: $Path" }

  Get-Content $Path | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    $k, $v = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), 'Process')
  }
}

function Get-RequiredEnv {
  param([string]$Name)
  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) { throw "Missing required env var: $Name" }
  return $value
}

function ConvertTo-Hashtable {
  param($InputObject)

  if ($null -eq $InputObject) { return $null }

  if ($InputObject -is [System.Collections.IDictionary]) {
    $h = @{}
    foreach ($k in $InputObject.Keys) {
      $h[$k] = ConvertTo-Hashtable -InputObject $InputObject[$k]
    }
    return $h
  }

  if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
    $list = @()
    foreach ($item in $InputObject) {
      $list += ,(ConvertTo-Hashtable -InputObject $item)
    }
    return ,$list
  }

  if ($InputObject -is [psobject] -and $InputObject.PSObject.Properties.Count -gt 0) {
    $h = @{}
    foreach ($p in $InputObject.PSObject.Properties) {
      $h[$p.Name] = ConvertTo-Hashtable -InputObject $p.Value
    }
    return $h
  }

  return $InputObject
}


function Invoke-Graph {
  param(
    [ValidateSet('GET','POST','PATCH','DELETE')] [string]$Method,
    [string]$Uri,
    [hashtable]$Headers,
    $Body
  )

  $maxRetries = 5
  for ($attempt = 0; $attempt -le $maxRetries; $attempt++) {
    try {
      if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType 'application/json'
      }

      $jsonBody = $Body | ConvertTo-Json -Depth 30
      return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType 'application/json' -Body $jsonBody
    } catch {
      $msg = $_.Exception.Message
      $statusCode = $null
      $retryAfterSeconds = 5
      if ($_.Exception.Response) {
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
        try {
          $retryHeader = $_.Exception.Response.Headers['Retry-After']
          if ($retryHeader) { $retryAfterSeconds = [int]$retryHeader }
        } catch {}
      }

      if ($statusCode -eq 429 -and $attempt -lt $maxRetries) {
        Write-Host "Graph throttled (429). Waiting $retryAfterSeconds second(s) before retry $($attempt + 1)/$maxRetries..."
        Start-Sleep -Seconds $retryAfterSeconds
        continue
      }

      if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $bodyText = $reader.ReadToEnd()
        if ($bodyText) {
          throw "Graph request failed. Method=$Method Uri=$Uri Error=$msg Body=$bodyText"
        }
      }
      throw "Graph request failed. Method=$Method Uri=$Uri Error=$msg"
    }
  }
}

function Escape-ODataString {
  param([string]$Value)
  return $Value.Replace("'", "''")
}

function Get-GroupByName {
  param([string]$DisplayName, [hashtable]$Headers)

  $escaped = Escape-ODataString -Value $DisplayName
  $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$escaped'&`$select=id,displayName,description,groupTypes,membershipRule,membershipRuleProcessingState"
  $existing = Invoke-Graph -Method GET -Uri $uri -Headers $Headers -Body $null
  if ($existing.value.Count -gt 0) { return $existing.value[0] }
  return $null
}

function Remove-GroupIfExists {
  param(
    [string]$DisplayName,
    [hashtable]$Headers
  )

  $existing = Get-GroupByName -DisplayName $DisplayName -Headers $Headers
  if ($null -eq $existing) {
    return $false
  }

  if ($WhatIf) {
    Write-RunLog -Level INFO -Message "[WhatIf] Would delete group: $DisplayName"
    return $true
  }

  Invoke-Graph -Method DELETE -Uri "https://graph.microsoft.com/v1.0/groups/$($existing.id)" -Headers $Headers -Body $null | Out-Null
  Write-RunLog -Level INFO -Message "Deleted group: $DisplayName"
  return $true
}

function Get-ExclusionGroupDefinitions {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return @()
  }

  $raw = Get-Content -Raw -Path $Path
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return @()
  }

  $arr = $raw | ConvertFrom-Json
  $defs = @()
  foreach ($d in $arr) {
    if ($d.name) {
      $defs += [pscustomobject]@{
        name = [string]$d.name
        description = [string]$d.description
      }
    }
  }
  return $defs
}

function Get-DynamicGroupDefinitions {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return @()
  }

  $raw = Get-Content -Raw -Path $Path
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return @()
  }

  $arr = $raw | ConvertFrom-Json
  $defs = @()
  foreach ($d in $arr) {
    if ($d.name -and $d.membershipRule) {
      $defs += [pscustomobject]@{
        name = [string]$d.name
        description = [string]$d.description
        membershipRule = [string]$d.membershipRule
        membershipRuleProcessingState = $(if ([string]::IsNullOrWhiteSpace([string]$d.membershipRuleProcessingState)) { 'On' } else { [string]$d.membershipRuleProcessingState })
        enforce = [bool]$d.enforce
      }
    }
  }
  return $defs
}

function Ensure-Group {
  param(
    [string]$DisplayName,
    [hashtable]$Headers,
    [string]$Description,
    $DynamicDefinition
  )

  $existing = Get-GroupByName -DisplayName $DisplayName -Headers $Headers
  if ($null -ne $existing) {
    if (-not $WhatIf) {
      $patch = @{}
      if (-not [string]::IsNullOrWhiteSpace($Description) -and [string]$existing.description -ne $Description) {
        $patch.description = $Description
      }

      if ($null -ne $DynamicDefinition) {
        $types = @()
        if ($existing.groupTypes) { $types = @($existing.groupTypes) }
        if ($types -notcontains 'DynamicMembership') {
          $types += 'DynamicMembership'
          $patch.groupTypes = @($types)
        }
        if ([string]$existing.membershipRule -ne [string]$DynamicDefinition.membershipRule) {
          $patch.membershipRule = [string]$DynamicDefinition.membershipRule
        }
        if ([string]$existing.membershipRuleProcessingState -ne [string]$DynamicDefinition.membershipRuleProcessingState) {
          $patch.membershipRuleProcessingState = [string]$DynamicDefinition.membershipRuleProcessingState
        }
      }

      if ($patch.Keys.Count -gt 0) {
        Invoke-Graph -Method PATCH -Uri "https://graph.microsoft.com/v1.0/groups/$($existing.id)" -Headers $Headers -Body $patch | Out-Null
        Write-Host "Updated group settings: $DisplayName"
      }
    }
    return $existing
  }

  $mailNick = ($DisplayName -replace '[^a-zA-Z0-9]', '').ToLower()
  if ([string]::IsNullOrWhiteSpace($mailNick)) { $mailNick = 'group' }
  if ($mailNick.Length -gt 64) { $mailNick = $mailNick.Substring(0,64) }

  $body = @{
    displayName     = $DisplayName
    description     = $(if ([string]::IsNullOrWhiteSpace($Description)) { "Created by CA policy deployment script" } else { $Description })
    mailEnabled     = $false
    mailNickname    = $mailNick
    securityEnabled = $true
  }

  if ($null -ne $DynamicDefinition) {
    $body.groupTypes = @('DynamicMembership')
    $body.membershipRule = [string]$DynamicDefinition.membershipRule
    $body.membershipRuleProcessingState = [string]$DynamicDefinition.membershipRuleProcessingState
  }

  if ($WhatIf) {
    Write-Host "[WhatIf] Would create group: $DisplayName"
    return [pscustomobject]@{ id = "WHATIF-$DisplayName"; displayName = $DisplayName }
  }

  $created = Invoke-Graph -Method POST -Uri 'https://graph.microsoft.com/v1.0/groups' -Headers $Headers -Body $body
  Write-Host "Created group: $($created.displayName)"
  return $created
}

function Get-AuthenticationStrengthMap {
  param([hashtable]$Headers)

  $uri = "https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationStrength/policies?`$select=id,displayName,policyType"
  $resp = Invoke-Graph -Method GET -Uri $uri -Headers $Headers -Body $null

  $map = @{}
  foreach ($item in $resp.value) {
    $map[$item.displayName] = $item.id
  }
  return $map
}

function Convert-TargetToUsersCondition {
  param(
    [hashtable]$Policy,
    [hashtable]$GroupMap,
    [string]$BreakGlassId
  )

  $users = @{}
  if ($Policy.conditions -and $Policy.conditions.users) {
    $users = @{} + $Policy.conditions.users
  }

  if ($Policy.conditions -and $Policy.conditions.clientApplications -and $Policy.conditions.clientApplications.includeAgentIdServicePrincipals) {
    return $users
  }

  $includeNames = @()
  if ($Policy.target -and $Policy.target.includeGroupNames) {
    $includeNames += @($Policy.target.includeGroupNames)
  }
  if ($users.includeGroupNames) {
    $includeNames += @($users.includeGroupNames)
    $users.Remove('includeGroupNames') | Out-Null
  }

  if ($includeNames.Count -gt 0) {
    $includeIds = @()
    foreach ($n in $includeNames) {
      if (-not $GroupMap.ContainsKey($n) -or [string]::IsNullOrWhiteSpace([string]$GroupMap[$n])) {
        throw "Required group not found for policy '$($Policy.displayName)': $n"
      }
      $includeIds += $GroupMap[$n]
    }
    $users.includeGroups = @($includeIds)
  }

  $includeRoleIds = @()
  if ($Policy.target -and $Policy.target.includeRoleTemplateIds) {
    $includeRoleIds += @($Policy.target.includeRoleTemplateIds)
  }
  if ($users.includeRoleTemplateIds) {
    $includeRoleIds += @($users.includeRoleTemplateIds)
    $users.Remove('includeRoleTemplateIds') | Out-Null
  }
  if ($users.includeRoles) {
    $includeRoleIds += @($users.includeRoles)
    $users.Remove('includeRoles') | Out-Null
  }
  if ($includeRoleIds.Count -gt 0) {
    $users.includeRoles = @($includeRoleIds | Select-Object -Unique)
    # Role-targeted policies must not implicitly include all users.
    $users.includeUsers = @()
    if ($users.ContainsKey('includeGuestsOrExternalUsers')) {
      $users.Remove('includeGuestsOrExternalUsers') | Out-Null
    }
    if ($includeNames.Count -eq 0) {
      # Clear stale includeGroups when switching policy targeting from groups to roles.
      $users.includeGroups = @()
    }
  }

  $excludeNames = @()
  if ($Policy.target -and $Policy.target.excludeGroupNames) {
    $excludeNames += @($Policy.target.excludeGroupNames)
  }
  if ($users.excludeGroupNames) {
    $excludeNames += @($users.excludeGroupNames)
    $users.Remove('excludeGroupNames') | Out-Null
  }

  $resolvedExcludes = @()
  if ($excludeNames.Count -gt 0) {
    foreach ($n in $excludeNames) {
      if (-not $GroupMap.ContainsKey($n) -or [string]::IsNullOrWhiteSpace([string]$GroupMap[$n])) {
        throw "Excluded group not found for policy '$($Policy.displayName)': $n"
      }
      $resolvedExcludes += $GroupMap[$n]
    }
  }
  if ($BreakGlassId -and ($resolvedExcludes -notcontains $BreakGlassId)) {
    $resolvedExcludes += $BreakGlassId
  }
  if ($resolvedExcludes.Count -gt 0) {
    $users.excludeGroups = @($resolvedExcludes)
  }

  $excludeRoleIds = @()
  if ($Policy.target -and $Policy.target.excludeRoleTemplateIds) {
    $excludeRoleIds += @($Policy.target.excludeRoleTemplateIds)
  }
  if ($users.excludeRoleTemplateIds) {
    $excludeRoleIds += @($users.excludeRoleTemplateIds)
    $users.Remove('excludeRoleTemplateIds') | Out-Null
  }
  if ($users.excludeRoles) {
    $excludeRoleIds += @($users.excludeRoles)
    $users.Remove('excludeRoles') | Out-Null
  }
  if ($excludeRoleIds.Count -gt 0) {
    $users.excludeRoles = @($excludeRoleIds | Select-Object -Unique)
  }

  return $users
}

function Resolve-PolicyPayload {
  param(
    [hashtable]$Policy,
    [hashtable]$GroupMap,
    [string]$BreakGlassId,
    [hashtable]$AuthStrengthMap
  )

  $conditions = @{} + $Policy.conditions
  $resolvedUsers = Convert-TargetToUsersCondition -Policy $Policy -GroupMap $GroupMap -BreakGlassId $BreakGlassId
  if ($resolvedUsers.Keys.Count -gt 0) {
    $conditions.users = $resolvedUsers
  } elseif ($conditions.ContainsKey('users')) {
    $conditions.Remove('users') | Out-Null
  }

  $payload = [ordered]@{
    displayName = $Policy.displayName
    state       = 'enabledForReportingButNotEnforced'
    conditions  = $conditions
  }

  if ($Policy.grantControls) {
    $grantControls = @{} + $Policy.grantControls
    if (-not $grantControls.ContainsKey('builtInControls')) {
      # Explicitly clear stale built-in controls on PATCH when policy uses only auth strength.
      $grantControls.builtInControls = @()
    }
    if (-not $grantControls.ContainsKey('termsOfUse')) {
      $grantControls.termsOfUse = @()
    }
    if ($grantControls.authenticationStrengthPolicyName) {
      $name = [string]$grantControls.authenticationStrengthPolicyName
      if (-not $AuthStrengthMap.ContainsKey($name)) {
        throw "Authentication strength policy not found: $name"
      }
      $grantControls.authenticationStrength = @{ id = $AuthStrengthMap[$name] }
      $grantControls.Remove('authenticationStrengthPolicyName') | Out-Null
    }
    $payload.grantControls = $grantControls
  }

  if ($Policy.sessionControls) {
    $payload.sessionControls = $Policy.sessionControls
  }

  return $payload
}

function Resolve-ExpectedBehaviorPayload {
  param(
    [hashtable]$Policy,
    [hashtable]$AuthStrengthMap
  )

  $conditions = @{}
  if ($Policy.conditions) { $conditions = @{} + $Policy.conditions }
  if ($conditions.ContainsKey('users')) {
    # Evaluate by policy behavior and controls, not tenant-specific target groups.
    $conditions.Remove('users') | Out-Null
  }

  $payload = [ordered]@{
    displayName = $Policy.displayName
    state       = 'enabledForReportingButNotEnforced'
    conditions  = $conditions
  }

  if ($Policy.grantControls) {
    $grantControls = @{} + $Policy.grantControls
    if (-not $grantControls.ContainsKey('builtInControls')) { $grantControls.builtInControls = @() }
    if (-not $grantControls.ContainsKey('termsOfUse')) { $grantControls.termsOfUse = @() }
    if ($grantControls.authenticationStrengthPolicyName) {
      $name = [string]$grantControls.authenticationStrengthPolicyName
      if (-not $AuthStrengthMap.ContainsKey($name)) {
        throw "Authentication strength policy not found: $name"
      }
      $grantControls.authenticationStrength = @{ id = $AuthStrengthMap[$name] }
      $grantControls.Remove('authenticationStrengthPolicyName') | Out-Null
    }
    $payload.grantControls = $grantControls
  }

  if ($Policy.sessionControls) {
    $payload.sessionControls = $Policy.sessionControls
  }

  return $payload
}

function Get-PolicyByName {
  param([string]$DisplayName, [hashtable]$Headers, [string]$PolicyId)

  $escapedName = Escape-ODataString -Value $DisplayName
  $findUri = "${script:ConditionalAccessApiBase}?`$filter=displayName eq '$escapedName'&`$select=id,displayName,state"
  $existing = Invoke-Graph -Method GET -Uri $findUri -Headers $Headers -Body $null
  if ($existing.value.Count -gt 0) { return $existing.value[0] }

  if (-not [string]::IsNullOrWhiteSpace($PolicyId)) {
    $prefix = Escape-ODataString -Value "$PolicyId - "
    $fallbackUri = "${script:ConditionalAccessApiBase}?`$filter=startsWith(displayName,'$prefix')&`$select=id,displayName,state"
    $fallback = Invoke-Graph -Method GET -Uri $fallbackUri -Headers $Headers -Body $null
    if ($fallback.value.Count -gt 0) { return $fallback.value[0] }
  }

  return $null
}

function Get-PolicyDetails {
  param([string]$Id, [hashtable]$Headers)
  return Invoke-Graph -Method GET -Uri "$script:ConditionalAccessApiBase/$Id" -Headers $Headers -Body $null
}

function Get-AllPolicies {
  param([hashtable]$Headers)

  $uri = $script:ConditionalAccessApiBase
  $all = @()
  while ($uri) {
    $resp = Invoke-Graph -Method GET -Uri $uri -Headers $Headers -Body $null
    if ($resp.value) {
      foreach ($p in $resp.value) { $all += ,(ConvertTo-Hashtable -InputObject $p) }
    }
    $uri = $resp.'@odata.nextLink'
  }
  return ,$all
}

function Get-ScalarList {
  param($Value)
  if ($null -eq $Value) { return @() }
  $items = @()
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    foreach ($i in $Value) { $items += [string]$i }
  } else {
    $items += [string]$Value
  }
  return @($items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function Get-PolicyFingerprint {
  param([hashtable]$Policy)

  $fp = [ordered]@{
    clientAppTypes = (Get-ScalarList -Value $Policy.conditions.clientAppTypes) -join ';'
    agentIdentities = ''
    includeApps = ''
    userActions = ''
    authFlow = ''
    signInRisk = (Get-ScalarList -Value $Policy.conditions.signInRiskLevels) -join ';'
    userRisk = (Get-ScalarList -Value $Policy.conditions.userRiskLevels) -join ';'
    includePlatforms = ''
    excludePlatforms = ''
    grantBuiltIn = ''
    grantOperator = ''
    authStrengthId = ''
    hasSessionRestriction = $false
  }

  if ($Policy.conditions -and $Policy.conditions.applications) {
    $fp.includeApps = (Get-ScalarList -Value $Policy.conditions.applications.includeApplications) -join ';'
    $fp.userActions = (Get-ScalarList -Value $Policy.conditions.applications.includeUserActions) -join ';'
  }
  if ($Policy.conditions -and $Policy.conditions.clientApplications) {
    $fp.agentIdentities = (Get-ScalarList -Value $Policy.conditions.clientApplications.includeAgentIdServicePrincipals) -join ';'
  }
  if ($Policy.conditions -and $Policy.conditions.authenticationFlows) {
    $fp.authFlow = [string]$Policy.conditions.authenticationFlows.transferMethods
  }
  if ($Policy.conditions -and $Policy.conditions.platforms) {
    $fp.includePlatforms = (Get-ScalarList -Value $Policy.conditions.platforms.includePlatforms) -join ';'
    $fp.excludePlatforms = (Get-ScalarList -Value $Policy.conditions.platforms.excludePlatforms) -join ';'
  }
  if ($Policy.grantControls) {
    $fp.grantBuiltIn = (Get-ScalarList -Value $Policy.grantControls.builtInControls) -join ';'
    $fp.grantOperator = [string]$Policy.grantControls.operator
    if ($Policy.grantControls.authenticationStrength) {
      $fp.authStrengthId = [string]$Policy.grantControls.authenticationStrength.id
    }
  }
  if ($Policy.sessionControls -and $Policy.sessionControls.applicationEnforcedRestrictions) {
    $fp.hasSessionRestriction = [bool]$Policy.sessionControls.applicationEnforcedRestrictions.isEnabled
  }

  return $fp
}

function Find-BestPolicyMatch {
  param(
    [hashtable]$ExpectedPayload,
    [array]$TenantPolicies
  )

  $expected = Get-PolicyFingerprint -Policy $ExpectedPayload
  $best = $null
  $bestScore = -1

  foreach ($candidate in $TenantPolicies) {
    $cand = Get-PolicyFingerprint -Policy $candidate
    $score = 0
    if ($cand.clientAppTypes -eq $expected.clientAppTypes) { $score++ }
    if ($cand.agentIdentities -eq $expected.agentIdentities) { $score++ }
    if ($cand.includeApps -eq $expected.includeApps) { $score++ }
    if ($cand.userActions -eq $expected.userActions) { $score++ }
    if ($cand.authFlow -eq $expected.authFlow) { $score++ }
    if ($cand.signInRisk -eq $expected.signInRisk) { $score++ }
    if ($cand.userRisk -eq $expected.userRisk) { $score++ }
    if ($cand.includePlatforms -eq $expected.includePlatforms) { $score++ }
    if ($cand.excludePlatforms -eq $expected.excludePlatforms) { $score++ }
    if ($cand.grantBuiltIn -eq $expected.grantBuiltIn) { $score++ }
    if ($cand.grantOperator -eq $expected.grantOperator) { $score++ }
    if ($cand.authStrengthId -eq $expected.authStrengthId) { $score++ }
    if ([bool]$cand.hasSessionRestriction -eq [bool]$expected.hasSessionRestriction) { $score++ }

    if ($score -gt $bestScore) {
      $bestScore = $score
      $best = $candidate
    }
  }

  return [pscustomobject]@{ policy = $best; score = $bestScore }
}

function Get-BehaviorMismatches {
  param(
    [hashtable]$ExpectedPolicy,
    [hashtable]$CandidatePolicy
  )

  $expected = Get-PolicyFingerprint -Policy $ExpectedPolicy
  $actual = Get-PolicyFingerprint -Policy $CandidatePolicy
  $issues = @()

  if ($expected.clientAppTypes -and $expected.clientAppTypes -ne $actual.clientAppTypes) { $issues += 'clientAppTypes differ' }
  if ($expected.agentIdentities -and $expected.agentIdentities -ne $actual.agentIdentities) { $issues += 'agent identities differ' }
  if ($expected.includeApps -and $expected.includeApps -ne $actual.includeApps) { $issues += 'included applications differ' }
  if ($expected.userActions -and $expected.userActions -ne $actual.userActions) { $issues += 'user actions differ' }
  if ($expected.authFlow -and $expected.authFlow -ne $actual.authFlow) { $issues += 'authentication flow differs' }
  if ($expected.signInRisk -and $expected.signInRisk -ne $actual.signInRisk) { $issues += 'sign-in risk condition differs' }
  if ($expected.userRisk -and $expected.userRisk -ne $actual.userRisk) { $issues += 'user risk condition differs' }
  if ($expected.includePlatforms -and $expected.includePlatforms -ne $actual.includePlatforms) { $issues += 'platform include differs' }
  if ($expected.excludePlatforms -and $expected.excludePlatforms -ne $actual.excludePlatforms) { $issues += 'platform exclude differs' }
  if ($expected.grantBuiltIn -ne $actual.grantBuiltIn) { $issues += 'grant built-in controls differ' }
  if ($expected.grantOperator -and $expected.grantOperator -ne $actual.grantOperator) { $issues += 'grant operator differs' }
  if ($expected.authStrengthId -and $expected.authStrengthId -ne $actual.authStrengthId) { $issues += 'authentication strength differs' }
  if ([bool]$expected.hasSessionRestriction -ne [bool]$actual.hasSessionRestriction) { $issues += 'session restriction differs' }

  return ,$issues
}

function Contains-Id {
  param($ArrayValue, [string]$Id)
  if ($null -eq $ArrayValue) { return $false }
  foreach ($item in $ArrayValue) {
    if ([string]$item -eq $Id) { return $true }
  }
  return $false
}

function Compare-PolicyForEvaluation {
  param(
    [hashtable]$ExpectedPayload,
    [hashtable]$ExistingPolicy,
    [string]$BreakGlassId
  )

  $issues = @()

  if ([string]$ExistingPolicy.state -ne 'enabledForReportingButNotEnforced') {
    $issues += 'Policy state is not report-only.'
  }

  $excludeGroups = $null
  if ($ExistingPolicy.conditions -and $ExistingPolicy.conditions.users) {
    $excludeGroups = $ExistingPolicy.conditions.users.excludeGroups
  }
  if (-not (Contains-Id -ArrayValue $excludeGroups -Id $BreakGlassId)) {
    $issues += 'Break-glass exclusion is missing.'
  }

  if ($ExpectedPayload.grantControls -and $ExpectedPayload.grantControls.authenticationStrength) {
    $expectedStrengthId = [string]$ExpectedPayload.grantControls.authenticationStrength.id
    $actualStrengthId = $null
    if ($ExistingPolicy.grantControls -and $ExistingPolicy.grantControls.authenticationStrength) {
      $actualStrengthId = [string]$ExistingPolicy.grantControls.authenticationStrength.id
    }
    if ([string]::IsNullOrWhiteSpace($actualStrengthId) -or $actualStrengthId -ne $expectedStrengthId) {
      $issues += 'Authentication strength does not match expected policy.'
    }
  }

  if ($ExpectedPayload.grantControls) {
    $expectedOperator = [string]$ExpectedPayload.grantControls.operator
    $actualOperator = ''
    if ($ExistingPolicy.grantControls) { $actualOperator = [string]$ExistingPolicy.grantControls.operator }
    if ($expectedOperator -and $actualOperator -and $expectedOperator -ne $actualOperator) {
      $issues += "Grant control operator mismatch (expected=$expectedOperator actual=$actualOperator)."
    }

    $expectedBuiltIn = Get-ScalarList -Value $ExpectedPayload.grantControls.builtInControls
    $actualBuiltIn = @()
    if ($ExistingPolicy.grantControls) { $actualBuiltIn = Get-ScalarList -Value $ExistingPolicy.grantControls.builtInControls }
    $exp = ($expectedBuiltIn | Sort-Object) -join ';'
    $act = ($actualBuiltIn | Sort-Object) -join ';'
    if ($exp -ne $act) {
      $issues += "Built-in controls mismatch (expected='$exp' actual='$act')."
    }
  }

  return ,$issues
}

function Get-ToolkitPolicies {
  param([string]$PoliciesRoot)
  
  $policies = @()
  $files = Get-ChildItem -Path $PoliciesRoot -Recurse -File -Filter '*.json' | Sort-Object FullName
  
  foreach ($file in $files) {
    try {
      $raw = Get-Content -Raw -Path $file.FullName
      $obj = ConvertTo-Hashtable -InputObject ($raw | ConvertFrom-Json)
      if ($obj.id -and $obj.displayName) {
        $policies += $obj
      }
    } catch {
      Write-Host "Warning: Failed to parse policy file $($file.FullName): $($_.Exception.Message)" -ForegroundColor Yellow
    }
  }
  
  return ,$policies
}

function Get-TenantPoliciesFromExport {
  param([string]$ExportFolder)
  
  $policies = @()
  
  # Try single file  
  $singleFile = Join-Path $ExportFolder 'policies.json'
  if (Test-Path $singleFile) {
    try {
      $content = Get-Content -Raw -Path $singleFile
      $items = $content | ConvertFrom-Json
      if ($items -is [array]) {
        $policies = $items | ForEach-Object { ConvertTo-Hashtable -InputObject $_ }
      } else {
        $policies = @(ConvertTo-Hashtable -InputObject $items)
      }
      return ,$policies
    } catch {
      Write-Host "Warning: Failed to parse $singleFile" -ForegroundColor Yellow
    }
  }
  
  # Try individual files
  $jsonFiles = Get-ChildItem -Path $ExportFolder -File -Filter '*.json' -ErrorAction SilentlyContinue
  foreach ($file in $jsonFiles) {
    if ($file.Name -eq 'manifest.json' -or $file.Name -eq 'policies.json') { continue }
    try {
      $obj = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json
      $policies += ConvertTo-Hashtable -InputObject $obj
    } catch {
      Write-Host "Warning: Failed to parse policy file $($file.Name)" -ForegroundColor Yellow
    }
  }
  
  return ,$policies
}

function Calculate-CoverageScore {
  param(
    [hashtable]$ToolkitPolicy,
    [hashtable]$TenantPolicy
  )
  
  $toolkitFp = Get-PolicyFingerprint -Policy $ToolkitPolicy
  $tenantFp = Get-PolicyFingerprint -Policy $TenantPolicy
  
  $totalAttributes = 13
  $matches = 0
  
  if ($tenantFp.clientAppTypes -eq $toolkitFp.clientAppTypes) { $matches++ }
  if ($tenantFp.agentIdentities -eq $toolkitFp.agentIdentities) { $matches++ }
  if ($tenantFp.includeApps -eq $toolkitFp.includeApps) { $matches++ }
  if ($tenantFp.userActions -eq $toolkitFp.userActions) { $matches++ }
  if ($tenantFp.authFlow -eq $toolkitFp.authFlow) { $matches++ }
  if ($tenantFp.signInRisk -eq $toolkitFp.signInRisk) { $matches++ }
  if ($tenantFp.userRisk -eq $toolkitFp.userRisk) { $matches++ }
  if ($tenantFp.includePlatforms -eq $toolkitFp.includePlatforms) { $matches++ }
  if ($tenantFp.excludePlatforms -eq $toolkitFp.excludePlatforms) { $matches++ }
  if ($tenantFp.grantBuiltIn -eq $toolkitFp.grantBuiltIn) { $matches++ }
  if ($tenantFp.grantOperator -eq $toolkitFp.grantOperator) { $matches++ }
  if ($tenantFp.authStrengthId -eq $toolkitFp.authStrengthId) { $matches++ }
  if ([bool]$tenantFp.hasSessionRestriction -eq [bool]$toolkitFp.hasSessionRestriction) { $matches++ }
  
  $percentage = [math]::Round(($matches / $totalAttributes) * 100, 0)
  
  return @{
    percentage = $percentage
    matches = $matches
    total = $totalAttributes
    tenantPolicy = $TenantPolicy
  }
}



function Write-RunReport {
  param(
    [array]$Rows,
    [string]$Format,
    [string]$Path
  )

  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  if ($Format -eq 'Csv') {
    $Rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
  } elseif ($Format -eq 'Json') {
    ($Rows | ConvertTo-Json -Depth 10) | Set-Content -Path $Path
  } else {
    $html = $Rows |
      Select-Object timestamp,mode,tier,id,displayName,status,action,issues |
      ConvertTo-Html -Title 'Conditional Access Policy Run Report' -PreContent '<h1>Conditional Access Policy Run Report</h1>' |
      Out-String
    Set-Content -Path $Path -Value $html
  }
}

Initialize-RunLog -Path $LogPath -ModeName $Mode
Write-RunLog -Level INFO -Message "Starting run. mode=$Mode envFile=$EnvFile whatIf=$($WhatIf.IsPresent) continueOnError=$($ContinueOnError.IsPresent)"

Load-EnvFile -Path $EnvFile

$tenantId = Get-RequiredEnv -Name 'TENANT_ID'
$clientId = Get-RequiredEnv -Name 'CLIENT_ID'
$clientSecret = Get-RequiredEnv -Name 'CLIENT_SECRET'
$scope = Get-RequiredEnv -Name 'GRAPH_SCOPE'

$token = Get-GraphToken -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret -Scope $scope
$headers = @{ Authorization = "Bearer $token" }

$groupNames = @(
  'CA-BreakGlass-Exclude',
  'CA-Tier-Baseline',
  'CA-Tier-P1-Managed',
  'CA-Tier-Frontline',
  'CA-Tier-E5',
  'CA-Admins',
  'CA-Pilot'
)

$groupDescriptions = @{}
$exclusionDefs = Get-ExclusionGroupDefinitions -Path $ExclusionGroupsFile
foreach ($d in $exclusionDefs) {
  if ($groupNames -notcontains $d.name) {
    $groupNames += $d.name
  }
  if (-not [string]::IsNullOrWhiteSpace($d.description)) {
    $groupDescriptions[$d.name] = $d.description
  }
}

$dynamicDefs = Get-DynamicGroupDefinitions -Path $DynamicGroupsFile
$dynamicDefMap = @{}
foreach ($d in $dynamicDefs) {
  if ($d.enforce) {
    $dynamicDefMap[$d.name] = $d
    if ($groupNames -notcontains $d.name) {
      $groupNames += $d.name
    }
    if (-not [string]::IsNullOrWhiteSpace($d.description)) {
      $groupDescriptions[$d.name] = $d.description
    }
  }
}

$groupMap = @{}
$missingGroups = @()
if ($Mode -eq 'Deploy') {
  foreach ($name in $groupNames) {
    try {
      $desc = $null
      if ($groupDescriptions.ContainsKey($name)) { $desc = [string]$groupDescriptions[$name] }
      $dyn = $null
      if ($dynamicDefMap.ContainsKey($name)) { $dyn = $dynamicDefMap[$name] }
      $g = Ensure-Group -DisplayName $name -Headers $headers -Description $desc -DynamicDefinition $dyn
      $groupMap[$name] = $g.id
      Write-RunLog -Level INFO -Message "Group ready: $name ($($g.id))"
    } catch {
      Write-RunLog -Level ERROR -Message "Failed to ensure group '$name': $($_.Exception.Message)"
      throw
    }
  }
}

$breakGlassId = $groupMap[$BreakGlassGroupName]

$authStrengthMap = Get-AuthenticationStrengthMap -Headers $headers

$policyFiles = Get-ChildItem -Path $PoliciesRoot -Recurse -File -Filter '*.json' | Sort-Object FullName
if ($policyFiles.Count -eq 0) { throw "No policy files found under $PoliciesRoot" }

$selectedTiers = @()
if (-not $Tier -or $Tier.Count -eq 0) {
  $selectedTiers = @(Show-TierSelectionMenu)
} else {
  $selectedTiers = @($Tier | ForEach-Object { $_.ToLower() })
}
$selectedIds = @()
if ($PolicyId -and $PolicyId.Count -gt 0) { $selectedIds = @($PolicyId | ForEach-Object { $_.ToUpper() }) }

$tenantPolicies = @()
if ($Mode -eq 'Evaluate') {
  $tenantPolicies = Get-AllPolicies -Headers $headers
}

$created = 0
$updated = 0
$removed = 0
$skipped = 0
$evaluated = 0
$covered = 0
$uncovered = 0
$errors = 0
$recommendations = @()
$results = @()
$now = (Get-Date).ToString('s')

# ===== COMPARE MODE HANDLER =====
if ($Mode -eq 'Compare') {
  try {
    Write-RunLog -Level INFO -Message "Loading toolkit policies..."
    $toolkitPolicies = Get-ToolkitPolicies -PoliciesRoot $PoliciesRoot
    Write-RunLog -Level INFO -Message "Loaded $($toolkitPolicies.Count) toolkit policies"

    Write-RunLog -Level INFO -Message "Loading tenant policies..."
    if ($ExportFolder -and (Test-Path $ExportFolder)) {
      $tenantPolicies = Get-TenantPoliciesFromExport -ExportFolder $ExportFolder
      Write-RunLog -Level INFO -Message "Loaded $($tenantPolicies.Count) tenant policies from export"
    } else {
      $tenantPolicies = Get-AllPolicies -Headers $headers
      Write-RunLog -Level INFO -Message "Loaded $($tenantPolicies.Count) tenant policies from Graph"
    }

    # Filter toolkit policies by tier/id if specified
    $policiesToCompare = $toolkitPolicies
    if ($selectedTiers.Count -gt 0) {
      $policiesToCompare = @($policiesToCompare | Where-Object { ([string]$_.tier).ToLower() -in $selectedTiers })
      Write-RunLog -Level INFO -Message "Filtered to $($policiesToCompare.Count) policies for selected tiers"
    }
    if ($selectedIds.Count -gt 0) {
      $policiesToCompare = @($policiesToCompare | Where-Object { ([string]$_.id).ToUpper() -in $selectedIds })
      Write-RunLog -Level INFO -Message "Filtered to $($policiesToCompare.Count) policies for selected IDs"
    }

    # Compare each toolkit policy against tenant policies
    foreach ($toolkitPolicy in $policiesToCompare) {
      try {
        $toolkitId = [string]$toolkitPolicy.id
        $toolkitName = [string]$toolkitPolicy.displayName
        $toolkitTier = [string]$toolkitPolicy.tier

        if ([string]::IsNullOrWhiteSpace($toolkitId) -or [string]::IsNullOrWhiteSpace($toolkitName)) {
          Write-RunLog -Level WARN -Message "Skipping malformed toolkit policy: missing id or displayName"
          $skipped++
          continue
        }

        # Prepare expected behavior payload (without tenant-specific targeting)
        $expected = Resolve-ExpectedBehaviorPayload -Policy $toolkitPolicy -AuthStrengthMap $authStrengthMap

        # Find best matching tenant policy
        $best = Find-BestPolicyMatch -ExpectedPayload $expected -TenantPolicies $tenantPolicies

        if ($null -eq $best.policy -or $best.score -lt 6) {
          # Uncovered: no similar policy found
          $uncovered++
          $exclusions = ''
          $results += [pscustomobject]@{
            timestamp = $now
            mode = $Mode
            tier = $toolkitTier
            id = $toolkitId
            displayName = $toolkitName
            status = 'Uncovered'
            action = 'Create policy'
            issues = 'No behaviorally similar policy found in tenant'
          }
          Write-RunLog -Level INFO -Message "[$toolkitId] UNCOVERED: No behavioral match found"
          continue
        }

        $candidate = ConvertTo-Hashtable -InputObject $best.policy
        $candidateName = [string]$candidate.displayName
        $scorePercentage = [math]::Round(($best.score / 12) * 100, 0)

        # Calculate coverage score
        $scoreResult = Calculate-CoverageScore -ToolkitPolicy $expected -TenantPolicy $candidate
        $coveragePercentage = $scoreResult.percentage

        # Determine coverage based on score threshold (>= 50% = covered)
        $isCovered = $coveragePercentage -ge 50
        $status = if ($isCovered) { 'Covered' } else { 'Uncovered' }

        if ($isCovered) {
          $covered++
        } else {
          $uncovered++
        }

        # Capture exclusions if present in matching tenant policy
        $exclusions = ''
        if ($candidate.conditions -and $candidate.conditions.users -and $candidate.conditions.users.excludeGroups) {
          $excludeNames = @($candidate.conditions.users.excludeGroups) | Select-Object -Unique
          if ($excludeNames.Count -gt 0) {
            $exclusions = "Excludes: $($excludeNames -join ', ')"
          }
        }

        $results += [pscustomobject]@{
          timestamp = $now
          mode = $Mode
          tier = $toolkitTier
          id = $toolkitId
          displayName = $toolkitName
          status = $status
          action = "Matched with: $candidateName ($coveragePercentage%)"
          issues = $exclusions
        }

        Write-RunLog -Level INFO -Message "[$toolkitId] $status ($coveragePercentage%): Matched with '$candidateName'"

      } catch {
        $errors++
        $msg = "Compare failed for policy '$($toolkitPolicy.displayName)': $($_.Exception.Message)"
        Write-RunLog -Level ERROR -Message $msg
        $results += [pscustomobject]@{
          timestamp = $now
          mode = $Mode
          tier = $toolkitPolicy.tier
          id = $toolkitPolicy.id
          displayName = $toolkitPolicy.displayName
          status = 'Error'
          action = 'Review error'
          issues = $msg
        }
        if (-not $ContinueOnError) {
          throw
        }
      }
    }

    Write-RunLog -Level INFO -Message "Compare complete: covered=$covered uncovered=$uncovered errors=$errors"

  } catch {
    $errors++
    $msg = "Compare mode failed: $($_.Exception.Message)"
    Write-RunLog -Level ERROR -Message $msg
    throw
  }
} else {
  # ===== ORIGINAL FOREACH LOOP FOR DEPLOY/EVALUATE/REMOVE MODES =====
  foreach ($file in $policyFiles) {
  try {
    $raw = Get-Content -Raw -Path $file.FullName
    $policy = ConvertTo-Hashtable -InputObject ($raw | ConvertFrom-Json)
    $hasUnresolvedPlaceholder = $raw -match '\{\{[A-Z0-9_\-]+\}\}'

    if ($selectedTiers.Count -gt 0 -and ($selectedTiers -notcontains ([string]$policy.tier).ToLower())) {
      $skipped++
      continue
    }

    if ($selectedIds.Count -gt 0 -and ($selectedIds -notcontains ([string]$policy.id).ToUpper())) {
      $skipped++
      continue
    }

    if ($Mode -ne 'Remove' -and $hasUnresolvedPlaceholder) {
      $skipped++
      $issues = 'Skipped due to unresolved placeholder values (for example {{...}}).'
      Write-RunLog -Level WARN -Message "Skipping policy '$($policy.displayName)': $issues"
      $results += [pscustomobject]@{
        timestamp = $now; mode = $Mode; tier = $policy.tier; id = $policy.id; displayName = $policy.displayName
        status = 'SkippedPrereq'; action = 'No action'; issues = $issues
      }
      continue
    }

    if ($Mode -eq 'Deploy') {
      $payload = Resolve-PolicyPayload -Policy $policy -GroupMap $groupMap -BreakGlassId $breakGlassId -AuthStrengthMap $authStrengthMap
      $existing = Get-PolicyByName -DisplayName $policy.displayName -Headers $headers -PolicyId $policy.id

      if ($null -ne $existing) {
        $id = $existing.id
        if ($WhatIf) {
          Write-RunLog -Level INFO -Message "[WhatIf] Would update policy: $($policy.displayName)"
          $updated++
          $results += [pscustomobject]@{
            timestamp = $now; mode = $Mode; tier = $policy.tier; id = $policy.id; displayName = $policy.displayName
            status = 'Planned'; action = 'Update'; issues = ''
          }
        } else {
          Invoke-Graph -Method PATCH -Uri "$script:ConditionalAccessApiBase/$id" -Headers $headers -Body $payload | Out-Null
          Write-RunLog -Level INFO -Message "Updated policy: $($policy.displayName)"
          $updated++
          $results += [pscustomobject]@{
            timestamp = $now; mode = $Mode; tier = $policy.tier; id = $policy.id; displayName = $policy.displayName
            status = 'Updated'; action = 'Patch existing policy'; issues = ''
          }
        }
      } else {
        if ($WhatIf) {
          Write-RunLog -Level INFO -Message "[WhatIf] Would create policy: $($policy.displayName)"
          $created++
          $results += [pscustomobject]@{
            timestamp = $now; mode = $Mode; tier = $policy.tier; id = $policy.id; displayName = $policy.displayName
            status = 'Planned'; action = 'Create'; issues = ''
          }
        } else {
          Invoke-Graph -Method POST -Uri $script:ConditionalAccessApiBase -Headers $headers -Body $payload | Out-Null
          Write-RunLog -Level INFO -Message "Created policy: $($policy.displayName)"
          $created++
          $results += [pscustomobject]@{
            timestamp = $now; mode = $Mode; tier = $policy.tier; id = $policy.id; displayName = $policy.displayName
            status = 'Created'; action = 'Create new policy'; issues = ''
          }
        }
      }
    } elseif ($Mode -eq 'Evaluate') {
      $expected = Resolve-ExpectedBehaviorPayload -Policy $policy -AuthStrengthMap $authStrengthMap
      $best = Find-BestPolicyMatch -ExpectedPayload $expected -TenantPolicies $tenantPolicies

      if ($null -eq $best.policy -or $best.score -lt 6) {
        $issueText = 'No behaviorally similar policy found. Recommend create policy in report-only mode.'
        $recommendations += "[$($policy.id)] $issueText"
        $results += [pscustomobject]@{
          timestamp = $now; mode = $Mode; tier = $policy.tier; id = $policy.id; displayName = $policy.displayName
          status = 'Missing'; action = 'Create policy'; issues = $issueText
        }
        $evaluated++
        continue
      }

      $candidate = ConvertTo-Hashtable -InputObject $best.policy
      $issues = Get-BehaviorMismatches -ExpectedPolicy $expected -CandidatePolicy $candidate
      if ([string]$candidate.state -ne 'enabledForReportingButNotEnforced') {
        $issues += 'candidate policy is not report-only'
      }
      $candidateName = [string]$candidate.displayName

      if ($best.score -ge 10 -and $issues.Count -eq 0) {
        $recommendations += "[$($policy.id)] OK."
        $results += [pscustomobject]@{
          timestamp = $now; mode = $Mode; tier = $policy.tier; id = $policy.id; displayName = $policy.displayName
          status = 'OK'; action = "Matched: $candidateName"; issues = ''
        }
      } else {
        $issueText = "Best behavioral match: '$candidateName' (score=$($best.score)/12). " + (($issues | Select-Object -Unique) -join '; ')
        $recommendations += "[$($policy.id)] $issueText"
        $results += [pscustomobject]@{
          timestamp = $now; mode = $Mode; tier = $policy.tier; id = $policy.id; displayName = $policy.displayName
          status = 'PartialMatch'; action = "Review/align with: $candidateName"; issues = $issueText
        }
      }
      $evaluated++
    } else {
      $existing = Get-PolicyByName -DisplayName $policy.displayName -Headers $headers -PolicyId $policy.id
      if ($null -eq $existing) {
        $skipped++
        $results += [pscustomobject]@{
          timestamp = $now; mode = $Mode; tier = $policy.tier; id = $policy.id; displayName = $policy.displayName
          status = 'NotFound'; action = 'No action'; issues = 'Policy not found in tenant.'
        }
        continue
      }

      if ($WhatIf) {
        Write-RunLog -Level INFO -Message "[WhatIf] Would delete policy: $($existing.displayName)"
        $removed++
        $results += [pscustomobject]@{
          timestamp = $now; mode = $Mode; tier = $policy.tier; id = $policy.id; displayName = $policy.displayName
          status = 'Planned'; action = 'Delete'; issues = ''
        }
      } else {
        Invoke-Graph -Method DELETE -Uri "$script:ConditionalAccessApiBase/$($existing.id)" -Headers $headers -Body $null | Out-Null
        Write-RunLog -Level INFO -Message "Deleted policy: $($existing.displayName)"
        $removed++
        $results += [pscustomobject]@{
          timestamp = $now; mode = $Mode; tier = $policy.tier; id = $policy.id; displayName = $policy.displayName
          status = 'Deleted'; action = 'Delete policy'; issues = ''
        }
      }
    }
  } catch {
    $errors++
    $msg = "Policy processing failed for file '$($file.Name)': $($_.Exception.Message)"
    Write-RunLog -Level ERROR -Message $msg
    $results += [pscustomobject]@{
      timestamp = $now; mode = $Mode; tier = ''; id = ''; displayName = $file.Name
      status = 'Error'; action = 'Review error'; issues = $msg
    }
    if (-not $ContinueOnError) {
      throw
    }
  }
}
} # end else block for non-Compare modes

if ($Mode -eq 'Remove') {
  $isFullTierSelection = (($selectedTiers | Sort-Object) -join ',') -eq 'baseline,e5,frontline,managed'
  $hasPolicyFilter = $selectedIds.Count -gt 0
  $canRemoveGroups = $isFullTierSelection -and -not $hasPolicyFilter

  if ($canRemoveGroups) {
    foreach ($name in $groupNames) {
      try {
        $deletedGroup = Remove-GroupIfExists -DisplayName $name -Headers $headers
        if ($deletedGroup) {
          $removed++
          $results += [pscustomobject]@{
            timestamp = $now; mode = $Mode; tier = 'group'; id = ''; displayName = $name
            status = $(if ($WhatIf) { 'Planned' } else { 'Deleted' }); action = 'Delete group'; issues = ''
          }
        } else {
          $skipped++
          $results += [pscustomobject]@{
            timestamp = $now; mode = $Mode; tier = 'group'; id = ''; displayName = $name
            status = 'NotFound'; action = 'No action'; issues = 'Group not found in tenant.'
          }
        }
      } catch {
        $errors++
        $msg = "Group removal failed for '$name': $($_.Exception.Message)"
        Write-RunLog -Level ERROR -Message $msg
        $results += [pscustomobject]@{
          timestamp = $now; mode = $Mode; tier = 'group'; id = ''; displayName = $name
          status = 'Error'; action = 'Review error'; issues = $msg
        }
        if (-not $ContinueOnError) {
          throw
        }
      }
    }
  } else {
    Write-RunLog -Level WARN -Message "Group cleanup skipped. Full tier selection and no PolicyId filter are required to safely remove toolkit groups."
  }
}

if (-not $ReportPath) {
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $ext = $ReportFormat.ToLower()
  $ReportPath = Join-Path -Path 'output' -ChildPath "ca-$($Mode.ToLower())-report-$ts.$ext"
}

Write-RunReport -Rows $results -Format $ReportFormat -Path $ReportPath

if ($Mode -eq 'Deploy') {
  Write-RunLog -Level INFO -Message "Summary: mode=Deploy created=$created updated=$updated skipped=$skipped errors=$errors whatIf=$($WhatIf.IsPresent) report=$ReportPath log=$script:RunLogPath"
} elseif ($Mode -eq 'Remove') {
  Write-RunLog -Level INFO -Message "Summary: mode=Remove removed=$removed skipped=$skipped errors=$errors whatIf=$($WhatIf.IsPresent) report=$ReportPath log=$script:RunLogPath"
} elseif ($Mode -eq 'Compare') {
  Write-RunLog -Level INFO -Message "Summary: mode=Compare covered=$covered uncovered=$uncovered skipped=$skipped errors=$errors report=$ReportPath log=$script:RunLogPath"
} else {
  Write-RunLog -Level INFO -Message "Summary: mode=Evaluate evaluated=$evaluated skipped=$skipped missingGroups=$($missingGroups.Count) errors=$errors report=$ReportPath log=$script:RunLogPath"
  Write-RunLog -Level INFO -Message "Recommendations:"
  foreach ($r in $recommendations) { Write-RunLog -Level INFO -Message "- $r" }

  if ($missingGroups.Count -gt 0) {
    Write-RunLog -Level WARN -Message "Missing groups: $($missingGroups -join ', ')"
  }
}

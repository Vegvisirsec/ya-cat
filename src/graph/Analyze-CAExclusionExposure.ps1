[CmdletBinding()]
param(
  [string]$EnvFile = '.env.local',
  [int]$DaysPast = 30,
  [string]$PolicyId = '',
  [string]$PrincipalId = '',
  [string]$OutputFolder = '',
  [int]$MaxObservedApplications = 8,
  [int]$MaxSampledUsersPerExcludedGroup = 5
)

$ErrorActionPreference = 'Stop'

$authModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'common' | Join-Path -ChildPath 'Authentication.ps1'
. $authModulePath

function Load-EnvFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Env file not found: $Path"
  }

  Get-Content $Path | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    $k, $v = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), 'Process')
  }
}

function Invoke-Graph {
  param(
    [string]$Uri,
    [hashtable]$Headers,
    [string]$Method = 'GET',
    [object]$Body,
    [int]$JsonDepth = 20,
    [int]$MaxRetries = 4
  )

  $retryCount = 0
  $backoffMs = 1000

  while ($retryCount -lt $MaxRetries) {
    try {
      $params = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = $Headers
        AuthContext = $script:authContext
        JsonDepth   = $JsonDepth
      }

      if ($null -ne $Body) {
        $params.Body = $Body
      }

      return Invoke-GraphRequest @params
    }
    catch {
      $statusCode = $null
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = $_.Exception.Response.StatusCode.Value__
      }

      if ($statusCode -eq 429) {
        $retryCount++
        if ($retryCount -lt $MaxRetries) {
          Write-Host "Rate limited. Waiting $backoffMs ms before retry $retryCount/$MaxRetries..." -ForegroundColor Yellow
          Start-Sleep -Milliseconds $backoffMs
          $backoffMs = [Math]::Min($backoffMs * 2, 8000)
          continue
        }
      }

      throw
    }
  }
}

function Get-AllGraphResults {
  param(
    [string]$Uri,
    [hashtable]$Headers
  )

  $items = @()
  $next = $Uri

  while ($next) {
    $response = Invoke-Graph -Uri $next -Headers $Headers
    if ($response.value) {
      $items += @($response.value)
    }
    $next = $response.'@odata.nextLink'
  }

  return @($items)
}

function Get-CAPolicies {
  param([hashtable]$Headers)

  Write-Host "Querying Conditional Access policies..." -ForegroundColor Cyan
  return Get-AllGraphResults -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -Headers $Headers
}

function Show-PolicyMenu {
  param(
    [array]$Policies,
    [string]$FilterString = ''
  )

  $filtered = $Policies
  if (-not [string]::IsNullOrWhiteSpace($FilterString)) {
    $filtered = $Policies | Where-Object {
      $_.displayName -like "*$FilterString*" -or $_.id -like "*$FilterString*"
    }
  }

  if ($filtered.Count -eq 0) {
    Write-Host "No policies match the filter." -ForegroundColor Red
    return $null
  }

  Write-Host "`n=== Select a Policy ===" -ForegroundColor Cyan
  for ($i = 0; $i -lt $filtered.Count; $i++) {
    Write-Host ("  [{0}] {1} ({2})" -f ($i + 1), $filtered[$i].displayName, $filtered[$i].state)
  }

  if ($filtered.Count -eq 1) {
    return $filtered[0]
  }

  $selection = Read-Host "Enter selection (1-$($filtered.Count))"
  $index = [int]::Parse($selection) - 1
  if ($index -lt 0 -or $index -ge $filtered.Count) {
    throw "Invalid policy selection"
  }

  return $filtered[$index]
}

function Get-UserById {
  param(
    [string]$UserId,
    [hashtable]$Headers
  )

  $uri = "https://graph.microsoft.com/v1.0/users/$UserId?`$select=id,displayName,userPrincipalName,accountEnabled,userType"
  return Invoke-Graph -Uri $uri -Headers $Headers
}

function Get-GroupById {
  param(
    [string]$GroupId,
    [hashtable]$Headers
  )

  $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId"
  $group = Invoke-Graph -Uri $uri -Headers $Headers
  return [pscustomobject]@{
    id              = $group.id
    displayName     = $group.displayName
    securityEnabled = $group.securityEnabled
    mailEnabled     = $group.mailEnabled
  }
}

function Get-GroupUserMembers {
  param(
    [string]$GroupId,
    [hashtable]$Headers
  )

  $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/transitiveMembers"
  $members = Get-AllGraphResults -Uri $uri -Headers $Headers
  return @(
    $members |
      Where-Object { $_.'@odata.type' -eq '#microsoft.graph.user' } |
      ForEach-Object {
        [pscustomobject]@{
          id                = $_.id
          displayName       = $_.displayName
          userPrincipalName = $_.userPrincipalName
          accountEnabled    = $_.accountEnabled
          userType          = $_.userType
        }
      }
  )
}

function Resolve-ExcludedUsers {
  param(
    [object]$Policy,
    [hashtable]$Headers,
    [int]$MaxSampledUsersPerExcludedGroup
  )

  $resolved = @()
  $unsupported = @()
  $userIdsSeen = @{}

  $excludeUsers = @()
  $excludeGroups = @()
  $excludeRoles = @()

  if ($Policy.conditions -and $Policy.conditions.users) {
    if ($Policy.conditions.users.excludeUsers) {
      $excludeUsers = @($Policy.conditions.users.excludeUsers)
    }
    if ($Policy.conditions.users.excludeGroups) {
      $excludeGroups = @($Policy.conditions.users.excludeGroups)
    }
    if ($Policy.conditions.users.excludeRoles) {
      $excludeRoles = @($Policy.conditions.users.excludeRoles)
    }
  }

  foreach ($userId in $excludeUsers) {
    if ($userId -in @('GuestsOrExternalUsers', 'None')) {
      $unsupported += [pscustomobject]@{
        type    = 'specialUserScope'
        id      = $userId
        reason  = 'Special CA user scopes cannot be resolved to a specific sign-in subject.'
      }
      continue
    }

    $user = Get-UserById -UserId $userId -Headers $Headers
    if (-not $userIdsSeen.ContainsKey($user.id)) {
      $resolved += [pscustomobject]@{
        id                = $user.id
        displayName       = $user.displayName
        userPrincipalName = $user.userPrincipalName
        accountEnabled    = $user.accountEnabled
        userType          = $user.userType
        sourceType        = 'DirectUserExclusion'
        sourceId          = $Policy.id
        sourceDisplayName = $Policy.displayName
      }
      $userIdsSeen[$user.id] = $true
    }
  }

  foreach ($groupId in $excludeGroups) {
    $group = Get-GroupById -GroupId $groupId -Headers $Headers
    $members = @(Get-GroupUserMembers -GroupId $groupId -Headers $Headers)

    if ($members.Count -eq 0) {
      $unsupported += [pscustomobject]@{
        type    = 'groupWithoutUsers'
        id      = $group.id
        reason  = "Excluded group '$($group.displayName)' has no transitive user members to analyze."
      }
      continue
    }

    $selectedMembers = $members
    if ($members.Count -gt $MaxSampledUsersPerExcludedGroup) {
      $selectedMembers = @($members | Get-Random -Count $MaxSampledUsersPerExcludedGroup)
      $unsupported += [pscustomobject]@{
        type    = 'sampledExcludedGroup'
        id      = $group.id
        reason  = "Excluded group '$($group.displayName)' has $($members.Count) user members. Sampled $($selectedMembers.Count) users to keep the analysis tractable."
      }
    }

    foreach ($member in $selectedMembers) {
      if ($userIdsSeen.ContainsKey($member.id)) {
        continue
      }

      $resolved += [pscustomobject]@{
        id                = $member.id
        displayName       = $member.displayName
        userPrincipalName = $member.userPrincipalName
        accountEnabled    = $member.accountEnabled
        userType          = $member.userType
        sourceType        = 'ExcludedGroupMember'
        sourceId          = $group.id
        sourceDisplayName = $group.displayName
      }
      $userIdsSeen[$member.id] = $true
    }
  }

  foreach ($roleId in $excludeRoles) {
    $unsupported += [pscustomobject]@{
      type    = 'roleExclusion'
      id      = $roleId
      reason  = 'Role-based exclusions are not expanded in this script. The policy stores role template IDs, while sign-in analysis is user-centric.'
    }
  }

  return [pscustomobject]@{
    ResolvedUsers = @($resolved)
    Unsupported   = @($unsupported)
  }
}

function Show-PrincipalMenu {
  param(
    [array]$Principals,
    [string]$PreselectedPrincipalId = ''
  )

  if ($Principals.Count -eq 0) {
    return $null
  }

  if (-not [string]::IsNullOrWhiteSpace($PreselectedPrincipalId)) {
    return $Principals | Where-Object { $_.id -eq $PreselectedPrincipalId } | Select-Object -First 1
  }

  Write-Host "`n=== Select an Excluded Identity to Analyze ===" -ForegroundColor Cyan
  for ($i = 0; $i -lt $Principals.Count; $i++) {
    $entry = $Principals[$i]
    $sourceLabel = if ($entry.sourceType -eq 'DirectUserExclusion') { 'direct exclusion' } else { "via $($entry.sourceDisplayName)" }
    Write-Host ("  [{0}] {1} <{2}> [{3}]" -f ($i + 1), $entry.displayName, $entry.userPrincipalName, $sourceLabel)
  }

  if ($Principals.Count -eq 1) {
    return $Principals[0]
  }

  $selection = Read-Host "Enter selection (1-$($Principals.Count))"
  $index = [int]::Parse($selection) - 1
  if ($index -lt 0 -or $index -ge $Principals.Count) {
    throw "Invalid identity selection"
  }

  return $Principals[$index]
}

function Get-UserSignInLogs {
  param(
    [string]$UserId,
    [int]$DaysPast,
    [hashtable]$Headers
  )

  $cutoffDate = (Get-Date).AddDays(-$DaysPast).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $filter = "createdDateTime ge $cutoffDate and userId eq '$UserId'"
  $select = 'createdDateTime,userId,userDisplayName,userPrincipalName,appId,appDisplayName,clientAppUsed,ipAddress,location,deviceDetail,status,conditionalAccessStatus,riskDetail,riskLevelAggregated,riskState'
  $uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$filter&`$select=$select&`$top=999"

  Write-Host "Querying sign-in logs for selected identity..." -ForegroundColor Cyan
  return Get-AllGraphResults -Uri $uri -Headers $Headers
}

function Get-TopValues {
  param(
    [array]$Records,
    [scriptblock]$Selector,
    [int]$Top = 5
  )

  $values = @($Records | ForEach-Object { & $Selector $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($values.Count -eq 0) {
    return @()
  }

  return @(
    $values |
      Group-Object |
      Sort-Object -Property @(
        @{ Expression = 'Count'; Descending = $true },
        @{ Expression = 'Name'; Descending = $false }
      ) |
      Select-Object -First $Top |
      ForEach-Object {
        [pscustomobject]@{
          value = $_.Name
          count = $_.Count
        }
      }
  )
}

function Get-ObservedAppIds {
  param(
    [array]$SignIns,
    [int]$MaxCount
  )

  $apps = @($SignIns |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_.appId) } |
    Group-Object appId |
    Sort-Object -Property @(
      @{ Expression = 'Count'; Descending = $true },
      @{ Expression = 'Name'; Descending = $false }
    ))

  if ($apps.Count -eq 0) {
    return @()
  }

  return @($apps | Select-Object -First $MaxCount | ForEach-Object { $_.Name })
}

function Convert-ClientAppToCAValue {
  param([string]$ClientAppUsed)

  switch -Regex ($ClientAppUsed) {
    '^Browser$' { return 'browser' }
    'Exchange ActiveSync' { return 'exchangeActiveSync' }
    'Mobile Apps and Desktop clients|Desktop|Mobile' { return 'mobileAppsAndDesktopClients' }
    default { return 'other' }
  }
}

function Test-BreakGlassLikeIdentity {
  param([object]$Principal)

  $tokens = @(
    [string]$Principal.displayName,
    [string]$Principal.userPrincipalName,
    [string]$Principal.sourceDisplayName
  ) -join ' '

  return ($tokens -match '(?i)break[\s-]?glass|emergency|tier0|tier-0')
}

function Get-PolicyCode {
  param([string]$DisplayName)

  if ([string]::IsNullOrWhiteSpace($DisplayName)) {
    return 'CA-ADHOC'
  }

  $match = [regex]::Match($DisplayName, '^(CA-[A-Z]{2}-\d{3})')
  if ($match.Success) {
    return $match.Groups[1].Value
  }

  return 'CA-ADHOC'
}

function Convert-ToSafeToken {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return 'unknown'
  }

  $safe = $Value -replace '[^a-zA-Z0-9._-]', '-'
  $safe = $safe -replace '-{2,}', '-'
  $safe = $safe.Trim('-')
  if ([string]::IsNullOrWhiteSpace($safe)) {
    return 'unknown'
  }

  return $safe
}

function Get-PrincipalToken {
  param([object]$Principal)

  $candidate = [string]$Principal.userPrincipalName
  if ($candidate.Contains('@')) {
    $candidate = $candidate.Split('@')[0]
  }

  if ([string]::IsNullOrWhiteSpace($candidate)) {
    $candidate = [string]$Principal.displayName
  }

  return Convert-ToSafeToken -Value $candidate
}

function Get-ProposalNaming {
  param(
    [object]$Policy,
    [object]$Principal
  )

  $policyCode = Get-PolicyCode -DisplayName ([string]$Policy.displayName)
  $principalToken = Get-PrincipalToken -Principal $Principal
  $baseToken = Convert-ToSafeToken -Value "$policyCode-exclusion-complement-$principalToken"

  return [pscustomobject]@{
    PolicyCode      = $policyCode
    PrincipalToken  = $principalToken
    DisplayName     = "$policyCode - Complementary Restriction for Excluded Identity - $principalToken"
    FileStem        = $baseToken
  }
}

function Get-BuiltInGrantControls {
  param([object]$Policy)

  if (-not $Policy.grantControls -or -not $Policy.grantControls.builtInControls) {
    return @()
  }

  return @($Policy.grantControls.builtInControls | ForEach-Object { [string]$_ })
}

function Test-CanUseAppEnforcedRestrictions {
  param([object]$Policy)

  if (-not $Policy.conditions -or -not $Policy.conditions.applications) {
    return $false
  }

  $clientApps = @()
  if ($Policy.conditions.clientAppTypes) {
    $clientApps = @($Policy.conditions.clientAppTypes | ForEach-Object { [string]$_ })
  }

  $includeApps = @()
  if ($Policy.conditions.applications.includeApplications) {
    $includeApps = @($Policy.conditions.applications.includeApplications | ForEach-Object { [string]$_ })
  }

  return (($clientApps -contains 'browser') -and ($includeApps -contains 'Office365'))
}

function New-DeepClone {
  param([object]$InputObject)

  if ($null -eq $InputObject) {
    return $null
  }

  return ($InputObject | ConvertTo-Json -Depth 50 | ConvertFrom-Json)
}

function New-ProposalBase {
  param(
    [object]$Policy,
    [object]$Principal,
    [object]$Naming
  )

  $proposal = [ordered]@{
    displayName = $Naming.DisplayName
    state       = 'enabledForReportingButNotEnforced'
    conditions  = [ordered]@{}
  }

  $clonedConditions = New-DeepClone -InputObject $Policy.conditions
  if ($null -ne $clonedConditions) {
    foreach ($property in $clonedConditions.PSObject.Properties) {
      $proposal.conditions[$property.Name] = $property.Value
    }
  }

  if ($Policy.grantControls) {
    $proposal.grantControls = [ordered]@{}
    $clonedGrantControls = New-DeepClone -InputObject $Policy.grantControls
    foreach ($property in $clonedGrantControls.PSObject.Properties) {
      $proposal.grantControls[$property.Name] = $property.Value
    }
  }

  if ($Policy.sessionControls) {
    $proposal.sessionControls = [ordered]@{}
    $clonedSessionControls = New-DeepClone -InputObject $Policy.sessionControls
    foreach ($property in $clonedSessionControls.PSObject.Properties) {
      $proposal.sessionControls[$property.Name] = $property.Value
    }
  }

  $proposal.conditions.users = [ordered]@{
    includeUsers  = @($Principal.id)
    excludeUsers  = @()
    includeGroups = @()
    excludeGroups = @()
    includeRoles  = @()
    excludeRoles  = @()
  }

  return $proposal
}

function Ensure-ConditionSection {
  param(
    [hashtable]$Proposal,
    [string]$SectionName
  )

  if (-not $Proposal.conditions.Contains($SectionName) -or $null -eq $Proposal.conditions[$SectionName]) {
    $Proposal.conditions[$SectionName] = [ordered]@{}
    return
  }

  if ($Proposal.conditions[$SectionName] -isnot [System.Collections.IDictionary]) {
    $existing = $Proposal.conditions[$SectionName]
    $Proposal.conditions[$SectionName] = [ordered]@{}
    foreach ($property in $existing.PSObject.Properties) {
      $Proposal.conditions[$SectionName][$property.Name] = $property.Value
    }
  }
}

function Get-ObservedCountryCodes {
  param([object]$Summary)

  if (-not $Summary.topCountries) {
    return @()
  }

  $countries = @($Summary.topCountries)
  if ($countries.Count -eq 0) {
    return @()
  }

  return @($countries | ForEach-Object { [string]$_.value } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-ObservedApplications {
  param([object]$Summary)

  if (-not $Summary.topApplications) {
    return @()
  }

  $applications = @($Summary.topApplications)
  if ($applications.Count -eq 0) {
    return @()
  }

  return @($applications | ForEach-Object { [string]$_.value } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-FactorPriorityOrder {
  return @(
    'locationOrIp',
    'application',
    'platform',
    'clientAppType',
    'deviceState',
    'risk'
  )
}

function Get-AllowedApplicationScopeScore {
  param([object]$Proposal)

  if (-not $Proposal.conditions -or -not $Proposal.conditions.applications) {
    return 80
  }

  $apps = @()
  if ($Proposal.conditions.applications.excludeApplications) {
    $apps = @($Proposal.conditions.applications.excludeApplications)
    if ($apps.Count -gt 0) {
      return [Math]::Min(15 + ($apps.Count * 5), 40)
    }
  }

  if ($Proposal.conditions.applications.includeApplications) {
    $apps = @($Proposal.conditions.applications.includeApplications)
    if ($apps -contains 'All') {
      return 100
    }
    if ($apps -contains 'Office365') {
      return 55
    }
    return [Math]::Min(20 + ($apps.Count * 5), 50)
  }

  return 80
}

function Get-AllowedLocationScopeScore {
  param([hashtable]$ScopeHints)

  if ($ScopeHints.ContainsKey('AllowedCountriesCount')) {
    return [Math]::Min(10 + ($ScopeHints.AllowedCountriesCount * 10), 45)
  }

  return 75
}

function New-ScoredProposalOption {
  param(
    [string]$OptionType,
    [string]$VariantLabel,
    [pscustomobject]$Policy,
    [string[]]$Notes,
    [bool]$Deployable,
    [hashtable]$ScopeHints,
    [object]$SourcePolicy,
    [array]$ChildPolicies
  )

  $policy.displayName = "$($policy.displayName) - $VariantLabel"

  $allowedAppScore = Get-AllowedApplicationScopeScore -Proposal $Policy
  $allowedLocationScore = Get-AllowedLocationScopeScore -ScopeHints $ScopeHints
  $constraintScore = if ($Policy.sessionControls -and $Policy.sessionControls.applicationEnforcedRestrictions -and $Policy.sessionControls.applicationEnforcedRestrictions.isEnabled) { 15 } elseif ((Get-BuiltInGrantControls -Policy $Policy) -contains 'block') { 25 } else { 10 }
  $deployableScore = if ($Deployable) { 20 } else { 0 }
  $placeholderPenalty = if ($ScopeHints.ContainsKey('HasPlaceholders') -and $ScopeHints.HasPlaceholders) { 20 } else { 0 }
  $patternBonus = 0
  if (($OptionType -eq 'ScopedRestrictionComplement') -and (Test-CanUseAppEnforcedRestrictions -Policy $SourcePolicy)) {
    $patternBonus += 25
  }
  if (($OptionType -eq 'ScopedBlockComplement') -and (Test-CanUseAppEnforcedRestrictions -Policy $SourcePolicy)) {
    $patternBonus -= 20
  }
  if (($OptionType -eq 'SinglePolicyLocationCarveout') -and ($ScopeHints.ContainsKey('AllowedCountriesCount')) -and $ScopeHints.AllowedCountriesCount -le 1) {
    $patternBonus += 20
  }
  if (($OptionType -eq 'SinglePolicyAppCarveout') -and ($ScopeHints.ContainsKey('AllowedApplicationsCount')) -and $ScopeHints.AllowedApplicationsCount -le 1) {
    $patternBonus += 10
  }
  if ($OptionType -eq 'CompoundBlockComplementSet') {
    $patternBonus += 5
  }
  if (($OptionType -eq 'ScopedBlockComplement') -and $ScopeHints.ContainsKey('AllowedApplicationsCount') -and $ScopeHints.AllowedApplicationsCount -le 1) {
    $patternBonus -= 10
  }
  $openingScore = [Math]::Round(($allowedAppScore + $allowedLocationScore) / 2)
  $score = [Math]::Max(1, [Math]::Min(100, 100 - $openingScore + $constraintScore + $deployableScore + $patternBonus - $placeholderPenalty))

  return [pscustomobject]@{
    optionType    = $OptionType
    variantLabel  = $VariantLabel
    score         = $score
    openingScore  = $openingScore
    deployable    = $Deployable
    scopeHints    = $ScopeHints
    notes         = @($Notes)
    policy        = $Policy
    childPolicies = @($ChildPolicies)
  }
}

function New-ProposedOptions {
  param(
    [object]$Policy,
    [object]$Principal,
    [array]$SignIns,
    [int]$MaxObservedApplications,
    [object]$Summary
  )

  $naming = Get-ProposalNaming -Policy $Policy -Principal $Principal
  $options = @()

  $observedAppIds = Get-ObservedAppIds -SignIns $SignIns -MaxCount $MaxObservedApplications
  $observedAppNames = Get-ObservedApplications -Summary $Summary
  $observedCountries = Get-ObservedCountryCodes -Summary $Summary
  $existingApps = @()
  if ($Policy.conditions -and $Policy.conditions.applications -and $Policy.conditions.applications.includeApplications) {
    $existingApps = @($Policy.conditions.applications.includeApplications)
  }

  $builtInControls = Get-BuiltInGrantControls -Policy $Policy
  if ($builtInControls -contains 'block') {
    if ($observedAppIds.Count -gt 0 -and $observedAppIds.Count -le $MaxObservedApplications -and $existingApps.Count -gt 0) {
      $appBlockProposal = New-ProposalBase -Policy $Policy -Principal $Principal -Naming $naming
      Ensure-ConditionSection -Proposal $appBlockProposal -SectionName 'applications'
      $appBlockProposal.conditions.applications.excludeApplications = @($observedAppIds)
      $appNotes = @(
        'Reused the original block-policy intent, but carved out only the observed application footprint for the excluded identity.',
        'This keeps the user blocked for the rest of the original target scope while preserving the currently observed app access path.'
      )
      $options += New-ScoredProposalOption -OptionType 'SinglePolicyAppCarveout' -VariantLabel 'Single Policy with Observed App Carveout' -Policy $appBlockProposal -Notes $appNotes -Deployable $true -ScopeHints @{
        AllowedApplicationsCount = $observedAppIds.Count
      } -SourcePolicy $Policy
    }

    if (Test-CanUseAppEnforcedRestrictions -Policy $Policy) {
      $sessionProposal = New-ProposalBase -Policy $Policy -Principal $Principal -Naming $naming
      $sessionProposal.grantControls = $null
      $sessionProposal.sessionControls = [ordered]@{
        applicationEnforcedRestrictions = [ordered]@{
          isEnabled = $true
        }
      }
      $sessionNotes = @(
        'Converted the original block intent into app-enforced restrictions so the user keeps limited unmanaged browser access instead of a full block.',
        'This is broader than an app-specific block carveout, but it maps well to the standard M365 unmanaged-browser restriction pattern.'
      )
      $options += New-ScoredProposalOption -OptionType 'ScopedRestrictionComplement' -VariantLabel 'App-Enforced Restriction Complement' -Policy $sessionProposal -Notes $sessionNotes -Deployable $true -ScopeHints @{} -SourcePolicy $Policy
    }

    if ($observedCountries.Count -gt 0 -and $observedCountries.Count -le 3) {
      $locationProposal = New-ProposalBase -Policy $Policy -Principal $Principal -Naming $naming
      Ensure-ConditionSection -Proposal $locationProposal -SectionName 'locations'
      $placeholderIds = @($observedCountries | ForEach-Object { "{{NAMED_LOCATION_$($_)}}" })
      $locationProposal.conditions.locations.excludeLocations = $placeholderIds
      $locationNotes = @(
        'Built a user-scoped block complement with a location carveout for the observed countries.',
        'This is potentially the narrowest opening, but it requires you to replace the named location placeholders with real tenant object IDs before deployment.'
      )
      $options += New-ScoredProposalOption -OptionType 'SinglePolicyLocationCarveout' -VariantLabel 'Single Policy with Named Location Carveout' -Policy $locationProposal -Notes $locationNotes -Deployable $false -ScopeHints @{
        AllowedCountriesCount = $observedCountries.Count
        HasPlaceholders       = $true
      } -SourcePolicy $Policy
    }

    if (($observedCountries.Count -gt 0 -and $observedCountries.Count -le 3) -and ($observedAppIds.Count -gt 0 -and $observedAppIds.Count -le $MaxObservedApplications)) {
      $locationPolicy = New-ProposalBase -Policy $Policy -Principal $Principal -Naming $naming
      Ensure-ConditionSection -Proposal $locationPolicy -SectionName 'locations'
      $locationPolicy.conditions.locations.excludeLocations = @($observedCountries | ForEach-Object { "{{NAMED_LOCATION_$($_)}}" })
      $locationPolicy.displayName = $naming.DisplayName

      $appPolicy = New-ProposalBase -Policy $Policy -Principal $Principal -Naming $naming
      Ensure-ConditionSection -Proposal $appPolicy -SectionName 'applications'
      $appPolicy.conditions.applications.excludeApplications = @($observedAppIds)
      $appPolicy.displayName = $naming.DisplayName

      $compoundSummary = [pscustomobject]@{
        displayName = "$($naming.DisplayName) - Compound Block Complement Set"
        policyCount = 2
      }
      $compoundNotes = @(
        'Built a two-policy complementary set because a single policy cannot safely express a tight AND-style exception boundary such as location plus application.',
        "The intended allowed path becomes the intersection of the exclusions, for example countries [$($observedCountries -join ', ')] and apps [$($observedAppNames -join ', ')]."
      )
      $options += New-ScoredProposalOption -OptionType 'CompoundBlockComplementSet' -VariantLabel 'Compound Block Complement Set' -Policy $compoundSummary -Notes $compoundNotes -Deployable $false -ScopeHints @{
        AllowedCountriesCount    = $observedCountries.Count
        AllowedApplicationsCount = $observedAppIds.Count
        HasPlaceholders          = $true
      } -SourcePolicy $Policy -ChildPolicies @(
        [pscustomobject]@{
          displayName = "$($naming.DisplayName) - Compound Location Carveout"
          policy      = [pscustomobject]$locationPolicy
        },
        [pscustomobject]@{
          displayName = "$($naming.DisplayName) - Compound App Carveout"
          policy      = [pscustomobject]$appPolicy
        }
      )
    }
  }
  else {
    $inheritedProposal = New-ProposalBase -Policy $Policy -Principal $Principal -Naming $naming
    $inheritedNotes = @(
      'Inherited the original non-block controls into a user-scoped complementary policy.',
      'No stronger narrowing pattern was inferred from the selected source policy.'
    )
    $options += New-ScoredProposalOption -OptionType 'InheritedRestriction' -VariantLabel 'Inherited Restriction' -Policy $inheritedProposal -Notes $inheritedNotes -Deployable $true -ScopeHints @{} -SourcePolicy $Policy
  }

  if ($options.Count -eq 0) {
    $fallbackProposal = New-ProposalBase -Policy $Policy -Principal $Principal -Naming $naming
    $fallbackNotes = @(
      'No precise complementary control could be inferred automatically.',
      'Manual Conditional Access design review is required before deployment.'
    )
    $options += New-ScoredProposalOption -OptionType 'ManualDesignRequired' -VariantLabel 'Manual Design Required' -Policy $fallbackProposal -Notes $fallbackNotes -Deployable $false -ScopeHints @{
      HasPlaceholders = $true
    } -SourcePolicy $Policy
  }

  $ranked = @($options | Sort-Object -Property @(
    @{ Expression = 'score'; Descending = $true },
    @{ Expression = 'openingScore'; Descending = $false },
    @{ Expression = 'deployable'; Descending = $true }
  ))

  return [pscustomobject]@{
    Recommended = $ranked[0]
    Options     = @($ranked)
    Naming      = $naming
  }
}

function Get-SignInSummary {
  param([array]$SignIns)

  $successCount = @($SignIns | Where-Object { $_.status.errorCode -eq 0 }).Count
  $failureCount = $SignIns.Count - $successCount

  $clientAppValues = @(
    $SignIns |
      ForEach-Object { Convert-ClientAppToCAValue -ClientAppUsed ([string]$_.clientAppUsed) } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      Select-Object -Unique
  )

  return [pscustomobject]@{
    totalSignIns        = $SignIns.Count
    successfulSignIns   = $successCount
    failedSignIns       = $failureCount
    topApplications     = Get-TopValues -Records $SignIns -Selector { param($x) $x.appDisplayName } -Top 10
    topClientApps       = Get-TopValues -Records $SignIns -Selector { param($x) $x.clientAppUsed } -Top 10
    topOperatingSystems = Get-TopValues -Records $SignIns -Selector { param($x) $x.deviceDetail.operatingSystem } -Top 10
    topCountries        = Get-TopValues -Records $SignIns -Selector { param($x) $x.location.countryOrRegion } -Top 10
    topRiskLevels       = Get-TopValues -Records $SignIns -Selector { param($x) $x.riskLevelAggregated } -Top 10
    caClientAppTypes    = @($clientAppValues)
  }
}

function Export-SignInCsv {
  param(
    [array]$SignIns,
    [string]$Path
  )

  $rows = $SignIns | ForEach-Object {
    [pscustomobject]@{
      Timestamp             = $_.createdDateTime
      UserDisplayName       = $_.userDisplayName
      UserPrincipalName     = $_.userPrincipalName
      Application           = $_.appDisplayName
      AppId                 = $_.appId
      ClientAppUsed         = $_.clientAppUsed
      ConditionalAccess     = $_.conditionalAccessStatus
      RiskLevelAggregated   = $_.riskLevelAggregated
      RiskState             = $_.riskState
      Country               = $_.location.countryOrRegion
      State                 = $_.location.state
      City                  = $_.location.city
      IPAddress             = $_.ipAddress
      DeviceOS              = $_.deviceDetail.operatingSystem
      Browser               = $_.deviceDetail.browser
      StatusErrorCode       = $_.status.errorCode
      StatusFailureReason   = $_.status.failureReason
    }
  }

  $rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}

try {
  Load-EnvFile -Path $EnvFile
  $authContext = Get-GraphAuthContextFromEnv

  if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputFolder = Join-Path -Path 'output' -ChildPath "ca-exclusion-exposure-$ts"
  }

  New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

  $token = Get-GraphTokenFromEnv
  $headers = if ($authContext.AuthMethod -eq 'Delegated') { @{} } else { @{ Authorization = "Bearer $token" } }

  Write-Host "Authenticated to Graph using method: $($authContext.AuthMethod)" -ForegroundColor Cyan

  $policies = Get-CAPolicies -Headers $headers
  if ($policies.Count -eq 0) {
    throw 'No Conditional Access policies found in the tenant.'
  }

  if ([string]::IsNullOrWhiteSpace($PolicyId)) {
    $filter = Read-Host "Filter policies by name or ID (press Enter to list all)"
    $selectedPolicy = Show-PolicyMenu -Policies $policies -FilterString $filter
  }
  else {
    $selectedPolicy = $policies | Where-Object { $_.id -eq $PolicyId -or $_.displayName -eq $PolicyId } | Select-Object -First 1
  }

  if ($null -eq $selectedPolicy) {
    throw 'No policy selected.'
  }

  Write-Host "`nSelected policy: $($selectedPolicy.displayName)" -ForegroundColor Green
  $resolution = Resolve-ExcludedUsers -Policy $selectedPolicy -Headers $headers -MaxSampledUsersPerExcludedGroup $MaxSampledUsersPerExcludedGroup

  if ($resolution.Unsupported.Count -gt 0) {
    Write-Host "`nUnsupported exclusions detected:" -ForegroundColor Yellow
    foreach ($entry in $resolution.Unsupported) {
      Write-Host ("  - {0}: {1}" -f $entry.id, $entry.reason) -ForegroundColor Yellow
    }
  }

  if ($resolution.ResolvedUsers.Count -eq 0) {
    throw 'The selected policy does not expose any resolvable excluded user identities.'
  }

  $selectedPrincipal = Show-PrincipalMenu -Principals $resolution.ResolvedUsers -PreselectedPrincipalId $PrincipalId
  if ($null -eq $selectedPrincipal) {
    throw 'No excluded identity selected.'
  }

  Write-Host "`nSelected identity: $($selectedPrincipal.displayName) <$($selectedPrincipal.userPrincipalName)>" -ForegroundColor Green
  $signIns = Get-UserSignInLogs -UserId $selectedPrincipal.id -DaysPast $DaysPast -Headers $headers
  $summary = Get-SignInSummary -SignIns $signIns
  $proposalBundle = New-ProposedOptions -Policy $selectedPolicy -Principal $selectedPrincipal -SignIns $signIns -MaxObservedApplications $MaxObservedApplications -Summary $summary

  $riskFlags = @()
  if (Test-BreakGlassLikeIdentity -Principal $selectedPrincipal) {
    $riskFlags += 'The selected identity appears to be a break-glass or emergency-style account. Do not auto-tighten this account without a validated access-recovery design.'
  }
  if ($signIns.Count -eq 0) {
    $riskFlags += 'No sign-ins were observed in the selected window. The proposal therefore inherits the parent policy scope and controls with minimal evidence-based narrowing.'
  }
  if ($summary.topRiskLevels.Count -gt 0) {
    $nonNoneRisk = @($summary.topRiskLevels | Where-Object { $_.value -and $_.value -notin @('none', 'hidden', 'unknownFutureValue') })
    if ($nonNoneRisk.Count -gt 0) {
      $riskFlags += 'Observed sign-ins include non-none risk signals. Review Identity Protection coverage before relying on a narrowly scoped exception policy.'
    }
  }

  $report = [pscustomobject]@{
    generatedAt          = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    tenantId             = $authContext.TenantId
    authMethod           = $authContext.AuthMethod
    daysPast             = $DaysPast
    selectedPolicy       = [pscustomobject]@{
      id          = $selectedPolicy.id
      displayName = $selectedPolicy.displayName
      state       = $selectedPolicy.state
    }
    selectedIdentity     = $selectedPrincipal
    unsupportedExclusions = @($resolution.Unsupported)
    signInSummary        = $summary
    proposalNaming       = $proposalBundle.Naming
    recommendationType   = $proposalBundle.Recommended.optionType
    proposalNotes        = @($proposalBundle.Recommended.notes)
    factorPriorityOrder  = @(Get-FactorPriorityOrder)
    rankedOptions        = @($proposalBundle.Options | ForEach-Object {
      [pscustomobject]@{
        optionType   = $_.optionType
        variantLabel = $_.variantLabel
        displayName  = $_.policy.displayName
        score        = $_.score
        openingScore = $_.openingScore
        deployable   = $_.deployable
        childPolicyCount = @($_.childPolicies).Count
        notes        = $_.notes
      }
    })
    riskFlags            = @($riskFlags)
    consultantAssessment = @(
      'Treat this output as a draft scoping recommendation, not an auto-remediation.'
      'Prefer targeting the specific excluded identity first; only widen to a group if the operating model requires it.'
      'In many valid Conditional Access designs, the original broad exclusion remains in place while this narrower complementary policy trims the exception surface.'
      'Validate recovery, service-account behavior, device-management dependencies, and licensing before moving beyond report-only.'
    )
  }

  $fileStem = $proposalBundle.Naming.FileStem
  $reportPath = Join-Path $OutputFolder "$fileStem.analysis-summary.json"
  $proposalPath = Join-Path $OutputFolder "$fileStem.recommended-policy.json"
  $optionsPath = Join-Path $OutputFolder "$fileStem.proposal-options.json"
  $signInCsvPath = Join-Path $OutputFolder "$fileStem.selected-identity-signins.csv"

  $report | ConvertTo-Json -Depth 20 | Set-Content -Path $reportPath
  $proposalBundle.Recommended.policy | ConvertTo-Json -Depth 30 | Set-Content -Path $proposalPath
  $proposalBundle.Options | ConvertTo-Json -Depth 30 | Set-Content -Path $optionsPath
  Export-SignInCsv -SignIns $signIns -Path $signInCsvPath

  Write-Host "`n=== Analysis Complete ===" -ForegroundColor Cyan
  Write-Host "Policy: $($selectedPolicy.displayName)"
  Write-Host "Identity: $($selectedPrincipal.userPrincipalName)"
  Write-Host "Sign-ins analyzed: $($signIns.Count)"
  Write-Host "`nRanked proposal options:"
  for ($i = 0; $i -lt $proposalBundle.Options.Count; $i++) {
    $option = $proposalBundle.Options[$i]
    Write-Host ("  [{0}] score={1} type={2} deployable={3} name={4}" -f ($i + 1), $option.score, $option.optionType, $option.deployable, $option.policy.displayName)
  }
  Write-Host "Summary: $reportPath"
  Write-Host "Recommended proposal: $proposalPath"
  Write-Host "All options: $optionsPath"
  Write-Host "Sign-ins CSV: $signInCsvPath"
}
catch {
  Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

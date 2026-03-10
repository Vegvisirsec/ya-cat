[CmdletBinding()]
param(
  [string]$EnvFile = '.env.local',
  [string]$OutputFolder,
  [int]$DaysPast = 30,
  [string]$PoliciesRoot = 'policies'
)

$ErrorActionPreference = 'Stop'

$authModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'common' | Join-Path -ChildPath 'Authentication.ps1'
. $authModulePath

$script:ConditionalAccessApiBase = 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies'

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

function Invoke-Graph {
  param(
    [string]$Uri,
    [hashtable]$Headers,
    [string]$Method = 'GET',
    $Body = $null,
    [int]$MaxRetries = 5
  )

  for ($attempt = 0; $attempt -lt $MaxRetries; $attempt++) {
    try {
      if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType 'application/json'
      }

      $jsonBody = $Body | ConvertTo-Json -Depth 20
      return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType 'application/json' -Body $jsonBody
    } catch {
      $statusCode = $null
      $retryAfterSeconds = 3
      if ($_.Exception.Response) {
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
        try {
          $retryHeader = $_.Exception.Response.Headers['Retry-After']
          if ($retryHeader) { $retryAfterSeconds = [int]$retryHeader }
        } catch {}
      }

      if ($statusCode -eq 429 -and $attempt -lt ($MaxRetries - 1)) {
        Start-Sleep -Seconds $retryAfterSeconds
        continue
      }

      throw
    }
  }
}

function Get-AllPages {
  param(
    [string]$Uri,
    [hashtable]$Headers
  )

  $items = @()
  $next = $Uri
  while ($next) {
    $resp = Invoke-Graph -Uri $next -Headers $Headers
    if ($resp.value) { $items += @($resp.value) }
    $next = $resp.'@odata.nextLink'
  }
  return @($items)
}

function ConvertTo-Hashtable {
  param($InputObject)

  if ($null -eq $InputObject) { return $null }
  if ($InputObject -is [System.Collections.IDictionary]) {
    $result = @{}
    foreach ($key in $InputObject.Keys) {
      $result[$key] = ConvertTo-Hashtable -InputObject $InputObject[$key]
    }
    return $result
  }
  if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
    $items = @()
    foreach ($item in $InputObject) {
      $items += ,(ConvertTo-Hashtable -InputObject $item)
    }
    return ,$items
  }
  if ($InputObject -is [psobject] -and $InputObject.PSObject.Properties.Count -gt 0) {
    $result = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
      $result[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
    }
    return $result
  }
  return $InputObject
}

function New-CountHeaders {
  param([string]$Token)
  return @{
    Authorization    = "Bearer $Token"
    ConsistencyLevel = 'eventual'
  }
}

function Get-CountValue {
  param(
    [string]$Uri,
    [hashtable]$Headers
  )

  $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
  $resp = Invoke-Graph -Uri ($Uri + $separator + '$top=1&$count=true') -Headers $Headers
  return [int]($resp.'@odata.count')
}

function Get-ToolkitPolicies {
  param([string]$Root)

  $files = Get-ChildItem -Path $Root -Recurse -File -Filter 'CA-*.json' | Sort-Object FullName
  $policies = @()
  foreach ($file in $files) {
    $raw = Get-Content -Raw -Path $file.FullName
    $obj = $raw | ConvertFrom-Json
    $policies += [pscustomobject]@{
      id = [string]$obj.id
      displayName = [string]$obj.displayName
      tier = [string]$obj.tier
      optional = [bool]$obj.optional
      path = [string]$obj.path
      sourceFile = $file.FullName
      policyObject = $obj
    }
  }
  return @($policies)
}

function Get-GroupDefinitions {
  param([string]$ExclusionGroupsPath)

  $names = @(
    'CA-BreakGlass-Exclude',
    'CA-Tier-Baseline',
    'CA-Tier-P1-Managed',
    'CA-Tier-Frontline',
    'CA-Tier-E5',
    'CA-Admins',
    'CA-Pilot'
  )

  if (Test-Path $ExclusionGroupsPath) {
    $defs = Get-Content -Raw -Path $ExclusionGroupsPath | ConvertFrom-Json
    foreach ($def in $defs) {
      if ($names -notcontains [string]$def.name) {
        $names += [string]$def.name
      }
    }
  }

  return @($names | Sort-Object -Unique)
}

function Get-GroupByName {
  param(
    [string]$DisplayName,
    [hashtable]$Headers
  )

  $escaped = $DisplayName.Replace("'", "''")
  $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$escaped'&`$select=id,displayName,description,groupTypes"
  $resp = Invoke-Graph -Uri $uri -Headers $Headers
  if ($resp.value -and $resp.value.Count -gt 0) { return $resp.value[0] }
  return $null
}

function Get-RoleTemplateIdsFromPolicies {
  param([array]$Policies)

  $roleIds = @()
  foreach ($policy in $Policies) {
    if ($policy.policyObject.target -and $policy.policyObject.target.includeRoleTemplateIds) {
      $roleIds += @($policy.policyObject.target.includeRoleTemplateIds)
    }
  }
  return @($roleIds | Sort-Object -Unique)
}

function Add-ToCounter {
  param(
    [hashtable]$Counter,
    [string]$Key
  )

  if ([string]::IsNullOrWhiteSpace($Key)) { $Key = 'Unknown' }
  if ($Counter.ContainsKey($Key)) {
    $Counter[$Key]++
  } else {
    $Counter[$Key] = 1
  }
}

function Convert-CounterToTopList {
  param(
    [hashtable]$Counter,
    [int]$Top = 10
  )

  return @(
    $Counter.GetEnumerator() |
      Sort-Object -Property Value -Descending |
      Select-Object -First $Top |
      ForEach-Object {
        [pscustomobject]@{
          name = $_.Key
          count = $_.Value
        }
      }
  )
}

function Get-SignInAggregateSummary {
  param(
    [hashtable]$Headers,
    [array]$ToolkitPolicies,
    [int]$DaysPast
  )

  $cutoff = (Get-Date).AddDays(-$DaysPast).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $uri = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=createdDateTime ge $cutoff&`$select=createdDateTime,appDisplayName,location,conditionalAccessStatus,appliedConditionalAccessPolicies&`$top=500"

  $toolkitById = @{}
  $toolkitByName = @{}
  foreach ($policy in $ToolkitPolicies) {
    $toolkitById[$policy.id] = $policy
    $toolkitByName[$policy.displayName] = $policy
  }

  $countries = @{}
  $apps = @{}
  $caStatus = @{}
  $policyHits = @{}
  $total = 0

  $next = $uri
  while ($next) {
    $resp = Invoke-Graph -Uri $next -Headers $Headers
    foreach ($signIn in @($resp.value)) {
      $total++
      Add-ToCounter -Counter $countries -Key ([string]$signIn.location.countryOrRegion)
      Add-ToCounter -Counter $apps -Key ([string]$signIn.appDisplayName)
      Add-ToCounter -Counter $caStatus -Key ([string]$signIn.conditionalAccessStatus)

      foreach ($applied in @($signIn.appliedConditionalAccessPolicies)) {
        $policyRef = $null
        if ($applied.id -and $toolkitById.ContainsKey([string]$applied.id)) {
          $policyRef = $toolkitById[[string]$applied.id]
        } elseif ($applied.displayName -and $toolkitByName.ContainsKey([string]$applied.displayName)) {
          $policyRef = $toolkitByName[[string]$applied.displayName]
        }

        if ($null -eq $policyRef) { continue }

        $key = [string]$policyRef.id
        if (-not $policyHits.ContainsKey($key)) {
          $policyHits[$key] = @{
            policyId = [string]$policyRef.id
            displayName = [string]$policyRef.displayName
            tier = [string]$policyRef.tier
            totalHits = 0
            results = @{}
            applications = @{}
            countries = @{}
          }
        }

        $policyHits[$key].totalHits++
        Add-ToCounter -Counter $policyHits[$key].results -Key ([string]$applied.result)
        Add-ToCounter -Counter $policyHits[$key].applications -Key ([string]$signIn.appDisplayName)
        Add-ToCounter -Counter $policyHits[$key].countries -Key ([string]$signIn.location.countryOrRegion)
      }
    }
    $next = $resp.'@odata.nextLink'
  }

  $policySummaries = @()
  foreach ($entry in $policyHits.GetEnumerator() | Sort-Object { $_.Value.totalHits } -Descending) {
    $value = $entry.Value
    $policySummaries += [pscustomobject]@{
      policyId = $value.policyId
      displayName = $value.displayName
      tier = $value.tier
      totalHits = $value.totalHits
      results = Convert-CounterToTopList -Counter $value.results -Top 10
      topApplications = Convert-CounterToTopList -Counter $value.applications -Top 10
      topCountries = Convert-CounterToTopList -Counter $value.countries -Top 10
    }
  }

  return [pscustomobject]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
    daysPast = $DaysPast
    totalSignIns = $total
    conditionalAccessStatus = Convert-CounterToTopList -Counter $caStatus -Top 10
    topCountries = Convert-CounterToTopList -Counter $countries -Top 20
    topApplications = Convert-CounterToTopList -Counter $apps -Top 20
    toolkitPolicyHits = $policySummaries
  }
}

Load-EnvFile -Path $EnvFile

$tenantId = Get-RequiredEnv -Name 'TENANT_ID'
$clientId = Get-RequiredEnv -Name 'CLIENT_ID'
$clientSecret = Get-RequiredEnv -Name 'CLIENT_SECRET'
$scope = Get-RequiredEnv -Name 'GRAPH_SCOPE'

if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $OutputFolder = Join-Path -Path 'output' -ChildPath "ca-context-$ts"
}

$desiredStateFolder = Join-Path $OutputFolder 'desired-state'
$tenantStateFolder = Join-Path $OutputFolder 'tenant-state'
$llmFolder = Join-Path $OutputFolder 'llm'

New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null
New-Item -ItemType Directory -Force -Path $desiredStateFolder | Out-Null
New-Item -ItemType Directory -Force -Path $tenantStateFolder | Out-Null
New-Item -ItemType Directory -Force -Path $llmFolder | Out-Null

$token = Get-GraphToken -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret -Scope $scope
$headers = @{ Authorization = "Bearer $token" }
$countHeaders = New-CountHeaders -Token $token

$toolkitPolicies = Get-ToolkitPolicies -Root $PoliciesRoot
$toolkitRoleTemplateIds = Get-RoleTemplateIdsFromPolicies -Policies $toolkitPolicies
$groupNames = Get-GroupDefinitions -ExclusionGroupsPath 'groups/policy-exclusion-groups.json'

$desiredManifest = @(
  $toolkitPolicies | ForEach-Object {
    [pscustomobject]@{
      id = $_.id
      displayName = $_.displayName
      tier = $_.tier
      optional = $_.optional
      path = $_.path
    }
  }
)

$desiredPoliciesFolder = Join-Path $desiredStateFolder 'policies'
New-Item -ItemType Directory -Force -Path $desiredPoliciesFolder | Out-Null
foreach ($policy in $toolkitPolicies) {
  $relativePath = $policy.path
  $destination = Join-Path $desiredStateFolder $relativePath
  $destinationDir = Split-Path -Parent $destination
  if (-not (Test-Path $destinationDir)) {
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
  }
  Copy-Item -Path $policy.sourceFile -Destination $destination -Force
}
($desiredManifest | ConvertTo-Json -Depth 10) | Set-Content -Path (Join-Path $desiredStateFolder 'policy-manifest.json')

$org = (Invoke-Graph -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,verifiedDomains' -Headers $headers).value | Select-Object -First 1
$tenantProfile = [pscustomobject]@{
  tenantId = $tenantId
  displayName = [string]$org.displayName
  verifiedDomains = @(
    @($org.verifiedDomains) | ForEach-Object {
      [pscustomobject]@{
        name = [string]$_.name
        isDefault = [bool]$_.isDefault
        isInitial = [bool]$_.isInitial
      }
    }
  )
}
($tenantProfile | ConvertTo-Json -Depth 10) | Set-Content -Path (Join-Path $tenantStateFolder 'tenant-profile.json')

$userPopulationSummary = [pscustomobject]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
  totals = [pscustomobject]@{
    users = Get-CountValue -Uri 'https://graph.microsoft.com/v1.0/users' -Headers $countHeaders
    memberUsers = Get-CountValue -Uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Member'" -Headers $countHeaders
    guestUsers = Get-CountValue -Uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'" -Headers $countHeaders
    enabledMemberUsers = Get-CountValue -Uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Member' and accountEnabled eq true" -Headers $countHeaders
    enabledGuestUsers = Get-CountValue -Uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest' and accountEnabled eq true" -Headers $countHeaders
  }
}
($userPopulationSummary | ConvertTo-Json -Depth 10) | Set-Content -Path (Join-Path $tenantStateFolder 'user-population-summary.json')

$groupSummaries = @()
foreach ($groupName in $groupNames) {
  $group = Get-GroupByName -DisplayName $groupName -Headers $headers
  if ($null -eq $group) {
    $groupSummaries += [pscustomobject]@{
      displayName = $groupName
      exists = $false
      id = ''
      memberCount = 0
      description = ''
    }
    continue
  }

  $memberCountUri = "https://graph.microsoft.com/v1.0/groups/$($group.id)/members"
  $memberCount = Get-CountValue -Uri $memberCountUri -Headers $countHeaders
  $groupSummaries += [pscustomobject]@{
    displayName = [string]$group.displayName
    exists = $true
    id = [string]$group.id
    memberCount = $memberCount
    description = [string]$group.description
  }
}
($groupSummaries | ConvertTo-Json -Depth 10) | Set-Content -Path (Join-Path $tenantStateFolder 'toolkit-group-summary.json')

$directoryRoles = Get-AllPages -Uri 'https://graph.microsoft.com/v1.0/directoryRoles?$select=id,displayName,roleTemplateId' -Headers $headers
$privilegedRoleSummary = @()
foreach ($roleTemplateId in $toolkitRoleTemplateIds) {
  $role = @($directoryRoles | Where-Object { [string]$_.roleTemplateId -eq $roleTemplateId } | Select-Object -First 1)
  if ($role.Count -eq 0) {
    $privilegedRoleSummary += [pscustomobject]@{
      roleTemplateId = $roleTemplateId
      displayName = ''
      activeInTenant = $false
      memberCount = 0
    }
    continue
  }

  $memberCountUri = "https://graph.microsoft.com/v1.0/directoryRoles/$($role[0].id)/members"
  $memberCount = Get-CountValue -Uri $memberCountUri -Headers $countHeaders
  $privilegedRoleSummary += [pscustomobject]@{
    roleTemplateId = [string]$role[0].roleTemplateId
    displayName = [string]$role[0].displayName
    activeInTenant = $true
    memberCount = $memberCount
  }
}
($privilegedRoleSummary | ConvertTo-Json -Depth 10) | Set-Content -Path (Join-Path $tenantStateFolder 'privileged-role-summary.json')

$namedLocations = Get-AllPages -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations' -Headers $headers
($namedLocations | ConvertTo-Json -Depth 30) | Set-Content -Path (Join-Path $tenantStateFolder 'named-locations.json')

$tenantPolicies = Get-AllPages -Uri $script:ConditionalAccessApiBase -Headers $headers
($tenantPolicies | ConvertTo-Json -Depth 50) | Set-Content -Path (Join-Path $tenantStateFolder 'tenant-policies.json')

$tenantPolicyManifest = @(
  $tenantPolicies | ForEach-Object {
    [pscustomobject]@{
      id = [string]$_.id
      displayName = [string]$_.displayName
      state = [string]$_.state
    }
  }
)
($tenantPolicyManifest | ConvertTo-Json -Depth 10) | Set-Content -Path (Join-Path $tenantStateFolder 'tenant-policy-manifest.json')

$signInAggregateSummary = Get-SignInAggregateSummary -Headers $headers -ToolkitPolicies $toolkitPolicies -DaysPast $DaysPast
($signInAggregateSummary | ConvertTo-Json -Depth 20) | Set-Content -Path (Join-Path $tenantStateFolder 'sign-in-aggregate-summary.json')

Copy-Item -Path 'instructions.md' -Destination (Join-Path $llmFolder 'instructions.md') -Force
Copy-Item -Path 'findings-schema.json' -Destination (Join-Path $llmFolder 'findings-schema.json') -Force

$manifest = [pscustomobject]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
  tenantId = $tenantId
  tenantDisplayName = [string]$org.displayName
  daysPast = $DaysPast
  files = @(
    [pscustomobject]@{ path = 'desired-state/policy-manifest.json'; purpose = 'Desired-state policy reference' },
    [pscustomobject]@{ path = 'tenant-state/tenant-profile.json'; purpose = 'Tenant orientation and report metadata' },
    [pscustomobject]@{ path = 'tenant-state/user-population-summary.json'; purpose = 'Proportional risk and population-size context' },
    [pscustomobject]@{ path = 'tenant-state/toolkit-group-summary.json'; purpose = 'Targeting model and exclusion hygiene context' },
    [pscustomobject]@{ path = 'tenant-state/privileged-role-summary.json'; purpose = 'Privileged exposure context for admin policies' },
    [pscustomobject]@{ path = 'tenant-state/named-locations.json'; purpose = 'Named-location and geography policy context' },
    [pscustomobject]@{ path = 'tenant-state/tenant-policies.json'; purpose = 'Actual tenant Conditional Access state' },
    [pscustomobject]@{ path = 'tenant-state/sign-in-aggregate-summary.json'; purpose = 'Aggregated telemetry for report-only hit and geography review' },
    [pscustomobject]@{ path = 'llm/instructions.md'; purpose = 'Global local-LLM evaluation contract' },
    [pscustomobject]@{ path = 'llm/findings-schema.json'; purpose = 'Structured output schema for evaluation results' }
  )
}
($manifest | ConvertTo-Json -Depth 10) | Set-Content -Path (Join-Path $OutputFolder 'manifest.json')

Write-Host "Exported context package to $OutputFolder"

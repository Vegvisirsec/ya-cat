[CmdletBinding()]
param(
  [string]$EnvFile = '.env.local',
  [int]$DaysPast = 30,
  [string]$PolicyId = '',
  [string]$OutputFolder = '',
  [switch]$IncludeUsername
)

$ErrorActionPreference = 'Stop'

# Source shared authentication module
$authModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'common' | Join-Path -ChildPath 'Authentication.ps1'
. $authModulePath

# Load environment file
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

function Get-RequiredEnv {
  param([string]$Name)
  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) { 
    throw "Missing required env var: $Name" 
  }
  return $value
}


function Invoke-GraphAPI {
  param(
    [string]$Uri, 
    [hashtable]$Headers, 
    [string]$Method = 'GET', 
    [object]$Body,
    [int]$MaxRetries = 3
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
        JsonDepth   = 10
      }
      if ($null -ne $Body) {
        $params['Body'] = $Body
      }
      return Invoke-GraphRequest @params
    }
    catch {
      $statusCode = $_.Exception.Response.StatusCode.Value__
      if ($statusCode -eq 429) {
        $retryCount++
        if ($retryCount -lt $MaxRetries) {
          $waitTime = [math]::Min($backoffMs, 5000)
          Write-Host "Rate limited. Waiting $waitTime ms..." -ForegroundColor Yellow
          Start-Sleep -Milliseconds $waitTime
          $backoffMs = $backoffMs * 2
          continue
        }
      }
      throw
    }
  }
}

function Get-CAPolicies {
  param([hashtable]$Headers)
  
  Write-Host "Querying Conditional Access policies..." -ForegroundColor Cyan
  
  $policies = @()
  $uri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
  
  try {
    while ($uri) {
      $response = Invoke-GraphAPI -Uri $uri -Headers $Headers
      $policies += $response.value
      $uri = $response.'@odata.nextLink'
    }
    Write-Host "Found $($policies.Count) policies" -ForegroundColor Green
    return $policies
  }
  catch {
    Write-Host "Failed to query policies: $_" -ForegroundColor Red
    throw
  }
}

function Show-PolicyMenu {
  param([array]$Policies, [string]$FilterString = '')
  
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
  Write-Host "Found $($filtered.Count) policies:`n"
  
  for ($i = 0; $i -lt $filtered.Count; $i++) {
    $state = if ($filtered[$i].state -eq 'enabled') { 'ENABLED' } else { 'REPORT_ONLY' }
    $stateColor = if ($filtered[$i].state -eq 'enabled') { 'Yellow' } else { 'Green' }
    Write-Host "  [$($i + 1)] $($filtered[$i].displayName)" -ForegroundColor Cyan -NoNewline
    Write-Host " (State: " -NoNewline
    Write-Host $state -ForegroundColor $stateColor -NoNewline
    Write-Host ")"
  }
  
  Write-Host ""
  if ($filtered.Count -gt 1) {
    $selection = Read-Host "Enter selection (1-$($filtered.Count))"
    $idx = [int]::Parse($selection) - 1
    if ($idx -lt 0 -or $idx -ge $filtered.Count) {
      Write-Host "Invalid selection" -ForegroundColor Red
      return $null
    }
    return $filtered[$idx]
  }
  else {
    Write-Host "Using the only matching policy."
    return $filtered[0]
  }
}

function Get-SignInLogs {
  param(
    [hashtable]$Headers, 
    [int]$DaysPast
  )
  
  Write-Host "Querying sign-in logs for the past $DaysPast days..." -ForegroundColor Cyan
  
  $cutoffDate = (Get-Date).AddDays(-$DaysPast).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  
  $signInLogs = @()
  $uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=createdDateTime ge $cutoffDate&`$top=999"
  
  try {
    while ($uri) {
      $response = Invoke-GraphAPI -Uri $uri -Headers $Headers
      $signInLogs += $response.value
      $uri = $response.'@odata.nextLink'
      
      if ($signInLogs.Count % 1000 -eq 0) {
        Write-Host "  ... retrieved $($signInLogs.Count) records" -ForegroundColor Gray
      }
    }
    Write-Host "Retrieved $($signInLogs.Count) total sign-in records" -ForegroundColor Green
    return $signInLogs
  }
  catch {
    Write-Host "Failed to query sign-in logs: $_" -ForegroundColor Red
    throw
  }
}

function Test-SignInAgainstPolicy {
  param(
    [object]$SignIn,
    [object]$Policy
  )
  
  $conditions = $Policy.conditions
  
  # Check applications
  if ($conditions.applications.includeApplications.Count -gt 0) {
    if ($conditions.applications.includeApplications[0] -ne 'All') {
      if ($SignIn.appId -notin $conditions.applications.includeApplications) {
        return $false
      }
    }
  }
  
  # Check client app types (if configured)
  if ($conditions.clientAppTypes.Count -gt 0) {
    $isMatch = $false
    foreach ($clientApp in $conditions.clientAppTypes) {
      if ($clientApp -eq 'All') {
        $isMatch = $true
        break
      }
    }
    if (-not $isMatch) {
      return $false
    }
  }
  
  return $true
}

function Format-SignInRecord {
  param(
    [object]$SignIn,
    [bool]$IncludeUsername
  )
  
  $record = [PSCustomObject]@{
    Timestamp       = $SignIn.createdDateTime
    City            = $SignIn.location.city
    State           = $SignIn.location.state
    Country         = $SignIn.location.countryOrRegion
    Application     = $SignIn.appDisplayName
    AppId           = $SignIn.appId
    Protocol        = $SignIn.clientAppUsed
    DeviceOS        = $SignIn.deviceDetail.operatingSystem
    DeviceBrowser   = $SignIn.deviceDetail.browser
    IPAddress       = $SignIn.ipAddress
    SignInStatus    = $SignIn.status.errorCode
  }
  
  if ($IncludeUsername) {
    $record | Add-Member -MemberType NoteProperty -Name 'UserPrincipalName' -Value $SignIn.userPrincipalName
  }
  
  return $record
}

function Export-ToCSV {
  param(
    [array]$Records,
    [string]$PolicyName,
    [string]$OutputPath
  )
  
  if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
  }
  
  $timestamp = Get-Date -Format 'yyyyMMdd'
  $safeDisplayName = $PolicyName -replace '[<>:"/\\|?*]', '-'
  $csvPath = Join-Path -Path $OutputPath -ChildPath "CA-$safeDisplayName-Impact-$timestamp.csv"
  
  $Records | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
  Write-Host "Exported $($Records.Count) records to: $csvPath" -ForegroundColor Green
  
  return $csvPath
}

# Main execution
try {
  Write-Host "Loading environment..." -ForegroundColor Cyan
  Load-EnvFile -Path $EnvFile
  
  $authContext = Get-GraphAuthContextFromEnv
  
  if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
    $OutputFolder = 'output'
  }
  
  Write-Host "Authenticating..." -ForegroundColor Cyan
  $token = Get-GraphTokenFromEnv
  Write-Host "Auth method: $($authContext.AuthMethod)" -ForegroundColor Gray
  
  $headers = @{
    ContentType = 'application/json'
  }
  if ($authContext.AuthMethod -ne 'Delegated') {
    $headers.Authorization = "Bearer $token"
  }
  
  $policies = Get-CAPolicies -Headers $headers
  
  if ($policies.Count -eq 0) {
    Write-Host "No policies found in tenant" -ForegroundColor Red
    exit 1
  }
  
  # Select policy
  if ([string]::IsNullOrWhiteSpace($PolicyId)) {
    Write-Host "Filter by policy name or ID (press Enter to see all):" -ForegroundColor Gray
    $filterInput = Read-Host "Filter"
    $selectedPolicy = Show-PolicyMenu -Policies $policies -FilterString $filterInput
  }
  else {
    $selectedPolicy = $policies | Where-Object { $_.id -eq $PolicyId -or $_.displayName -eq $PolicyId } | Select-Object -First 1
  }
  
  if ($null -eq $selectedPolicy) {
    Write-Host "No policy selected" -ForegroundColor Red
    exit 1
  }
  
  Write-Host "`n=== Policy Selected ===" -ForegroundColor Green
  Write-Host "Name: $($selectedPolicy.displayName)"
  Write-Host "State: $($selectedPolicy.state)"
  Write-Host ""
  
  # Get sign-in logs
  $signInLogs = Get-SignInLogs -Headers $headers -DaysPast $DaysPast
  
  # Filter by policy
  Write-Host "Filtering logs against policy conditions..." -ForegroundColor Cyan
  $matchingLogs = @()
  
  foreach ($log in $signInLogs) {
    if (Test-SignInAgainstPolicy -SignIn $log -Policy $selectedPolicy) {
      $matchingLogs += $log
    }
  }
  
  Write-Host "Found $($matchingLogs.Count) matching sign-ins" -ForegroundColor Green
  
  if ($matchingLogs.Count -eq 0) {
    Write-Host "No matching records. Analysis complete." -ForegroundColor Yellow
    exit 0
  }
  
  Write-Host "Formatting records..." -ForegroundColor Cyan
  $formattedRecords = @()
  
  foreach ($log in $matchingLogs) {
    $record = Format-SignInRecord -SignIn $log -IncludeUsername $IncludeUsername
    $formattedRecords += $record
  }
  
  $exportPath = Export-ToCSV -Records $formattedRecords -PolicyName $selectedPolicy.displayName -OutputPath $OutputFolder
  
  Write-Host "`n=== Summary ===" -ForegroundColor Green
  Write-Host "Policy: $($selectedPolicy.displayName)"
  Write-Host "Time Range: Last $DaysPast days"
  Write-Host "Matching Sign-ins: $($matchingLogs.Count)"
  Write-Host "Output: $exportPath"
  Write-Host ""
}
catch {
  Write-Host "Error: $_" -ForegroundColor Red
  exit 1
}

[CmdletBinding()]
param(
  [string]$EnvFile = '.env.local',
  [Parameter(Mandatory = $true)] [string]$InputFolder,
  [switch]$PreserveState,
  [switch]$WhatIf,
  [string]$ReportPath = '',
  [string]$LogPath = '',
  [switch]$ContinueOnError
)

$ErrorActionPreference = 'Stop'
$script:RunLogPath = $null

# Source shared authentication module
$authModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'common' | Join-Path -ChildPath 'Authentication.ps1'
. $authModulePath

function Initialize-RunLog {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Path = Join-Path -Path 'output' -ChildPath "ca-folder-deploy-log-$ts.txt"
  }
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $script:RunLogPath = $Path
  Set-Content -Path $script:RunLogPath -Value ""
}

function Write-RunLog {
  param([ValidateSet('INFO','WARN','ERROR')] [string]$Level, [string]$Message)
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
    foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-Hashtable -InputObject $InputObject[$k] }
    return $h
  }
  if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
    $arr = @()
    foreach ($i in $InputObject) { $arr += ,(ConvertTo-Hashtable -InputObject $i) }
    return ,$arr
  }
  if ($InputObject -is [psobject] -and $InputObject.PSObject.Properties.Count -gt 0) {
    $h = @{}
    foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hashtable -InputObject $p.Value }
    return $h
  }
  return $InputObject
}

function Remove-NullAndOData {
  param($Value)

  if ($null -eq $Value) { return $null }

  if ($Value -is [System.Collections.IDictionary]) {
    $clean = @{}
    foreach ($k in @($Value.Keys)) {
      if ([string]$k -like '@odata*' -or [string]$k -like '*@odata*') { continue }
      $v = Remove-NullAndOData -Value $Value[$k]
      if ($null -ne $v) { $clean[$k] = $v }
    }
    return $clean
  }

  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    $arr = @()
    foreach ($i in $Value) {
      $v = Remove-NullAndOData -Value $i
      if ($null -ne $v) { $arr += ,$v }
    }
    return ,$arr
  }

  return $Value
}


function Invoke-Graph {
  param(
    [ValidateSet('GET','POST','PATCH')] [string]$Method,
    [string]$Uri,
    [hashtable]$Headers,
    $Body
  )

  return Invoke-GraphRequest -Method $Method -Uri $Uri -Headers $Headers -Body $Body -AuthContext $script:authContext -JsonDepth 50
}

function Escape-ODataString {
  param([string]$Value)
  return $Value.Replace("'", "''")
}

function Get-PolicyByDisplayName {
  param([string]$DisplayName, [hashtable]$Headers)
  $escaped = Escape-ODataString -Value $DisplayName
  $uri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?`$filter=displayName eq '$escaped'&`$select=id,displayName,state"
  $resp = Invoke-Graph -Method GET -Uri $uri -Headers $Headers -Body $null
  if ($resp.value.Count -gt 0) { return $resp.value[0] }
  return $null
}

function ConvertTo-DeployablePolicy {
  param([hashtable]$Source, [bool]$KeepState)

  $payload = [ordered]@{}
  if (-not $Source.displayName) { return $null }
  $payload.displayName = $Source.displayName

  if ($Source.conditions) { $payload.conditions = $Source.conditions }
  if ($Source.grantControls) { $payload.grantControls = $Source.grantControls }
  if ($Source.sessionControls) { $payload.sessionControls = $Source.sessionControls }

  if ($KeepState -and $Source.state) {
    $payload.state = $Source.state
  } else {
    $payload.state = 'enabledForReportingButNotEnforced'
  }

  $clean = Remove-NullAndOData -Value $payload
  return $clean
}

Initialize-RunLog -Path $LogPath
Write-RunLog -Level INFO -Message "Starting folder deploy. inputFolder=$InputFolder whatIf=$($WhatIf.IsPresent) preserveState=$($PreserveState.IsPresent) continueOnError=$($ContinueOnError.IsPresent)"

Load-EnvFile -Path $EnvFile
$authContext = Get-GraphAuthContextFromEnv

if (-not (Test-Path $InputFolder)) { throw "Input folder not found: $InputFolder" }
$files = Get-ChildItem -Path $InputFolder -File -Filter '*.json' | Sort-Object Name
if ($files.Count -eq 0) { throw "No .json files found in: $InputFolder" }

$token = Get-GraphTokenFromEnv
Write-RunLog -Level INFO -Message "Authenticated to Graph using method=$($authContext.AuthMethod)"
$headers = if ($authContext.AuthMethod -eq 'Delegated') { @{} } else { @{ Authorization = "Bearer $token" } }

$rows = @()
$created = 0
$updated = 0
$skipped = 0

foreach ($file in $files) {
  try {
    if ($file.Name -eq 'manifest.json') { continue }

    $raw = Get-Content -Raw -Path $file.FullName
    $parsed = ConvertTo-Hashtable -InputObject ($raw | ConvertFrom-Json)

    if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string]) -and -not ($parsed -is [hashtable])) {
      $rows += [pscustomobject]@{ file = $file.Name; displayName = ''; status = 'Skipped'; action = 'Array payload not supported in per-file mode'; notes = '' }
      Write-RunLog -Level WARN -Message "Skipped $($file.Name): array payload not supported."
      $skipped++
      continue
    }

    $payload = ConvertTo-DeployablePolicy -Source $parsed -KeepState:$PreserveState.IsPresent
    if ($null -eq $payload) {
      $rows += [pscustomobject]@{ file = $file.Name; displayName = ''; status = 'Skipped'; action = 'Missing displayName'; notes = '' }
      Write-RunLog -Level WARN -Message "Skipped $($file.Name): missing displayName."
      $skipped++
      continue
    }

    $existing = Get-PolicyByDisplayName -DisplayName ([string]$payload.displayName) -Headers $headers
    if ($null -ne $existing) {
      if ($WhatIf) {
        $rows += [pscustomobject]@{ file = $file.Name; displayName = $payload.displayName; status = 'Planned'; action = 'Update'; notes = '' }
        Write-RunLog -Level INFO -Message "[WhatIf] Would update policy from file: $($file.Name)"
        $updated++
      } else {
        Invoke-Graph -Method PATCH -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$($existing.id)" -Headers $headers -Body $payload | Out-Null
        $rows += [pscustomobject]@{ file = $file.Name; displayName = $payload.displayName; status = 'Updated'; action = 'Patch existing policy'; notes = '' }
        Write-RunLog -Level INFO -Message "Updated policy from file: $($file.Name)"
        $updated++
      }
    } else {
      if ($WhatIf) {
        $rows += [pscustomobject]@{ file = $file.Name; displayName = $payload.displayName; status = 'Planned'; action = 'Create'; notes = '' }
        Write-RunLog -Level INFO -Message "[WhatIf] Would create policy from file: $($file.Name)"
        $created++
      } else {
        Invoke-Graph -Method POST -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -Headers $headers -Body $payload | Out-Null
        $rows += [pscustomobject]@{ file = $file.Name; displayName = $payload.displayName; status = 'Created'; action = 'Create new policy'; notes = '' }
        Write-RunLog -Level INFO -Message "Created policy from file: $($file.Name)"
        $created++
      }
    }
  } catch {
    $msg = "Failed file $($file.Name): $($_.Exception.Message)"
    $rows += [pscustomobject]@{ file = $file.Name; displayName = ''; status = 'Error'; action = 'Review error'; notes = $msg }
    Write-RunLog -Level ERROR -Message $msg
    if (-not $ContinueOnError) { throw }
  }
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $ReportPath = Join-Path -Path 'output' -ChildPath "ca-folder-deploy-report-$ts.csv"
}

$reportDir = Split-Path -Parent $ReportPath
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Force -Path $reportDir | Out-Null }
$rows | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8

Write-RunLog -Level INFO -Message "Summary: created=$created updated=$updated skipped=$skipped whatIf=$($WhatIf.IsPresent) report=$ReportPath log=$script:RunLogPath"

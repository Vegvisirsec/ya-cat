[CmdletBinding()]
param(
  [string]$EnvFile = '.env.local',
  [string]$OutputFolder,
  [switch]$SingleFile
)

$ErrorActionPreference = 'Stop'

# Source shared authentication module
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
  param([string]$Uri, [hashtable]$Headers)
  return Invoke-RestMethod -Method GET -Uri $Uri -Headers $Headers -ContentType 'application/json'
}

function Get-AllPolicies {
  param([hashtable]$Headers)
  $uri = $script:ConditionalAccessApiBase
  $all = @()
  while ($uri) {
    $resp = Invoke-Graph -Uri $uri -Headers $Headers
    if ($resp.value) { $all += @($resp.value) }
    $uri = $resp.'@odata.nextLink'
  }
  return @($all)
}

function Get-SafeName {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) { return 'unnamed-policy' }
  $safe = $Name -replace '[^a-zA-Z0-9\- ]', ''
  $safe = $safe -replace '\s+', '-'
  $safe = $safe.Trim('-')
  if ([string]::IsNullOrWhiteSpace($safe)) { return 'unnamed-policy' }
  return $safe
}

Load-EnvFile -Path $EnvFile
$tenantId = Get-RequiredEnv -Name 'TENANT_ID'
$clientId = Get-RequiredEnv -Name 'CLIENT_ID'
$clientSecret = Get-RequiredEnv -Name 'CLIENT_SECRET'
$scope = Get-RequiredEnv -Name 'GRAPH_SCOPE'

if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $OutputFolder = Join-Path -Path 'output' -ChildPath "ca-export-$ts"
}

New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$token = Get-GraphToken -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret -Scope $scope
$headers = @{ Authorization = "Bearer $token" }
$policies = Get-AllPolicies -Headers $headers

if ($SingleFile) {
  $single = Join-Path $OutputFolder 'policies.json'
  ($policies | ConvertTo-Json -Depth 50) | Set-Content -Path $single
  Write-Host "Exported $($policies.Count) policies to $single"
} else {
  $i = 1
  $manifest = @()
  foreach ($p in $policies) {
    $safe = Get-SafeName -Name ([string]$p.displayName)
    $file = ('{0:D3}-{1}.json' -f $i, $safe)
    $path = Join-Path $OutputFolder $file
    ($p | ConvertTo-Json -Depth 50) | Set-Content -Path $path
    $manifest += [pscustomobject]@{ index = $i; file = $file; id = $p.id; displayName = $p.displayName; state = $p.state }
    $i++
  }
  $manifestPath = Join-Path $OutputFolder 'manifest.json'
  ($manifest | ConvertTo-Json -Depth 10) | Set-Content -Path $manifestPath
  Write-Host "Exported $($policies.Count) policies to $OutputFolder"
  Write-Host "Manifest: $manifestPath"
}

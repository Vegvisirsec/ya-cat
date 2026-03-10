[CmdletBinding()]
param(
  [string]$EnvFile = '.env.local',
  [int]$DaysPast = 30,
  [string]$OutputFolder = '',
  [switch]$CreateNamedLocation,
  [string]$NamedLocationName = '',
  [switch]$IncludeUnknownLocations
)

$ErrorActionPreference = 'Stop'

# Source shared authentication module
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

function Get-RequiredEnv {
  param([string]$Name)
  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) { 
    throw "Missing required env var: $Name" 
  }
  return $value
}


function Invoke-Graph {
  param([string]$Uri, [hashtable]$Headers, [string]$Method = 'GET', [object]$Body)
  
  $maxRetries = 3
  $retryCount = 0
  $backoffMs = 1000
  
  while ($retryCount -lt $maxRetries) {
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
      $errMsg = $_.Exception.Message
      # Check for rate limiting (429)
      if ($_.Exception.Response.StatusCode -eq 429) {
        $retryCount++
        if ($retryCount -lt $maxRetries) {
          Write-Host "Rate limited (429). Waiting $backoffMs ms before retry $retryCount/$maxRetries..." -ForegroundColor Yellow
          Start-Sleep -Milliseconds $backoffMs
          $backoffMs = $backoffMs * 2
          continue
        }
      }
      throw
    }
  }
}

function Convert-ToSlug {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return 'tenant'
  }
  $slug = $Value.ToLowerInvariant()
  $slug = [Regex]::Replace($slug, '[^a-z0-9]+', '-')
  $slug = $slug.Trim('-')
  if ([string]::IsNullOrWhiteSpace($slug)) {
    return 'tenant'
  }
  return $slug
}

function Get-TenantDisplayName {
  param([hashtable]$Headers)
  $uri = "https://graph.microsoft.com/v1.0/organization?`$select=displayName"
  try {
    $resp = Invoke-Graph -Uri $uri -Headers $Headers
    if ($resp.value -and $resp.value.Count -gt 0 -and $resp.value[0].displayName) {
      return [string]$resp.value[0].displayName
    }
  }
  catch {
    Write-Warning "Could not resolve tenant display name from Graph. Falling back to tenant ID token."
  }
  return ''
}

function Get-DefaultNamedLocationName {
  param([string]$TenantDisplayName, [string]$TenantId)
  $tenantToken = if (-not [string]::IsNullOrWhiteSpace($TenantDisplayName)) {
    Convert-ToSlug -Value $TenantDisplayName
  }
  else {
    Convert-ToSlug -Value (($TenantId -split '-')[0])
  }
  $year = Get-Date -Format 'yyyy'
  return "$tenantToken-operating-locations-$year"
}


function Get-SignInLocations {
  param([hashtable]$Headers, [int]$DaysPast, [bool]$IncludeUnknown)
  
  Write-Host "Querying sign-in logs for the past $DaysPast days (location data only)..." -ForegroundColor Cyan
  
  $cutoffDate = (Get-Date).AddDays(-$DaysPast).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $filter = "createdDateTime ge $cutoffDate"
  
  $locations = @{}
  $processed = 0
  $uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$filter&`$select=location&`$top=999"
  
  while ($uri) {
    try {
      $resp = Invoke-Graph -Uri $uri -Headers $Headers
      
      if ($resp.value) {
        foreach ($signIn in $resp.value) {
          $processed++
          
          # Extract location data (privacy: only location, no usernames)
          if ($signIn.location) {
            $loc = $signIn.location
            
            # Build a location key - handle null/empty fields
            $city = if ($loc.city) { $loc.city } else { 'Unknown' }
            $state = if ($loc.state) { $loc.state } else { 'Unknown' }
            $country = if ($loc.countryOrRegion) { $loc.countryOrRegion } else { 'Unknown' }
            
            # Skip unknown locations if not requested
            if (-not $IncludeUnknown -and $city -eq 'Unknown' -and $state -eq 'Unknown' -and $country -eq 'Unknown') {
              continue
            }
            
            $locKey = "$city, $state, $country"
            if (-not $locations.ContainsKey($locKey)) {
              $locations[$locKey] = @{
                city            = $city
                state           = $state
                countryOrRegion = $country
                count           = 0
              }
            }
            $locations[$locKey].count++
          }
        }
      }
      
      $uri = $resp.'@odata.nextLink'
    }
    catch {
      $errMsg = $_.Exception.Message
      Write-Warning "Error processing page: $errMsg"
      $uri = $null
    }
  }
  
  Write-Host "Processed $processed sign-in records." -ForegroundColor Green
  return $locations
}

function Create-NamedLocation {
  param([hashtable]$Headers, [string]$Name, [hashtable]$Locations)
  
  Write-Host "Creating named location: $Name" -ForegroundColor Cyan
  
  # Extract unique country codes
  $countries = @()
  foreach ($loc in $Locations.Values) {
    if ($loc.countryOrRegion -and $loc.countryOrRegion -ne 'Unknown') {
      if ($countries -notcontains $loc.countryOrRegion) {
        $countries += $loc.countryOrRegion
      }
    }
  }
  
  # Correct endpoint and property names
  $uri = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations'
  
  try {
    # Build JSON with correct property names
    $countriesJson = ($countries | ConvertTo-Json)
    if ($countries.Count -eq 1) {
      $countriesJson = "[$countriesJson]"
    }
    
    $jsonPayload = @"
{
  "@odata.type": "#microsoft.graph.countryNamedLocation",
  "displayName": "$($Name.Replace('"', '\"'))",
  "countriesAndRegions": $countriesJson
}
"@
    
    Write-Host "Sending payload: $jsonPayload" -ForegroundColor Gray
    $result = Invoke-GraphRequest -Method POST -Uri $uri -Headers $Headers -Body $jsonPayload -AuthContext $script:authContext
    $resultId = $result.id
    Write-Host "Named location created successfully (ID: $resultId)" -ForegroundColor Green
    return $result
  }
  catch {
    $errMsg = $_.Exception.Message
    if ($_.ErrorDetails) {
      $errDetails = $_.ErrorDetails.Message
      Write-Warning "Failed to create named location: $errMsg - Details: $errDetails"
    }
    else {
      Write-Warning "Failed to create named location: $errMsg"
    }
    return $null
  }
}

# Main execution
try {
  Load-EnvFile -Path $EnvFile
  $authContext = Get-GraphAuthContextFromEnv
  $tenantId = $authContext.TenantId
  
  if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputFolder = Join-Path -Path 'output' -ChildPath "sign-in-locations-$ts"
  }
  
  New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null
  
  Write-Host "`n=== Sign-In Location Discovery ===" -ForegroundColor Cyan
  Write-Host "Tenant ID: $tenantId"
  Write-Host "Days past: $DaysPast"
  Write-Host "Output folder: $OutputFolder`n"
  
  # Authenticate
  $token = Get-GraphTokenFromEnv
  Write-Host "Auth method: $($authContext.AuthMethod)" -ForegroundColor Cyan
  $headers = if ($authContext.AuthMethod -eq 'Delegated') { @{} } else { @{ Authorization = "Bearer $token" } }

  # Compute a usable default named location name if none is provided
  $tenantDisplayName = Get-TenantDisplayName -Headers $headers
  if ([string]::IsNullOrWhiteSpace($NamedLocationName)) {
    $NamedLocationName = Get-DefaultNamedLocationName -TenantDisplayName $tenantDisplayName -TenantId $tenantId
  }
  
  # Get locations from sign-in logs
  $locations = Get-SignInLocations -Headers $headers -DaysPast $DaysPast -IncludeUnknown $IncludeUnknownLocations
  
  if ($locations.Count -eq 0) {
    Write-Warning "No locations found in sign-in logs."
  }
  else {
    Write-Host "`nDiscovered $($locations.Count) unique locations:" -ForegroundColor Green
    $locations.Keys | Sort-Object | ForEach-Object {
      $loc = $locations[$_]
      Write-Host "  - $_ (count: $($loc.count))" -ForegroundColor Gray
    }
  }
  
  # Export results
  $exportPath = Join-Path $OutputFolder 'discovered-locations.json'
  $exportData = @{
    discoveredAt  = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'
    daysPast      = $DaysPast
    locationCount = $locations.Count
    locations     = $locations
  }
  $exportData | ConvertTo-Json -Depth 3 | Set-Content $exportPath
  Write-Host "`nResults exported to: $exportPath" -ForegroundColor Green
  
  # Create named location if requested
  if ($CreateNamedLocation -and $locations.Count -gt 0) {
    Write-Host "`nAttempting to create named location (experimental)..." -ForegroundColor Yellow
    $provenanceNote = "Auto-generated from sign-in log location discovery (past $DaysPast days) on $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'); includeUnknownLocations=$IncludeUnknownLocations."
    Write-Host "Provenance note: $provenanceNote" -ForegroundColor Gray
    Write-Host "Note: countryNamedLocation in Graph supports displayName but not a writable description field." -ForegroundColor Gray
    $namedLoc = Create-NamedLocation -Headers $headers -Name $NamedLocationName -Locations $locations
    if ($namedLoc) {
      $namedLocPath = Join-Path $OutputFolder 'created-named-location.json'
      $namedLoc | ConvertTo-Json -Depth 3 | Set-Content $namedLocPath
      Write-Host "Named location details exported to: $namedLocPath" -ForegroundColor Green
      $namedLocMetaPath = Join-Path $OutputFolder 'created-named-location-metadata.json'
      $namedLocMetadata = @{
        generatedNamedLocationName = $NamedLocationName
        tenantDisplayName          = if ([string]::IsNullOrWhiteSpace($tenantDisplayName)) { $null } else { $tenantDisplayName }
        tenantId                   = $tenantId
        generatedAt                = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'
        daysPast                   = $DaysPast
        includeUnknownLocations    = [bool]$IncludeUnknownLocations
        provenanceNote             = $provenanceNote
      }
      $namedLocMetadata | ConvertTo-Json -Depth 3 | Set-Content $namedLocMetaPath
      Write-Host "Named location metadata exported to: $namedLocMetaPath" -ForegroundColor Green
    }
    else {
      Write-Warning "Named location creation failed. Review discovered-locations.json and create manually in Azure AD admin center."
    }
  }
  
  Write-Host "`n=== Discovery Complete ===" -ForegroundColor Cyan
}
catch {
  $errMsg = $_.Exception.Message
  Write-Error "Script failed: $errMsg"
  exit 1
}

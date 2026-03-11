[CmdletBinding()]
param(
  [string]$Endpoint = 'ActiveSync'
)

$ErrorActionPreference = 'Stop'

function Get-BasicAuthorizationHeader {
  param([pscredential]$Credential)

  $plain = '{0}:{1}' -f $Credential.UserName, $Credential.GetNetworkCredential().Password
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($plain)
  return 'Basic ' + [Convert]::ToBase64String($bytes)
}

$targets = @{
  ActiveSync = 'https://outlook.office365.com/Microsoft-Server-ActiveSync'
  IMAP       = 'https://outlook.office365.com/imap'
}

if (-not $targets.ContainsKey($Endpoint)) {
  throw "Unsupported endpoint '$Endpoint'. Use ActiveSync or IMAP."
}

$credential = Get-Credential -Message 'Enter the excluded test user credential'
$uri = $targets[$Endpoint]
$headers = @{
  Authorization = Get-BasicAuthorizationHeader -Credential $credential
}

Write-Host "Attempting legacy-style auth against $Endpoint endpoint: $uri" -ForegroundColor Cyan
Write-Host 'Non-production warning: use this helper only in test tenants.' -ForegroundColor Yellow
Write-Host 'Expected result:' -ForegroundColor Yellow
Write-Host '- The request may fail because Microsoft 365 has deprecated many legacy auth paths.' -ForegroundColor Yellow
Write-Host '- Even a failed request can still create a useful legacy-style sign-in event for CA review.' -ForegroundColor Yellow

try {
  Invoke-WebRequest -Method GET -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 30 | Out-Null
  Write-Host 'Request completed without a transport error.' -ForegroundColor Green
}
catch {
  Write-Host "Request failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host 'Next step: review Entra sign-in logs for a legacy-auth style attempt from this user.' -ForegroundColor Cyan

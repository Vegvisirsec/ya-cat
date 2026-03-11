[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$TenantId,

  [string]$ClientId = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'
)

$ErrorActionPreference = 'Stop'

$deviceCodeUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode"
$tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$scope = 'https://graph.microsoft.com/User.Read offline_access openid profile'

Write-Host 'Requesting a device code for Microsoft Graph...' -ForegroundColor Cyan
Write-Host 'Non-production warning: use this helper only in test tenants.' -ForegroundColor Yellow
$deviceCode = Invoke-RestMethod -Method POST -Uri $deviceCodeUri -Body @{
  client_id = $ClientId
  scope     = $scope
}

Write-Host ''
Write-Host "User code: $($deviceCode.user_code)" -ForegroundColor Green
Write-Host "Verification URL: $($deviceCode.verification_uri)" -ForegroundColor Green
Write-Host ''
Write-Host 'Complete the device code sign-in with the excluded test user.' -ForegroundColor Yellow
Write-Host 'Expected result:' -ForegroundColor Yellow
Write-Host '- The excluded user should avoid the report-only block from CA-BL-005.' -ForegroundColor Yellow
Write-Host '- A non-excluded user should trigger the device-code-flow policy.' -ForegroundColor Yellow

Start-Process $deviceCode.verification_uri

while ($true) {
  Start-Sleep -Seconds $deviceCode.interval
  try {
    $token = Invoke-RestMethod -Method POST -Uri $tokenUri -Body @{
      grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
      client_id   = $ClientId
      device_code = $deviceCode.device_code
    }
    Write-Host 'Device code flow completed successfully.' -ForegroundColor Green
    break
  }
  catch {
    $payload = $null
    try {
      $payload = $_.ErrorDetails.Message | ConvertFrom-Json
    }
    catch {
      throw
    }

    if ($payload.error -in @('authorization_pending','slow_down')) {
      continue
    }

    Write-Host "Device code flow failed: $($payload.error_description)" -ForegroundColor Yellow
    break
  }
}

Write-Host 'Next step: review Entra sign-in logs for the device code flow attempt.' -ForegroundColor Cyan

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$url = 'https://portal.office.com'

Write-Host 'Launching an interactive Microsoft 365 browser sign-in test.' -ForegroundColor Cyan
Write-Host 'Non-production warning: use this helper only in test tenants.' -ForegroundColor Yellow
Write-Host 'Expected result for the excluded test user:' -ForegroundColor Yellow
Write-Host '- Sign-in should succeed without this policy enforcing MFA or managed-device requirements.' -ForegroundColor Yellow
Write-Host '- Compare the result with a non-excluded user to confirm the policy signal difference.' -ForegroundColor Yellow
Write-Host '- Check Entra sign-in logs afterwards for report-only details.' -ForegroundColor Yellow

Start-Process $url

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$url = 'https://portal.office.com'

Write-Host 'Launching the sign-in start point for an authentication transfer test.' -ForegroundColor Cyan
Write-Host 'Non-production warning: use this helper only in test tenants.' -ForegroundColor Yellow
Write-Host 'Use the excluded test user and complete a mobile-assisted sign-in if the current Microsoft sign-in UX offers it.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Suggested manual flow:' -ForegroundColor Yellow
Write-Host '1. Start the sign-in in the desktop browser.' -ForegroundColor Yellow
Write-Host '2. Choose a mobile-assisted or Authenticator transfer method if shown.' -ForegroundColor Yellow
Write-Host '3. Complete the sign-in on the phone and observe whether the sign-in succeeds.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Expected result:' -ForegroundColor Yellow
Write-Host '- The excluded user should avoid the CA-BL-006 report-only block.' -ForegroundColor Yellow
Write-Host '- A non-excluded user should surface the authentication transfer policy in sign-in logs if the transfer method is used.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Review Entra sign-in logs afterwards and confirm the authentication transfer flow was recorded.' -ForegroundColor Cyan

Start-Process $url

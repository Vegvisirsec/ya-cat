<#
.SYNOPSIS
  Provides pluggable authentication methods for Microsoft Graph API access.

.DESCRIPTION
  Supports three authentication flows:
  - ClientSecret: Service principal with client ID and secret
  - ClientCertificate: Service principal with client ID and certificate
  - Delegated: Interactive OAuth2 user sign-in flow

  This module replaces inline Get-GraphToken implementations across the codebase.

.NOTES
  Multi-tenant considerations:
  - For multi-tenant deployments, use certificate-based auth (better rotation story)
  - Delegated flow requires interactive sign-in; not suitable for automation
  - Each flow requires appropriate app registration and permissions in target tenant
#>

<#
.FUNCTION Get-GraphTokenFromAuth
.SYNOPSIS
  Acquire Microsoft Graph access token using specified authentication method.

.PARAMETER AuthMethod
  Authentication method to use: 'ClientSecret', 'ClientCertificate', or 'Delegated'

.PARAMETER TenantId
  Azure AD tenant ID (required for all methods)

.PARAMETER ClientId
  Application (client) ID (required for ClientSecret and ClientCertificate)

.PARAMETER ClientSecret
  Client secret (required for ClientSecret method)

.PARAMETER CertificatePath
  Path to certificate file (.pfx or .cer) (required for ClientCertificate method)

.PARAMETER CertificateThumbprint
  Thumbprint of certificate in cert store (alternative to CertificatePath for ClientCertificate)

.PARAMETER CertificatePassword
  Password for .pfx certificate file (optional, may be needed for ClientCertificate)

.PARAMETER Scope
  Graph scope for token request (default: 'https://graph.microsoft.com/.default')

.EXAMPLE
  # Client secret method
  $token = Get-GraphTokenFromAuth -AuthMethod ClientSecret `
    -TenantId $tenantId -ClientId $clientId -ClientSecret $secret

  # Client certificate method
  $token = Get-GraphTokenFromAuth -AuthMethod ClientCertificate `
    -TenantId $tenantId -ClientId $clientId -CertificatePath 'cert.pfx' -CertificatePassword $pass

  # Delegated method (interactive)
  $token = Get-GraphTokenFromAuth -AuthMethod Delegated -TenantId $tenantId -ClientId $clientId
#>
function Get-GraphTokenFromAuth {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ClientSecret', 'ClientCertificate', 'Delegated')]
    [string]$AuthMethod,

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [string]$CertificatePath,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [SecureString]$CertificatePassword,

    [Parameter(Mandatory = $false)]
    [string]$Scope = 'https://graph.microsoft.com/.default'
  )

  switch ($AuthMethod) {
    'ClientSecret' {
      return Get-GraphTokenClientSecret -TenantId $TenantId -ClientId $ClientId `
        -ClientSecret $ClientSecret -Scope $Scope
    }
    'ClientCertificate' {
      return Get-GraphTokenClientCertificate -TenantId $TenantId -ClientId $ClientId `
        -CertificatePath $CertificatePath -CertificateThumbprint $CertificateThumbprint `
        -CertificatePassword $CertificatePassword -Scope $Scope
    }
    'Delegated' {
      return Get-GraphTokenDelegated -TenantId $TenantId -ClientId $ClientId -Scope $Scope
    }
  }
}

<#
.FUNCTION Get-GraphTokenClientSecret
.SYNOPSIS
  Acquire token using client credentials (client ID + secret).
#>
function Get-GraphTokenClientSecret {
  param(
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$Scope
  )

  if ([string]::IsNullOrWhiteSpace($ClientId)) {
    throw "ClientId required for ClientSecret authentication"
  }
  if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
    throw "ClientSecret required for ClientSecret authentication"
  }

  try {
    $body = @{
      client_id     = $ClientId
      scope         = $Scope
      client_secret = $ClientSecret
      grant_type    = 'client_credentials'
    }
    $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $resp = Invoke-RestMethod -Method Post -Uri $tokenUri -Body $body -ErrorAction Stop

    if (-not $resp.access_token) {
      throw "Token response missing access_token field"
    }

    return $resp.access_token
  }
  catch {
    Write-Error "Failed to acquire token via ClientSecret: $($_.Exception.Message)"
    throw
  }
}

<#
.FUNCTION Get-GraphTokenClientCertificate
.SYNOPSIS
  Acquire token using client credentials (client ID + certificate).

.NOTES
  Requires either:
  - CertificatePath: path to .pfx or .cer file with optional CertificatePassword
  - CertificateThumbprint: thumbprint of certificate in current user's cert store
#>
function Get-GraphTokenClientCertificate {
  param(
    [string]$TenantId,
    [string]$ClientId,
    [string]$CertificatePath,
    [string]$CertificateThumbprint,
    [SecureString]$CertificatePassword,
    [string]$Scope
  )

  if ([string]::IsNullOrWhiteSpace($ClientId)) {
    throw "ClientId required for ClientCertificate authentication"
  }

  if ([string]::IsNullOrWhiteSpace($CertificatePath) -and [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    throw "Either CertificatePath or CertificateThumbprint required for ClientCertificate authentication"
  }

  try {
    # Load certificate
    $cert = $null
    if (-not [string]::IsNullOrWhiteSpace($CertificatePath)) {
      if (-not (Test-Path $CertificatePath)) {
        throw "Certificate file not found: $CertificatePath"
      }

      $certPassword = $null
      if ($null -ne $CertificatePassword) {
        $certPassword = ConvertFrom-SecureString -SecureString $CertificatePassword -AsPlainText
      }

      $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 `
        -ArgumentList @($CertificatePath, $certPassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
    }
    else {
      $certStore = Get-Item cert:\CurrentUser\My
      $cert = $certStore.GetChildItem($CertificateThumbprint) | Select-Object -First 1
      if ($null -eq $cert) {
        throw "Certificate not found in cert store with thumbprint: $CertificateThumbprint"
      }
    }

    # Build JWT assertion
    $jwtHeader = @{
      alg = "RS256"
      typ = "JWT"
      x5t = [System.Convert]::ToBase64String($cert.GetCertHash())
    } | ConvertTo-Json -Compress

    $now = [System.DateTime]::UtcNow
    $jwtPayload = @{
      aud = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
      exp = [int]$now.AddMinutes(10).Subtract([System.DateTime]::UnixEpoch).TotalSeconds
      iat = [int]$now.Subtract([System.DateTime]::UnixEpoch).TotalSeconds
      iss = $ClientId
      sub = $ClientId
    } | ConvertTo-Json -Compress

    # Encode JWT parts
    $jwtHeaderEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($jwtHeader)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $jwtPayloadEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($jwtPayload)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $jwtUnsigned = "$jwtHeaderEncoded.$jwtPayloadEncoded"

    # Sign JWT
    $rsa = $cert.PrivateKey
    if ($null -eq $rsa) {
      throw "Certificate does not have a private key"
    }

    $hashAlgo = [System.Security.Cryptography.HashAlgorithmName]::SHA256
    $padding = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    $signatureBytes = $rsa.SignData([System.Text.Encoding]::UTF8.GetBytes($jwtUnsigned), $hashAlgo, $padding)
    $jwtSignature = [Convert]::ToBase64String($signatureBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    $jwtAssertion = "$jwtUnsigned.$jwtSignature"

    # Exchange JWT for token
    $body = @{
      client_id             = $ClientId
      scope                 = $Scope
      client_assertion      = $jwtAssertion
      client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
      grant_type            = 'client_credentials'
    }

    $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $resp = Invoke-RestMethod -Method Post -Uri $tokenUri -Body $body -ErrorAction Stop

    if (-not $resp.access_token) {
      throw "Token response missing access_token field"
    }

    return $resp.access_token
  }
  catch {
    Write-Error "Failed to acquire token via ClientCertificate: $($_.Exception.Message)"
    throw
  }
}

<#
.FUNCTION Get-GraphTokenDelegated
.SYNOPSIS
  Acquire token using delegated flow (interactive user sign-in).

.NOTES
  - Requires MSAL.PS module
  - Launches browser for interactive authentication
  - Token includes user context; useful for audit/compliance scenarios
  - Not suitable for unattended automation
#>
function Get-GraphTokenDelegated {
  param(
    [string]$TenantId,
    [string]$ClientId,
    [string]$Scope
  )

  if ([string]::IsNullOrWhiteSpace($ClientId)) {
    throw "ClientId required for Delegated authentication"
  }

  # Check for MSAL.PS module
  if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
    Write-Error "MSAL.PS module is required for delegated authentication. Install with: Install-Module MSAL.PS"
    throw "MSAL.PS module not found"
  }

  try {
    Import-Module MSAL.PS -ErrorAction Stop

    $msalParams = @{
      ClientId    = $ClientId
      TenantId    = $TenantId
      Scopes      = @($Scope)
      Interactive = $true
    }

    $authResult = Get-MsalToken @msalParams

    if (-not $authResult.AccessToken) {
      throw "MSAL authentication failed or was cancelled"
    }

    Write-Verbose "Token acquired via delegated flow for user: $($authResult.ClaimsPrincipal.FindFirst('preferred_username').Value)"
    return $authResult.AccessToken
  }
  catch {
    Write-Error "Failed to acquire token via Delegated flow: $($_.Exception.Message)"
    throw
  }
}

<#
.FUNCTION Get-GraphToken
.SYNOPSIS
  Legacy wrapper for backward compatibility.
  
.NOTES
  Maintained for compatibility with existing scripts.
  New scripts should use Get-GraphTokenFromAuth.
#>
function Get-GraphToken {
  param(
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$Scope = 'https://graph.microsoft.com/.default'
  )

  return Get-GraphTokenFromAuth -AuthMethod ClientSecret `
    -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope $Scope
}

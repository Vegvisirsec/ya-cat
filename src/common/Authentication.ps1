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

function Get-OptionalEnvironmentValue {
  param([string]$Name)

  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $null
  }

  return $value
}

function Get-RequiredEnvironmentValue {
  param([string]$Name)

  $value = Get-OptionalEnvironmentValue -Name $Name
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Missing required env var: $Name"
  }

  return $value
}

function Get-GraphAuthContextFromEnv {
  [CmdletBinding()]
  param(
    [string]$DefaultAuthMethod = 'ClientSecret',
    [string]$DefaultScope = 'https://graph.microsoft.com/.default'
  )

  $tenantId = Get-RequiredEnvironmentValue -Name 'TENANT_ID'
  $clientId = Get-RequiredEnvironmentValue -Name 'CLIENT_ID'

  $authMethod = Get-OptionalEnvironmentValue -Name 'AUTH_METHOD'
  if ([string]::IsNullOrWhiteSpace($authMethod)) {
    $authMethod = $DefaultAuthMethod
  }

  if ($authMethod -notin @('ClientSecret', 'ClientCertificate', 'Delegated')) {
    throw "Invalid AUTH_METHOD '$authMethod'. Expected one of: ClientSecret, ClientCertificate, Delegated"
  }

  $scope = Get-OptionalEnvironmentValue -Name 'GRAPH_SCOPE'
  if ([string]::IsNullOrWhiteSpace($scope)) {
    $scope = $DefaultScope
  }

  $context = [ordered]@{
    AuthMethod = $authMethod
    TenantId   = $tenantId
    ClientId   = $clientId
    Scope      = $scope
  }

  switch ($authMethod) {
    'ClientSecret' {
      $context.ClientSecret = Get-RequiredEnvironmentValue -Name 'CLIENT_SECRET'
    }
    'ClientCertificate' {
      $certificatePath = Get-OptionalEnvironmentValue -Name 'CERTIFICATE_PATH'
      $certificateThumbprint = Get-OptionalEnvironmentValue -Name 'CERTIFICATE_THUMBPRINT'
      $certificatePassword = Get-OptionalEnvironmentValue -Name 'CERTIFICATE_PASSWORD'

      if ([string]::IsNullOrWhiteSpace($certificatePath) -and [string]::IsNullOrWhiteSpace($certificateThumbprint)) {
        throw "ClientCertificate authentication requires CERTIFICATE_PATH or CERTIFICATE_THUMBPRINT"
      }

      if (-not [string]::IsNullOrWhiteSpace($certificatePath)) {
        $context.CertificatePath = $certificatePath
      }
      if (-not [string]::IsNullOrWhiteSpace($certificateThumbprint)) {
        $context.CertificateThumbprint = $certificateThumbprint
      }
      if (-not [string]::IsNullOrWhiteSpace($certificatePassword)) {
        $context.CertificatePassword = ConvertTo-SecureString -String $certificatePassword -AsPlainText -Force
      }
    }
    'Delegated' {
      $delegatedScopes = @()
      if (-not [string]::IsNullOrWhiteSpace($scope) -and $scope -ne 'https://graph.microsoft.com/.default') {
        $delegatedScopes = @($scope -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      }
      if ($delegatedScopes.Count -eq 0) {
        $delegatedScopes = @(
          'Policy.Read.All',
          'Policy.ReadWrite.ConditionalAccess',
          'AuditLog.Read.All',
          'Directory.Read.All',
          'Group.ReadWrite.All',
          'Application.Read.All'
        )
      }

      $context.DelegatedScopes = @($delegatedScopes)
    }
  }

  return [pscustomobject]$context
}

function Get-GraphTokenFromEnv {
  [CmdletBinding()]
  param(
    [string]$DefaultAuthMethod = 'ClientSecret',
    [string]$DefaultScope = 'https://graph.microsoft.com/.default'
  )

  $context = Get-GraphAuthContextFromEnv -DefaultAuthMethod $DefaultAuthMethod -DefaultScope $DefaultScope
  $params = @{
    AuthMethod = $context.AuthMethod
    TenantId   = $context.TenantId
    ClientId   = $context.ClientId
    Scope      = $context.Scope
  }

  if ($context.PSObject.Properties.Name -contains 'ClientSecret') {
    $params.ClientSecret = $context.ClientSecret
  }
  if ($context.PSObject.Properties.Name -contains 'CertificatePath') {
    $params.CertificatePath = $context.CertificatePath
  }
  if ($context.PSObject.Properties.Name -contains 'CertificateThumbprint') {
    $params.CertificateThumbprint = $context.CertificateThumbprint
  }
  if ($context.PSObject.Properties.Name -contains 'CertificatePassword') {
    $params.CertificatePassword = $context.CertificatePassword
  }

  return Get-GraphTokenFromAuth @params
}

function Connect-GraphDelegatedSession {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [pscustomobject]$AuthContext
  )

  if ($AuthContext.AuthMethod -ne 'Delegated') {
    throw "Connect-GraphDelegatedSession only supports Delegated auth contexts"
  }

  if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Error "Microsoft.Graph.Authentication module is required for delegated authentication. Install with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    throw "Microsoft.Graph.Authentication module not found"
  }

  Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

  $existingContext = Get-MgContext -ErrorAction SilentlyContinue
  $requiredScopes = @($AuthContext.DelegatedScopes)
  $needsConnect = $true

  if ($null -ne $existingContext -and $existingContext.AuthType -eq 'Delegated') {
    $existingScopes = @()
    if ($existingContext.Scopes) {
      $existingScopes = @($existingContext.Scopes)
    }

    $scopeMissing = $false
    foreach ($scope in $requiredScopes) {
      if ($existingScopes -notcontains $scope) {
        $scopeMissing = $true
        break
      }
    }

    if (($existingContext.TenantId -eq $AuthContext.TenantId) -and ($existingContext.ClientId -eq $AuthContext.ClientId) -and -not $scopeMissing) {
      $needsConnect = $false
    }
  }

  if ($needsConnect) {
    Connect-MgGraph -ClientId $AuthContext.ClientId -TenantId $AuthContext.TenantId -Scopes $requiredScopes -ErrorAction Stop | Out-Null
  }

  return Get-MgContext -ErrorAction Stop
}

function Invoke-GraphRequest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('GET','POST','PATCH','DELETE')]
    [string]$Method,

    [Parameter(Mandatory = $true)]
    [string]$Uri,

    [Parameter(Mandatory = $true)]
    [pscustomobject]$AuthContext,

    [hashtable]$Headers,

    $Body,

    [int]$JsonDepth = 50
  )

  if ($AuthContext.AuthMethod -eq 'Delegated') {
    Connect-GraphDelegatedSession -AuthContext $AuthContext | Out-Null

    $params = @{
      Method     = $Method
      Uri        = $Uri
      OutputType = 'PSObject'
    }

    if ($Headers -and $Headers.Keys.Count -gt 0) {
      $params.Headers = $Headers
    }

    if ($null -ne $Body) {
      if ($Body -is [string]) {
        $params.Body = $Body
      }
      else {
        $params.Body = $Body | ConvertTo-Json -Depth $JsonDepth
      }
    }

    return Invoke-MgGraphRequest @params
  }

  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType 'application/json'
  }

  $jsonBody = $Body | ConvertTo-Json -Depth $JsonDepth
  return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType 'application/json' -Body $jsonBody
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
  - Requires Microsoft.Graph.Authentication module
  - Launches browser-backed Connect-MgGraph authentication
  - User context is used for subsequent Graph requests in the session
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

  try {
    $authContext = [pscustomobject]@{
      AuthMethod      = 'Delegated'
      TenantId        = $TenantId
      ClientId        = $ClientId
      DelegatedScopes = if (-not [string]::IsNullOrWhiteSpace($Scope) -and $Scope -ne 'https://graph.microsoft.com/.default') {
        @($Scope -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      }
      else {
        @(
          'Policy.Read.All',
          'Policy.ReadWrite.ConditionalAccess',
          'AuditLog.Read.All',
          'Directory.Read.All',
          'Group.ReadWrite.All',
          'Application.Read.All'
        )
      }
    }

    $context = Connect-GraphDelegatedSession -AuthContext $authContext
    Write-Verbose "Graph delegated session established for user: $($context.Account)"
    return $null
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

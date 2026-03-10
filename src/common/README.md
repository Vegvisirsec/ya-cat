# Common utilities

## Authentication.ps1

Provides pluggable authentication for Microsoft Graph API access.

### Quick start

**Using client secret (default):**
```powershell
. .\src\common\Authentication.ps1

$token = Get-GraphToken `
  -TenantId 'your-tenant-id' `
  -ClientId 'your-app-client-id' `
  -ClientSecret 'your-secret'
```

**Using certificate:**
```powershell
$token = Get-GraphTokenFromAuth `
  -AuthMethod ClientCertificate `
  -TenantId 'your-tenant-id' `
  -ClientId 'your-app-client-id' `
  -CertificatePath '/path/to/cert.pfx' `
  -CertificatePassword (ConvertTo-SecureString 'password' -AsPlainText -Force)
```

Or with certificate thumbprint from cert store:
```powershell
$token = Get-GraphTokenFromAuth `
  -AuthMethod ClientCertificate `
  -TenantId 'your-tenant-id' `
  -ClientId 'your-app-client-id' `
  -CertificateThumbprint 'abcd1234...'
```

**Using delegated flow (interactive, via Microsoft Graph PowerShell):**
```powershell
Connect-GraphDelegatedSession -AuthContext ([pscustomobject]@{
  AuthMethod = 'Delegated'
  TenantId = 'your-tenant-id'
  ClientId = 'your-app-client-id'
  DelegatedScopes = @('Policy.Read.All')
})
```

This launches a browser-backed `Connect-MgGraph` sign-in and uses your user context for subsequent Graph requests.

### Environment variables

Scripts automatically load from `.env.local`:

```
TENANT_ID=your-tenant-id
CLIENT_ID=your-app-client-id
AUTH_METHOD=ClientSecret
CLIENT_SECRET=your-secret
GRAPH_SCOPE=https://graph.microsoft.com/.default
```

Certificate example:

```
TENANT_ID=your-tenant-id
CLIENT_ID=your-app-client-id
AUTH_METHOD=ClientCertificate
CERTIFICATE_THUMBPRINT=abcd1234...
GRAPH_SCOPE=https://graph.microsoft.com/.default
```

Delegated example:

```
TENANT_ID=your-tenant-id
CLIENT_ID=your-app-client-id
AUTH_METHOD=Delegated
GRAPH_SCOPE=https://graph.microsoft.com/.default
```

### Authentication methods comparison

| Aspect | Client Secret | Client Certificate | Delegated |
|--------|---------------|-------------------|-----------|
| **Method** | Service principal + secret | Service principal + cert | User OAuth2 |
| **Automation** | ✓ Yes | ✓ Yes | ✗ Interactive only |
| **Multi-tenant** | Fair | ✓ Excellent | Case-by-case |
| **Credential rotation** | Manual | PKI workflow | None |
| **Audit trail** | App identity | App identity | User identity |
| **Setup complexity** | Simple | Medium | Simple |
| **Recommended for** | Single tenant dev | Multi-tenant prod | Audit/compliance |

### Prerequisites

**For Client Secret:**
- App registration with `Policy.ReadWrite.ConditionalAccess` permission
- Store secret securely in `.env.local` (never commit)

**For Client Certificate:**
- App registration with `Policy.ReadWrite.ConditionalAccess` permission
- Certificate in `.pfx` format with private key, or thumbprint in cert store
- Optional: certificate password if `.pfx` is encrypted

**For Delegated flow:**
- App registration with `Policy.ReadWrite.ConditionalAccess` delegated permission
- Microsoft Graph auth module: `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser`
- Interactive sign-in capability

### Function reference

#### Get-GraphTokenFromAuth
Main pluggable authentication function.

```powershell
Get-GraphTokenFromAuth -AuthMethod <method> [parameters...]
```

**Parameters:**
- `-AuthMethod`: `ClientSecret`, `ClientCertificate`, or `Delegated` (required)
- `-TenantId`: Azure AD tenant ID (required)
- `-ClientId`: App client ID (required for all methods)
- `-ClientSecret`: Secret string (required for ClientSecret)
- `-CertificatePath`: Path to `.pfx` or `.cer` (optional for ClientCertificate)
- `-CertificateThumbprint`: Cert store thumbprint (optional for ClientCertificate)
- `-CertificatePassword`: Password as SecureString (optional for ClientCertificate)
- `-Scope`: Graph scope (default: `https://graph.microsoft.com/.default`); delegated auth can also use a comma- or space-separated scope list

#### Get-GraphToken (legacy)
Backward-compatibility wrapper using client secret.

```powershell
Get-GraphToken -TenantId $id -ClientId $cid -ClientSecret $secret -Scope $scope
```

### Integration in scripts

All deploy, evaluate, and graph utility scripts source `Authentication.ps1` and now resolve auth from `.env.local` through `Get-GraphAuthContextFromEnv` / `Get-GraphTokenFromEnv`.

Set `AUTH_METHOD=ClientSecret`, `ClientCertificate`, or `Delegated` and provide the matching environment variables.

### Troubleshooting

**"Missing required env var: TENANT_ID"**
- Ensure `.env.local` exists and contains `TENANT_ID=...`
- Verify no trailing/leading spaces

**"Certificate not found in cert store with thumbprint: xyz"**
- List available certs: `Get-ChildItem cert:\CurrentUser\My`
- Copy exact thumbprint (no spaces)
- Use `-CertificatePath` if cert is in a file instead

**Microsoft.Graph.Authentication module not found**
- Install: `Install-Module Microsoft.Graph.Authentication -Force -Scope CurrentUser`
- Required only for delegated flow

### Future enhancements

Planned additions:
- Managed identity auth (for Azure automation contexts)
- Client assertion flow variant
- Token caching layer
- Scope parameter per script (not just `.default`)

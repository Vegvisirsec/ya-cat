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

**Using delegated flow (interactive):**
```powershell
$token = Get-GraphTokenFromAuth `
  -AuthMethod Delegated `
  -TenantId 'your-tenant-id' `
  -ClientId 'your-app-client-id'
```

This launches a browser for interactive sign-in and includes your user context in the token.

### Environment variables

Scripts automatically load from `.env.local`:

```
TENANT_ID=your-tenant-id
CLIENT_ID=your-app-client-id
CLIENT_SECRET=your-secret
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
- MSAL.PS module: `Install-Module MSAL.PS -Force`
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
- `-Scope`: Graph scope (default: `https://graph.microsoft.com/.default`)

#### Get-GraphToken (legacy)
Backward-compatibility wrapper using client secret.

```powershell
Get-GraphToken -TenantId $id -ClientId $cid -ClientSecret $secret -Scope $scope
```

### Integration in scripts

All deploy, evaluate, and graph utility scripts source `Authentication.ps1` and use `Get-GraphToken`. To support other auth methods, update `.env.local` or pass parameters to the scripts directly.

Example for scripts that accept auth customization:
```bash
# Future: certificate-based deployment
./Deploy-CAPolicies.ps1 -AuthMethod ClientCertificate -CertThumbprint abc123
```

### Troubleshooting

**"Missing required env var: TENANT_ID"**
- Ensure `.env.local` exists and contains `TENANT_ID=...`
- Verify no trailing/leading spaces

**"Certificate not found in cert store with thumbprint: xyz"**
- List available certs: `Get-ChildItem cert:\CurrentUser\My`
- Copy exact thumbprint (no spaces)
- Use `-CertificatePath` if cert is in a file instead

**MSAL.PS module not found**
- Install: `Install-Module MSAL.PS -Force -Scope CurrentUser`
- Required only for delegated flow

### Future enhancements

Planned additions:
- Managed identity auth (for Azure automation contexts)
- Client assertion flow variant
- Token caching layer
- Scope parameter per script (not just `.default`)

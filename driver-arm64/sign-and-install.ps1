#Requires -RunAsAdministrator
<#
  sign-and-install.ps1

  Installs the FuelTech ARM64 libusb-win32 driver on Windows 11 on ARM by
  generating a self-signed driver catalog (no WDK / Inf2Cat needed - uses only
  built-in PowerShell) and installing the package with pnputil.

  PREREQUISITE: the VM must be in Test Mode:
      bcdedit /set testsigning on   (Secure Boot off), reboot, "Test Mode" watermark.

  USAGE: right-click this file -> "Run with PowerShell" as Administrator, OR:
      powershell -ExecutionPolicy Bypass -File .\sign-and-install.ps1
#>

$ErrorActionPreference = 'Stop'
$drv = $PSScriptRoot
Write-Host "Driver folder: $drv" -ForegroundColor Cyan

# 0. Make sure the INF references the catalog we are about to create.
$inf = Join-Path $drv 'datalogger.inf'
$txt = Get-Content $inf -Raw
if ($txt -notmatch '(?im)^\s*CatalogFile\s*=') {
    $txt = $txt -replace '(?im)(^\s*DriverVer\s*=.*$)', "`$1`r`nCatalogFile = datalogger.cat"
    Set-Content -Path $inf -Value $txt -Encoding ASCII
    Write-Host "Added 'CatalogFile = datalogger.cat' to the INF." -ForegroundColor Green
}

# 1. Create a self-signed code-signing certificate.
$cert = New-SelfSignedCertificate -Type CodeSigningCert `
    -Subject 'CN=FuelTech ARM64 Driver (Test)' `
    -CertStoreLocation Cert:\CurrentUser\My `
    -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(5)
Write-Host "Created signing cert: $($cert.Thumbprint)" -ForegroundColor Green

# 2. Trust the cert machine-wide. Use the PUBLIC cert (.cer) via certutil -addstore;
#    importing the PFX (with private key) into Root does NOT reliably register it
#    as a trust anchor, which makes pnputil report "publisher not trusted".
$cer = Join-Path $env:TEMP 'ftarm64.cer'
Export-Certificate -Cert $cert -FilePath $cer -Type CERT -Force | Out-Null
certutil -addstore -f Root             $cer | Out-Null
certutil -addstore -f TrustedPublisher $cer | Out-Null
Remove-Item $cer -Force
Write-Host "Certificate trusted (Root + TrustedPublisher, machine-wide)." -ForegroundColor Green

# 3. Build a SHA-256 catalog covering the driver files.
$cat = Join-Path $drv 'datalogger.cat'
if (Test-Path $cat) { Remove-Item $cat -Force }
New-FileCatalog -Path $drv -CatalogFilePath $cat -CatalogVersion 2 | Out-Null
Write-Host "Catalog created: $cat" -ForegroundColor Green

# 4. Sign the catalog with our trusted cert.
#    -IncludeChain All is REQUIRED: the cert is self-signed (a root), and the
#    default (NotRoot) would exclude it from the embedded signature, leaving
#    pnputil unable to establish the publisher ("publisher not trusted").
$sig = Set-AuthenticodeSignature -FilePath $cat -Certificate $cert `
        -IncludeChain All -HashAlgorithm SHA256
Write-Host "Catalog signature status: $($sig.Status)" -ForegroundColor Green

# 5. Install the driver package onto any matching present device.
Write-Host "Installing driver package..." -ForegroundColor Cyan
pnputil /add-driver $inf /install

Write-Host "`nDone. Check Device Manager - the FuelTech device should leave 'Other devices'." -ForegroundColor Cyan

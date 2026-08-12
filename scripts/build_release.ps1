# build_release.ps1
# Official one-command release build + packaging for pos_offline_desktop.
#
# This replaces the manual sequence:
#   flutter clean && flutter pub get && flutter build windows --release && iscc installer.iss
#
# It runs the verification script (scripts\verify_windows_build.ps1) AFTER the
# build and BEFORE packaging. If any required DLL / exe / data file is missing,
# packaging is aborted (exit 1) so a broken installer never reaches a customer.
#
# Usage (from project root):
#   powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1
#
# Params:
#   -LicenseSecretKey <key>   License signing key (same value used by license generators).
#                             Falls back to $env:LICENSE_SECRET_KEY.
#   -TrialLicenseKey  <key>   Built-in trial license key. Falls back to $env:TRIAL_LICENSE_KEY.
#   -InstallerScript  <path>  Inno Setup script to compile (default: installer.iss).
#   -SkipPackaging            Build + verify only; do NOT run Inno Setup.
#   -SkipLicenseCheck         Skip the secret-key guard (local dev builds without a license).

[CmdletBinding()]
param(
    [string]$LicenseSecretKey = $env:LICENSE_SECRET_KEY,
    [string]$TrialLicenseKey = $env:TRIAL_LICENSE_KEY,
    [string]$InstallerScript = "installer.iss",
    [switch]$SkipPackaging,
    [switch]$SkipLicenseCheck
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Get-Location).Path
$ScriptsDir  = Join-Path $ProjectRoot "scripts"
$VerifyScript = Join-Path $ScriptsDir "verify_windows_build.ps1"

# ────────────────────────────────────────────────────────────────────────────
# 0) Guard: a real license secret is required unless explicitly skipped.
#    This prevents building a silently-broken "CHANGE_ME" release.
# ────────────────────────────────────────────────────────────────────────────
if (-not $SkipLicenseCheck) {
    if ([string]::IsNullOrEmpty($LicenseSecretKey) -or $LicenseSecretKey -eq 'CHANGE_ME') {
        Write-Host "[ABORT] LICENSE_SECRET_KEY is empty or 'CHANGE_ME'." -ForegroundColor Red
        Write-Host "[ABORT] Pass -LicenseSecretKey <key> or set the LICENSE_SECRET_KEY env var." -ForegroundColor Red
        Write-Host "[ABORT] For a local non-licensed dev build use -SkipLicenseCheck (NOT for customers)." -ForegroundColor Yellow
        exit 1
    }
}

# ────────────────────────────────────────────────────────────────────────────
# 1) flutter clean
# ────────────────────────────────────────────────────────────────────────────
Write-Host "`n=== [1/5] flutter clean ===" -ForegroundColor Cyan
& flutter clean
if ($LASTEXITCODE -ne 0) { Write-Host "[ABORT] flutter clean failed." -ForegroundColor Red; exit 1 }

# ────────────────────────────────────────────────────────────────────────────
# 2) flutter pub get
# ────────────────────────────────────────────────────────────────────────────
Write-Host "`n=== [2/5] flutter pub get ===" -ForegroundColor Cyan
& flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Host "[ABORT] flutter pub get failed." -ForegroundColor Red; exit 1 }

# ────────────────────────────────────────────────────────────────────────────
# 3) flutter build windows --release
# ────────────────────────────────────────────────────────────────────────────
Write-Host "`n=== [3/5] flutter build windows --release ===" -ForegroundColor Cyan
$buildArgs = @("build", "windows", "--release")
if (-not $SkipLicenseCheck) {
    if (-not [string]::IsNullOrEmpty($LicenseSecretKey)) {
        $buildArgs += "--dart-define=LICENSE_SECRET_KEY=$LicenseSecretKey"
    }
    if (-not [string]::IsNullOrEmpty($TrialLicenseKey)) {
        $buildArgs += "--dart-define=TRIAL_LICENSE_KEY=$TrialLicenseKey"
    }
}
& flutter @buildArgs
if ($LASTEXITCODE -ne 0) { Write-Host "[ABORT] flutter build windows --release failed." -ForegroundColor Red; exit 1 }

# ────────────────────────────────────────────────────────────────────────────
# 4) Verification gate
# ────────────────────────────────────────────────────────────────────────────
Write-Host "`n=== [4/5] Verifying build output ===" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File $VerifyScript -ProjectRoot $ProjectRoot
if ($LASTEXITCODE -ne 0) {
    Write-Host "" -ForegroundColor Red
    Write-Host "`n[ABORT] Verification FAILED - some build outputs are missing." -ForegroundColor Red
    Write-Host "[ABORT] Packaging was STOPPED. Do NOT create an installer from this build." -ForegroundColor Red
    Write-Host "[ABORT] فشل التحقق - في ملفات ناقصة. تم إيقاف التغليف. ممنوع إنشاء installer من هذا البناء." -ForegroundColor Red
    Write-Host "[FIX]   Run 'flutter clean', check Windows Defender exclusions, then re-run this script." -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK] Verification passed. Proceeding to packaging." -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────────────
# 5) Inno Setup packaging
# ────────────────────────────────────────────────────────────────────────────
if ($SkipPackaging) {
    Write-Host "`n=== [5/5] Packaging skipped (-SkipPackaging) ===" -ForegroundColor Yellow
    Write-Host "Build + verification succeeded. Exiting."
    exit 0
}

Write-Host "`n=== [5/5] Inno Setup packaging ($InstallerScript) ===" -ForegroundColor Cyan

function Find-Iscc {
    $cmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 5\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 5\ISCC.exe",
        "C:\Program Files\Inno Setup 5\ISCC.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

$isccPath = Find-Iscc
if (-not $isccPath) {
    Write-Host "`n[ABORT] Inno Setup compiler (ISCC.exe) was NOT found." -ForegroundColor Red
    Write-Host "To install it, download from: https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
    Write-Host "Or install via Chocolatey: choco install innosetup -y (requires admin)." -ForegroundColor Yellow
    Write-Host "After installing, re-run this script." -ForegroundColor Yellow
    exit 1
}

& $isccPath $InstallerScript
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ABORT] Inno Setup compilation failed." -ForegroundColor Red
    exit 1
}

Write-Host "`n[DONE] Release build + verification + packaging completed successfully." -ForegroundColor Green
Write-Host "[DONE] اكتمل البناء والتحقق والتغليف بنجاح." -ForegroundColor Green
exit 0

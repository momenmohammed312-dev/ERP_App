# scripts/build_android_apk.ps1
# Release APK builder for MADAR ERP Android with injected production secrets.
#
# Reads secrets from build_secrets.local.json in the repo root.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\build_android_apk.ps1 -TrialDays 7
#   powershell -ExecutionPolicy Bypass -File scripts\build_android_apk.ps1 -TrialDays 7 -InstallOnDevice

param(
    [int]$TrialDays = 7,
    [switch]$InstallOnDevice,
    [string]$Target = "lib/main_all.dart"
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Get-Item $PSScriptRoot).Parent.FullName
$SecretsFile = Join-Path $ProjectRoot 'build_secrets.local.json'

if (-not (Test-Path -LiteralPath $SecretsFile)) {
    Write-Host "[ABORT] $SecretsFile not found in project root." -ForegroundColor Red
    exit 1
}

$secrets = Get-Content -LiteralPath $SecretsFile -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($secrets.LICENSE_SECRET_KEY) -or $secrets.LICENSE_SECRET_KEY -eq 'CHANGE_ME') {
    Write-Host "[ABORT] LICENSE_SECRET_KEY is empty or 'CHANGE_ME' in $SecretsFile." -ForegroundColor Red
    exit 1
}

# Defensive extraction for LICENSE_PUBLIC_KEY
$rawKey = if ($secrets.LICENSE_PUBLIC_KEY.value) {
    [string]$secrets.LICENSE_PUBLIC_KEY.value
} else {
    [string]$secrets.LICENSE_PUBLIC_KEY
}
$publicKeyPem = ($rawKey -replace "`r`n", '\n' -replace "`n", '\n').Trim()

Write-Host "=== Building Android Release APK (Trial: $TrialDays days) ===" -ForegroundColor Cyan
Write-Host "Injected Secrets:" -ForegroundColor Green
Write-Host "  - LICENSE_SECRET_KEY: [Configured]" -ForegroundColor Green
Write-Host "  - LICENSE_PUBLIC_KEY: [Configured]" -ForegroundColor Green
Write-Host "  - FREE_VERSION: true" -ForegroundColor Green
Write-Host "  - FREE_TRIAL_DAYS: $TrialDays" -ForegroundColor Green

$buildArgs = @(
    'build', 'apk', '--release',
    '-t', $Target,
    '--dart-define=FLAVOR=all',
    '--dart-define=ENABLE_ALL_FEATURES=true',
    '--dart-define=FREE_VERSION=true',
    "--dart-define=FREE_TRIAL_DAYS=$TrialDays",
    "--dart-define=LICENSE_SECRET_KEY=$($secrets.LICENSE_SECRET_KEY)",
    "--dart-define=LICENSE_PUBLIC_KEY=$publicKeyPem"
)

if (-not [string]::IsNullOrWhiteSpace($secrets.SUPABASE_URL)) {
    $buildArgs += "--dart-define=SUPABASE_URL=$($secrets.SUPABASE_URL)"
}
if (-not [string]::IsNullOrWhiteSpace($secrets.SUPABASE_ANON_KEY)) {
    $buildArgs += "--dart-define=SUPABASE_ANON_KEY=$($secrets.SUPABASE_ANON_KEY)"
}

Push-Location $ProjectRoot
try {
    Write-Host "Running: flutter $($buildArgs -join ' ')" -ForegroundColor DarkGray
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAILED] flutter build apk exited with code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    $builtApk = Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path -LiteralPath $builtApk)) {
        Write-Host "[FAILED] Output APK not found at $builtApk" -ForegroundColor Red
        exit 1
    }

    $destApk = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\MADAR_ERP_Trial_${TrialDays}Days.apk"
    Copy-Item -LiteralPath $builtApk -Destination $destApk -Force
    Write-Host ">>> SUCCESS: Built APK copied to $destApk <<<" -ForegroundColor Green

    $sizeMb = [math]::Round(((Get-Item $destApk).Length / 1MB), 2)
    Write-Host "File Size: $sizeMb MB" -ForegroundColor Green

    if ($InstallOnDevice) {
        $adb = "C:\Users\Momen\AppData\Local\Android\Sdk\platform-tools\adb.exe"
        if (Test-Path $adb) {
            Write-Host "Installing on connected device via ADB..." -ForegroundColor Cyan
            & $adb install -r $destApk
        } else {
            Write-Host "adb not found at $adb" -ForegroundColor Yellow
        }
    }
} finally {
    Pop-Location
}

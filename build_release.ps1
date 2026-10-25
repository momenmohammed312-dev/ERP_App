# build_release.ps1
# One reliable Windows release build for pos_offline_desktop.
#
# Reads required secrets from build_secrets.local.json (gitignored, never
# committed) so you never have to type long --dart-define flags by hand and
# never ship a build with sync or licensing silently broken.
#
# Usage (from repo root):
#   .\build_release.ps1

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Get-Location).Path
$SecretsFile = Join-Path $ProjectRoot 'build_secrets.local.json'

# ────────────────────────────────────────────────────────────────────────────
# 0) Secrets file guard
# ────────────────────────────────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $SecretsFile)) {
    Write-Host "[ABORT] $SecretsFile does not exist." -ForegroundColor Red
    Write-Host '' -ForegroundColor Red
    Write-Host 'Create it with this exact shape (replace values):' -ForegroundColor Yellow
    Write-Host '{' -ForegroundColor Yellow
    Write-Host '  "SUPABASE_URL": "https://your-project.supabase.co",' -ForegroundColor Yellow
    Write-Host '  "SUPABASE_ANON_KEY": "sb_publishable_...",' -ForegroundColor Yellow
    Write-Host '  "LICENSE_SECRET_KEY": "the-real-production-secret",' -ForegroundColor Yellow
    Write-Host '  "LICENSE_PUBLIC_KEY": "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----"' -ForegroundColor Yellow
    Write-Host '}' -ForegroundColor Yellow
    Write-Host '' -ForegroundColor Red
    Write-Host 'LICENSE_PUBLIC_KEY is REQUIRED (FEAT-016). Without it the' -ForegroundColor Red
    Write-Host 'release build compiles with an EMPTY verification key and' -ForegroundColor Red
    Write-Host '_parseLease() rejects every signed license - which locks out' -ForegroundColor Red
    Write-Host 'every customer. It is a PUBLIC key and is safe in this file.' -ForegroundColor Red
    Write-Host '' -ForegroundColor Red
    Write-Host 'The file is gitignored and must never be committed.' -ForegroundColor Red
    exit 1
}

$secrets = Get-Content -LiteralPath $SecretsFile -Raw | ConvertFrom-Json

foreach ($key in @('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'LICENSE_SECRET_KEY', 'LICENSE_PUBLIC_KEY')) {
    $val = $secrets.$key
    if ([string]::IsNullOrEmpty($val) -or $val -eq 'PLACEHOLDER_REPLACE_WITH_PRODUCTION_SECRET' -or $val -eq 'CHANGE_ME') {
        Write-Host "[ABORT] $key in $SecretsFile is empty or still a placeholder." -ForegroundColor Red
        Write-Host "[ABORT] Fill in the real value before building." -ForegroundColor Red
        exit 1
    }
}

# ────────────────────────────────────────────────────────────────────────────
# 1) Read current version from pubspec.yaml
# ────────────────────────────────────────────────────────────────────────────
$pubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
if (-not (Test-Path -LiteralPath $pubspecPath)) {
    Write-Host "[ABORT] $pubspecPath not found. Run this script from the repo root." -ForegroundColor Red
    exit 1
}

$versionLine = Select-String -LiteralPath $pubspecPath -Pattern '^version:\s*' | Select-Object -First 1
if (-not $versionLine) {
    Write-Host "[ABORT] Could not find a 'version:' line in $pubspecPath." -ForegroundColor Red
    exit 1
}
$appVersion = ($versionLine.Line -replace '^version:\s*', '').Trim()

# ────────────────────────────────────────────────────────────────────────────
# 2) Build
# ────────────────────────────────────────────────────────────────────────────
Write-Host "=== Building release v$appVersion ===" -ForegroundColor Cyan
# LICENSE_PUBLIC_KEY is not secret, but it IS mandatory: it is compiled into the
# binary and is the only thing that can verify an RS256 lease offline. Escape
# the literal newlines because --dart-define cannot carry real ones; the app
# side (LicenseConfig.normalizePem) converts them back.
$publicKeyPem = ($secrets.LICENSE_PUBLIC_KEY -replace "`r`n", '\n' -replace "`n", '\n')
$buildArgs = @(
    'build', 'windows', '--release',
    "--dart-define=SUPABASE_URL=$($secrets.SUPABASE_URL)",
    "--dart-define=SUPABASE_ANON_KEY=$($secrets.SUPABASE_ANON_KEY)",
    "--dart-define=LICENSE_SECRET_KEY=$($secrets.LICENSE_SECRET_KEY)",
    "--dart-define=LICENSE_PUBLIC_KEY=$publicKeyPem"
)
& flutter @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ABORT] flutter build windows --release failed." -ForegroundColor Red
    exit 1
}

# ────────────────────────────────────────────────────────────────────────────
# 3) Post-build verification & bundling (Release DLL + MSVC Runtimes)
# ────────────────────────────────────────────────────────────────────────────
$releaseDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
$outputPath = Join-Path $releaseDir 'pos_offline_desktop.exe'

# Locate Flutter SDK cache to guarantee Release AOT flutter_windows.dll
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterCmd) {
    $flutterBin = Split-Path $flutterCmd.Source
    $flutterRoot = Split-Path $flutterBin
    $engineReleaseDll = Join-Path $flutterRoot 'bin\cache\artifacts\engine\windows-x64-release\flutter_windows.dll'
    $targetDll = Join-Path $releaseDir 'flutter_windows.dll'

    if (Test-Path $engineReleaseDll) {
        $targetItem = Get-Item $targetDll -ErrorAction SilentlyContinue
        # If the target DLL is the debug one (>30MB) or missing, overwrite with genuine release AOT DLL
        if (-not $targetItem -or $targetItem.Length -gt 30MB) {
            Write-Host "[POST-BUILD] Ensuring genuine Release AOT flutter_windows.dll..." -ForegroundColor Yellow
            Copy-Item -LiteralPath $engineReleaseDll -Destination $targetDll -Force
        }
    }
}

# Copy MSVC C++ Redistributable DLLs so client machines never hit missing runtime DLLs
$msvcDlls = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
foreach ($dll in $msvcDlls) {
    $sysPath = Join-Path $env:windir "System32\$dll"
    $destPath = Join-Path $releaseDir $dll
    if (Test-Path $sysPath) {
        Copy-Item -LiteralPath $sysPath -Destination $destPath -Force -ErrorAction SilentlyContinue
    }
}

# Sanity smoke-test: verify binary launches cleanly and doesn't crash on start
Write-Host "[POST-BUILD] Running sanity smoke-test on release binary..." -ForegroundColor Cyan
$p = Start-Process -FilePath $outputPath -PassThru
Start-Sleep -Seconds 2
if ($p.HasExited) {
    Write-Host "[FATAL] Release binary crashed immediately with exit code $($p.ExitCode)!" -ForegroundColor Red
    exit 1
}
Stop-Process -Id $p.Id -Force
Write-Host "[POST-BUILD] Sanity smoke-test passed! Application launches cleanly." -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────────────
# 4) Report
# ────────────────────────────────────────────────────────────────────────────
Write-Host '' -ForegroundColor Green
Write-Host "[DONE] Release build succeeded and verified." -ForegroundColor Green
Write-Host "[DONE] Version: $appVersion" -ForegroundColor Green
Write-Host "[DONE] Output: $outputPath" -ForegroundColor Green
Write-Host "[IMPORTANT] To deliver to client: Copy the ENTIRE folder 'build\windows\x64\runner\Release\' (including 'data/' and all .dll files), not just pos_offline_desktop.exe alone." -ForegroundColor Yellow
Write-Host '' -ForegroundColor Green
exit 0

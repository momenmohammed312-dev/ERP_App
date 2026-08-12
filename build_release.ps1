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
    Write-Host '  "LICENSE_SECRET_KEY": "the-real-production-secret"' -ForegroundColor Yellow
    Write-Host '}' -ForegroundColor Yellow
    Write-Host '' -ForegroundColor Yellow
    Write-Host 'The file is gitignored and must never be committed.' -ForegroundColor Red
    exit 1
}

$secrets = Get-Content -LiteralPath $SecretsFile -Raw | ConvertFrom-Json

foreach ($key in @('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'LICENSE_SECRET_KEY')) {
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
$buildArgs = @(
    'build', 'windows', '--release',
    "--dart-define=SUPABASE_URL=$($secrets.SUPABASE_URL)",
    "--dart-define=SUPABASE_ANON_KEY=$($secrets.SUPABASE_ANON_KEY)",
    "--dart-define=LICENSE_SECRET_KEY=$($secrets.LICENSE_SECRET_KEY)"
)
& flutter @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ABORT] flutter build windows --release failed." -ForegroundColor Red
    exit 1
}

# ────────────────────────────────────────────────────────────────────────────
# 3) Report
# ────────────────────────────────────────────────────────────────────────────
$outputPath = Join-Path $ProjectRoot 'build\windows\x64\runner\Release\pos_offline_desktop.exe'
Write-Host '' -ForegroundColor Green
Write-Host "[DONE] Release build succeeded." -ForegroundColor Green
Write-Host "[DONE] Version: $appVersion" -ForegroundColor Green
Write-Host "[DONE] Output: $outputPath" -ForegroundColor Green
Write-Host '' -ForegroundColor Green
exit 0

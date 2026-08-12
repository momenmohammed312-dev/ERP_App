# verify_windows_build.ps1
# Verifies that a Windows Release build is complete before packaging.
# Parses windows/flutter/generated_plugins.cmake (auto-generated) for the
# plugin list, then checks every expected plugin DLL exists in Release.
#
# Exit codes:
#   0 = all good -> packaging may continue
#   1 = missing files -> packaging MUST stop
#
# Usage (from project root):
#   powershell -ExecutionPolicy Bypass -File scripts\verify_windows_build.ps1

[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$ReleaseDir = ""
)

$ErrorActionPreference = 'Stop'

$cmakeFile = Join-Path $ProjectRoot "windows\flutter\generated_plugins.cmake"
if ([string]::IsNullOrEmpty($ReleaseDir)) {
    $ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
}
$exeName = "pos_offline_desktop.exe"
$exePath = Join-Path $ReleaseDir $exeName
$dataDir = Join-Path $ReleaseDir "data"

Write-Host "=== Verification of Windows Release build ===" -ForegroundColor Cyan
Write-Host "Project root : $ProjectRoot"
Write-Host "Release dir  : $ReleaseDir"
Write-Host ""

$failures = @()

# 1) generated_plugins.cmake must exist (created by 'flutter pub get')
if (-not (Test-Path -LiteralPath $cmakeFile)) {
    Write-Host "[FAIL] windows\flutter\generated_plugins.cmake not found (did you run 'flutter pub get'?)." -ForegroundColor Red
    Write-Host "[FAIL] file generated_plugins.cmake not found - run 'flutter pub get' first." -ForegroundColor Red
    exit 1
}

# 2) Extract plugin list automatically (never hardcoded)
$content = Get-Content -LiteralPath $cmakeFile -Raw
$blockMatch = [regex]::Match(
    $content,
    'list\(APPEND FLUTTER_PLUGIN_LIST(?<body>[\s\S]*?)\)',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

$plugins = @()
if ($blockMatch.Success) {
    $body = $blockMatch.Groups['body'].Value
    $allMatches = [regex]::Matches($body, '(?m)^\s*([a-zA-Z0-9_]+)\s*$')
    foreach ($m in $allMatches) {
        $name = $m.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $plugins += $name
        }
    }
}

if ($plugins.Count -eq 0) {
    Write-Host "[FAIL] Could not parse FLUTTER_PLUGIN_LIST from generated_plugins.cmake." -ForegroundColor Red
    Write-Host "[FAIL] Failed to extract plugin list from generated_plugins.cmake." -ForegroundColor Red
    exit 1
}

Write-Host "Detected $($plugins.Count) plugins (from generated_plugins.cmake):"
Write-Host ("  " + ($plugins -join ", ")) -ForegroundColor Gray
Write-Host ""

# 3) Check each plugin DLL against actual files
$dllFiles = @(Get-ChildItem -LiteralPath $ReleaseDir -Filter "*.dll" -File -ErrorAction SilentlyContinue)
$dllNames = $dllFiles | ForEach-Object { $_.Name }

foreach ($plugin in $plugins) {
    $prefix = $plugin + "_"
    $match = $dllNames | Where-Object { $_ -like "$prefix*" } | Select-Object -First 1

    if (-not $match) {
        $msgEn = "Missing DLL for plugin '$plugin'. Expected a file starting with '$prefix'. Found DLLs: $($dllNames -join ', ')"
        Write-Host "[FAIL] $msgEn" -ForegroundColor Red
        $failures += "plugin:$plugin"
    } else {
        Write-Host "[OK]   $plugin -> $match" -ForegroundColor Green
    }
}

Write-Host ""

# 4) Main executable must exist
if (-not (Test-Path -LiteralPath $exePath)) {
    $msgEn = "Missing main executable: $exePath"
    Write-Host "[FAIL] $msgEn" -ForegroundColor Red
    $failures += "exe:$exeName"
} else {
    Write-Host "[OK]   $exeName exists." -ForegroundColor Green
}

# 5) data folder must exist and be non-empty
$dataFileCount = 0
if (-not (Test-Path -LiteralPath $dataDir)) {
    $msgEn = "Missing data folder: $dataDir"
    Write-Host "[FAIL] $msgEn" -ForegroundColor Red
    $failures += "data:folder"
} else {
    $dataFileCount = @(Get-ChildItem -LiteralPath $dataDir -Recurse -File -ErrorAction SilentlyContinue).Count
    if ($dataFileCount -eq 0) {
        $msgEn = "data folder is empty: $dataDir"
        Write-Host "[FAIL] $msgEn" -ForegroundColor Red
        $failures += "data:empty"
    } else {
        Write-Host "[OK]   data folder exists with $dataFileCount file(s)." -ForegroundColor Green
    }
}

Write-Host ""

# 6) Final result
if ($failures.Count -gt 0) {
    Write-Host "RESULT: FAILED - $($failures.Count) issue(s) found. Packaging MUST NOT continue." -ForegroundColor Red
    Write-Host "RESULT: FAILED - stop packaging immediately, some files are missing." -ForegroundColor Red
    exit 1
} else {
    Write-Host "RESULT: PASSED - all plugin DLLs, main exe and data folder are present." -ForegroundColor Green
    Write-Host "RESULT: PASSED - all required files are present, packaging can continue." -ForegroundColor Green
    exit 0
}

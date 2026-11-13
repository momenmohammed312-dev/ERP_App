# build_all_targets.ps1
# Master build script for MADAR POS/ERP:
# 1) Windows Release (Standard / Licensed - Requires Activation)
# 2) Windows Release (7-Day Free Trial - Pre-activated for 7 days)
# 3) Android Release APK (Standard / Licensed - Requires Activation)
# 4) Android Release APK (7-Day Free Trial - Pre-activated for 7 days)

param(
    [switch]$SkipWindows,
    [switch]$SkipAndroid
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Get-Location).Path
$SecretsFile = Join-Path $ProjectRoot 'build_secrets.local.json'

if (-not (Test-Path -LiteralPath $SecretsFile)) {
    Write-Host "[ABORT] $SecretsFile does not exist." -ForegroundColor Red
    exit 1
}

$secrets = Get-Content -LiteralPath $SecretsFile -Raw | ConvertFrom-Json

foreach ($key in @('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'LICENSE_SECRET_KEY', 'LICENSE_PUBLIC_KEY')) {
    $val = $secrets.$key
    if ([string]::IsNullOrEmpty($val) -or $val -eq 'CHANGE_ME') {
        Write-Host "[ABORT] $key in $SecretsFile is empty or invalid." -ForegroundColor Red
        exit 1
    }
}

# Defensive extraction for LICENSE_PUBLIC_KEY
$rawKey = if ($secrets.LICENSE_PUBLIC_KEY.value) {
    [string]$secrets.LICENSE_PUBLIC_KEY.value
} else {
    [string]$secrets.LICENSE_PUBLIC_KEY
}
$publicKeyPem = ($rawKey -replace "`r`n", '\n' -replace "`n", '\n').Trim()

if (-not $publicKeyPem.StartsWith('-----BEGIN PUBLIC KEY-----')) {
    Write-Host "[ABORT] LICENSE_PUBLIC_KEY must start with '-----BEGIN PUBLIC KEY-----'." -ForegroundColor Red
    exit 1
}

$pubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
$versionLine = Select-String -LiteralPath $pubspecPath -Pattern '^version:\s*' | Select-Object -First 1
$appVersion = ($versionLine.Line -replace '^version:\s*', '').Trim()

$distRoot = Join-Path $ProjectRoot 'dist'
$distWinStandard = Join-Path $distRoot 'Windows_Standard_Release'
$distWinTrial = Join-Path $distRoot 'Windows_Trial_7Days'
$distAndroidStandard = Join-Path $distRoot 'Android_Standard_Release'
$distAndroidTrial = Join-Path $distRoot 'Android_Trial_7Days'

@($distWinStandard, $distWinTrial, $distAndroidStandard, $distAndroidTrial) | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

function PostProcess-WindowsBuild([string]$DestFolder) {
    $releaseDir = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
    $outputPath = Join-Path $releaseDir 'pos_offline_desktop.exe'

    # Verify AOT engine dll
    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCmd) {
        $flutterBin = Split-Path $flutterCmd.Source
        $flutterRoot = Split-Path $flutterBin
        $engineReleaseDll = Join-Path $flutterRoot 'bin\cache\artifacts\engine\windows-x64-release\flutter_windows.dll'
        $targetDll = Join-Path $releaseDir 'flutter_windows.dll'

        if (Test-Path $engineReleaseDll) {
            $targetItem = Get-Item $targetDll -ErrorAction SilentlyContinue
            if (-not $targetItem -or $targetItem.Length -gt 30MB) {
                Write-Host "[POST-BUILD] Ensuring genuine Release AOT flutter_windows.dll..." -ForegroundColor Yellow
                Copy-Item -LiteralPath $engineReleaseDll -Destination $targetDll -Force
            }
        }
    }

    # Copy MSVC C++ Redistributable DLLs
    $msvcDlls = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
    foreach ($dll in $msvcDlls) {
        $sysPath = Join-Path $env:windir "System32\$dll"
        $destPath = Join-Path $releaseDir $dll
        if (Test-Path $sysPath) {
            Copy-Item -LiteralPath $sysPath -Destination $destPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Sanity smoke-test: verify binary launches cleanly
    Write-Host "[POST-BUILD] Running sanity smoke-test on release binary..." -ForegroundColor Cyan
    $p = Start-Process -FilePath $outputPath -PassThru
    Start-Sleep -Seconds 2
    if ($p.HasExited) {
        Write-Host "[FATAL] Release binary crashed immediately with exit code $($p.ExitCode)!" -ForegroundColor Red
        exit 1
    }
    Stop-Process -Id $p.Id -Force
    Write-Host "[POST-BUILD] Sanity smoke-test passed! Application launches cleanly." -ForegroundColor Green

    # Copy entire Release folder to destination
    Write-Host "[DIST] Copying release to $DestFolder..." -ForegroundColor Cyan
    Get-ChildItem -Path $releaseDir | Copy-Item -Destination $DestFolder -Recurse -Force
}

# ═════════════════════════════════════════════════════════════════════════════
# 1) WINDOWS BUILDS
# ═════════════════════════════════════════════════════════════════════════════
if (-not $SkipWindows) {
    # --- Target 1: Windows Standard Release ---
    Write-Host "`n========================================================" -ForegroundColor Magenta
    Write-Host ">>> TARGET 1: Windows Release (Standard / Licensed) <<<" -ForegroundColor Magenta
    Write-Host "========================================================" -ForegroundColor Magenta
    $winStdArgs = @(
        'build', 'windows', '--release',
        "--dart-define=SUPABASE_URL=$($secrets.SUPABASE_URL)",
        "--dart-define=SUPABASE_ANON_KEY=$($secrets.SUPABASE_ANON_KEY)",
        "--dart-define=LICENSE_SECRET_KEY=$($secrets.LICENSE_SECRET_KEY)",
        "--dart-define=LICENSE_PUBLIC_KEY=$publicKeyPem",
        # Customer release gate: Smart Analytics & Smart Notifications are hidden
        # in EVERY artifact produced by this script (all 4 targets).
        '--dart-define=ENABLE_SMART_ANALYTICS=false'
    )
    & flutter @winStdArgs
    if ($LASTEXITCODE -ne 0) { throw "Windows Standard build failed" }
    PostProcess-WindowsBuild -DestFolder $distWinStandard
    
    # Create ZIP archive
    $zipWinStd = Join-Path $distRoot "MADAR_ERP_Standard_Release.zip"
    Write-Host "[DIST] Creating zip: $zipWinStd" -ForegroundColor Cyan
    if (Test-Path $zipWinStd) { Remove-Item -LiteralPath $zipWinStd -Force }
    Compress-Archive -Path "$distWinStandard\*" -DestinationPath $zipWinStd -Force

    # Compile Standalone Setup Executable (.exe)
    $setupStdExe = Join-Path $distRoot "MADAR_ERP_Setup_Standard.exe"
    Write-Host "[DIST] Compiling Standalone Setup Executable: $setupStdExe" -ForegroundColor Cyan
    $csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    & $csc /target:winexe /optimize+ /platform:anycpu /out:$setupStdExe `
        /win32icon:"assets\logo\app_logo.ico" `
        /win32manifest:"installer\src\app.manifest" `
        /resource:"$zipWinStd,AppPayload" `
        /r:System.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll /r:Microsoft.CSharp.dll `
        "installer\src\Installer.cs"
    if ($LASTEXITCODE -ne 0) { throw "Setup Executable compilation failed" }

    # --- Target 2: Windows 7-Day Free Trial ---
    Write-Host "`n========================================================" -ForegroundColor Magenta
    Write-Host ">>> TARGET 2: Windows Release (7-Day Free Trial) <<<" -ForegroundColor Magenta
    Write-Host "========================================================" -ForegroundColor Magenta
    $winTrialArgs = @(
        'build', 'windows', '--release',
        "--dart-define=FREE_VERSION=true",
        "--dart-define=FREE_TRIAL_DAYS=7",
        "--dart-define=ENABLE_ALL_FEATURES=true",
        # NOTE: ENABLE_ALL_FEATURES=true does NOT re-enable Smart Analytics.
        # An explicit ENABLE_SMART_ANALYTICS=false wins over ENABLE_ALL_FEATURES
        # on the Dart side (AppFeatures.hasSmartAnalytics) - do not "fix" this.
        '--dart-define=ENABLE_SMART_ANALYTICS=false',
        "--dart-define=SUPABASE_URL=$($secrets.SUPABASE_URL)",
        "--dart-define=SUPABASE_ANON_KEY=$($secrets.SUPABASE_ANON_KEY)",
        "--dart-define=LICENSE_SECRET_KEY=$($secrets.LICENSE_SECRET_KEY)",
        "--dart-define=LICENSE_PUBLIC_KEY=$publicKeyPem"
    )
    & flutter @winTrialArgs
    if ($LASTEXITCODE -ne 0) { throw "Windows Trial build failed" }
    PostProcess-WindowsBuild -DestFolder $distWinTrial

    # Create ZIP archive
    $zipWinTrial = Join-Path $distRoot "MADAR_ERP_Trial_7Days.zip"
    Write-Host "[DIST] Creating zip: $zipWinTrial" -ForegroundColor Cyan
    if (Test-Path $zipWinTrial) { Remove-Item -LiteralPath $zipWinTrial -Force }
    Compress-Archive -Path "$distWinTrial\*" -DestinationPath $zipWinTrial -Force

    # Compile Standalone Trial Setup Executable (.exe)
    $setupTrialExe = Join-Path $distRoot "MADAR_ERP_Setup_Trial_7Days.exe"
    Write-Host "[DIST] Compiling Standalone Trial Setup Executable: $setupTrialExe" -ForegroundColor Cyan
    & $csc /target:winexe /optimize+ /platform:anycpu /define:TRIAL /out:$setupTrialExe `
        /win32icon:"assets\logo\app_logo.ico" `
        /win32manifest:"installer\src\app.manifest" `
        /resource:"$zipWinTrial,AppPayload" `
        /r:System.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll /r:Microsoft.CSharp.dll `
        "installer\src\Installer.cs"
    if ($LASTEXITCODE -ne 0) { throw "Trial Setup Executable compilation failed" }
}

# ═════════════════════════════════════════════════════════════════════════════
# 2) ANDROID BUILDS
# ═════════════════════════════════════════════════════════════════════════════
if (-not $SkipAndroid) {
    # --- Target 3: Android Standard Release APK ---
    Write-Host "`n========================================================" -ForegroundColor Magenta
    Write-Host ">>> TARGET 3: Android Release APK (Standard / Licensed) <<<" -ForegroundColor Magenta
    Write-Host "========================================================" -ForegroundColor Magenta
    $apkStdArgs = @(
        'build', 'apk', '--release',
        '-t', 'lib/main_all.dart',
        '--dart-define=FLAVOR=all',
        '--dart-define=ENABLE_ALL_FEATURES=true',
        # NOTE: ENABLE_ALL_FEATURES=true does NOT re-enable Smart Analytics.
        # An explicit ENABLE_SMART_ANALYTICS=false wins over ENABLE_ALL_FEATURES
        # on the Dart side (AppFeatures.hasSmartAnalytics) - do not "fix" this.
        '--dart-define=ENABLE_SMART_ANALYTICS=false',
        "--dart-define=LICENSE_SECRET_KEY=$($secrets.LICENSE_SECRET_KEY)",
        "--dart-define=LICENSE_PUBLIC_KEY=$publicKeyPem",
        "--dart-define=SUPABASE_URL=$($secrets.SUPABASE_URL)",
        "--dart-define=SUPABASE_ANON_KEY=$($secrets.SUPABASE_ANON_KEY)"
    )
    & flutter @apkStdArgs
    if ($LASTEXITCODE -ne 0) { throw "Android Standard build failed" }
    
    $rawApk = Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-release.apk'
    $destApkStd = Join-Path $distAndroidStandard "MADAR_ERP_Standard_Release.apk"
    Copy-Item -LiteralPath $rawApk -Destination $destApkStd -Force
    Write-Host "[DIST] Android Standard APK ready at $destApkStd" -ForegroundColor Green

    # --- Target 4: Android 7-Day Free Trial APK ---
    Write-Host "`n========================================================" -ForegroundColor Magenta
    Write-Host ">>> TARGET 4: Android Release APK (7-Day Free Trial) <<<" -ForegroundColor Magenta
    Write-Host "========================================================" -ForegroundColor Magenta
    $apkTrialArgs = @(
        'build', 'apk', '--release',
        '-t', 'lib/main_all.dart',
        '--dart-define=FLAVOR=all',
        '--dart-define=ENABLE_ALL_FEATURES=true',
        '--dart-define=FREE_VERSION=true',
        '--dart-define=FREE_TRIAL_DAYS=7',
        # NOTE: ENABLE_ALL_FEATURES=true does NOT re-enable Smart Analytics.
        # An explicit ENABLE_SMART_ANALYTICS=false wins over ENABLE_ALL_FEATURES
        # on the Dart side (AppFeatures.hasSmartAnalytics) - do not "fix" this.
        '--dart-define=ENABLE_SMART_ANALYTICS=false',
        "--dart-define=LICENSE_SECRET_KEY=$($secrets.LICENSE_SECRET_KEY)",
        "--dart-define=LICENSE_PUBLIC_KEY=$publicKeyPem",
        "--dart-define=SUPABASE_URL=$($secrets.SUPABASE_URL)",
        "--dart-define=SUPABASE_ANON_KEY=$($secrets.SUPABASE_ANON_KEY)"
    )
    & flutter @apkTrialArgs
    if ($LASTEXITCODE -ne 0) { throw "Android Trial build failed" }

    $destApkTrial = Join-Path $distAndroidTrial "MADAR_ERP_Trial_7Days.apk"
    Copy-Item -LiteralPath $rawApk -Destination $destApkTrial -Force
    Write-Host "[DIST] Android Trial APK ready at $destApkTrial" -ForegroundColor Green
}

# ═════════════════════════════════════════════════════════════════════════════
# SUMMARY REPORT
# ═════════════════════════════════════════════════════════════════════════════
Write-Host "`n========================================================" -ForegroundColor Green
Write-Host ">>> ALL BUILDS COMPLETED SUCCESSFULLY <<<" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "[DONE] Smart Analytics & Smart Notifications: HIDDEN in all artifacts (ENABLE_SMART_ANALYTICS=false)" -ForegroundColor Yellow
Get-ChildItem -Path $distRoot -Recurse -File | Where-Object { $_.Extension -in @('.exe', '.zip', '.apk') } | Select-Object Name, Length, FullName | Format-Table -AutoSize

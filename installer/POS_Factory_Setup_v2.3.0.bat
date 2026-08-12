@echo off
title POS Factory v2.3.0 Setup
echo ============================================
echo   POS Factory v2.3.0 - Setup
echo ============================================
echo.

:: Check admin
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo This installer requires administrator rights.
    echo Please right-click and select "Run as administrator".
    echo.
    pause
    exit /b 1
)

:: Run PowerShell installer
echo Starting installer...
powershell -ExecutionPolicy Bypass -File "%~dp0POS_Factory_Setup_v2.3.0.ps1"
if '%errorlevel%' NEQ '0' (
    echo.
    echo Installer exited with error code %errorlevel%.
    pause
)
exit /b %errorlevel%

@echo off
title POS Factory - Reset License Data
echo ============================================
echo   POS Factory - Reset License Data
echo ============================================
echo.

REM Delete old license data
set "APPDATA_DIR=%APPDATA%\com.example\pos_offline_desktop"
if exist "%APPDATA_DIR%" (
    echo Deleting old license data...
    del /q "%APPDATA_DIR%\secure_license.dat" 2>nul
    del /q "%APPDATA_DIR%\secure_license.bak" 2>nul
    echo License data cleared.
) else (
    echo No old license data found.
)

echo.
echo ============================================
echo   Launching POS Factory...
echo ============================================
echo.

REM Launch the application
cd /d "%~dp0"
start "" "pos_offline_desktop.exe"

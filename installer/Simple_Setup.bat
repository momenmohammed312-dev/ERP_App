@echo off
title POS System v2.3.0 Setup
chcp 65001 >nul 2>&1

echo ============================================
echo   POS System v2.3.0 - Setup
echo ============================================
echo.

:: Check admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Requesting Administrator Privileges...
    powershell -ExecutionPolicy Bypass -Command "Start-Process cmd -ArgumentList '/c', '\"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: Set paths
set "INSTALL_DIR=%ProgramFiles%\POS System"
set "APP_DATA=%APPDATA%\pos_offline_desktop"

echo [1/4] Closing application if running...
taskkill /f /im pos_offline_desktop.exe >nul 2>&1
timeout /t 1 /nobreak >nul
echo       Done.

echo [2/4] Checking previous license state...
REM FEAT-013: the old license data is deliberately NOT deleted. An update must
REM never cost a paying customer their license. See
REM test/unit/services/installer_license_persistence_test.dart
if exist "%APP_DATA%\secure_license.dat" (
    echo       Existing license found - it will be preserved.
) else (
    echo       No license file found.
)

echo [3/4] Installing application...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" >nul 2>&1

:: Copy application files
robocopy "%~dp0\" "%INSTALL_DIR%" /E /IS /IT /XF "Install*.bat" "Setup*.bat" "*.zip" >nul 2>&1
if %errorlevel% gtr 7 (
    xcopy /s /e /y /q "%~dp0*" "%INSTALL_DIR%\" >nul 2>&1
)
echo       Application installed to: %INSTALL_DIR%

echo [4/4] Creating shortcuts...
set "DESKTOP=%PUBLIC%\Desktop"
set "STARTMENU=%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ws = New-Object -ComObject WScript.Shell; " ^
    "$desk = $ws.CreateShortcut('%DESKTOP%\POS System.lnk'); " ^
    "$desk.TargetPath = '%INSTALL_DIR%\pos_offline_desktop.exe'; " ^
    "$desk.WorkingDirectory = '%INSTALL_DIR%'; " ^
    "$desk.IconLocation = '%INSTALL_DIR%\pos_offline_desktop.exe,0'; " ^
    "$desk.Save(); " ^
    "$menu = $ws.CreateShortcut('%STARTMENU%\POS System.lnk'); " ^
    "$menu.TargetPath = '%INSTALL_DIR%\pos_offline_desktop.exe'; " ^
    "$menu.WorkingDirectory = '%INSTALL_DIR%'; " ^
    "$menu.IconLocation = '%INSTALL_DIR%\pos_offline_desktop.exe,0'; " ^
    "$menu.Save();" >nul 2>&1

echo       Shortcuts created.
echo.
echo ============================================
echo   Installation Complete!
echo ============================================
echo.
echo   POS System v2.3.0 installed successfully!
echo   Location: %INSTALL_DIR%
echo.

set /p LAUNCH="Launch POS System now? (Y/N): "
if /i "%LAUNCH%"=="" set LAUNCH=Y
if /i "%LAUNCH%"=="Y" (
    start "" "%INSTALL_DIR%\pos_offline_desktop.exe"
)

echo.
timeout /t 2 >nul
exit /b 0

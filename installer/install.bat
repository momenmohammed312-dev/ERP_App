@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

REM ════════════════════════════════════════════════════════════════════════════
REM POS System - Clean Setup & Update Installer
REM ════════════════════════════════════════════════════════════════════════════

set "APP_NAME=POS System"
set "APP_VERSION=2.3.0"
set "APP_EXE=pos_offline_desktop.exe"
set "INSTALL_DIR=%ProgramFiles%\POS System"
set "SHORTCUT_NAME=POS System"

title %APP_NAME% v%APP_VERSION% - Installer

:: Check for admin rights and auto-elevate
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Requesting Administrator Privileges...
    powershell -ExecutionPolicy Bypass -Command "Start-Process cmd -ArgumentList '/c', '\"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

cls
echo ══════════════════════════════════════════════════════════════════════
echo   %APP_NAME% v%APP_VERSION% - Installation
echo ══════════════════════════════════════════════════════════════════════
echo.
echo Installing to: %INSTALL_DIR%
echo.

:: Close existing application if running
echo Closing application if running...
taskkill /f /im %APP_EXE% >nul 2>&1
timeout /t 1 /nobreak >nul

:: FEAT-013: Existing license data is deliberately PRESERVED.
:: An update or installation must NEVER cost a customer their license.
if exist "%APPDATA%\pos_offline_desktop\secure_license.dat" (
    echo Existing license found - preserved safely.
)

:: Create installation directory
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" >nul 2>&1

:: Copy application files
echo Copying application files...
robocopy "%~dp0\" "%INSTALL_DIR%" /E /IS /IT /XF "Install*.bat" "Setup*.bat" "*.zip" >nul 2>&1
if %errorlevel% gtr 7 (
    xcopy /s /e /y /q "%~dp0*" "%INSTALL_DIR%\" >nul 2>&1
)

:: Create shortcuts
echo Creating shortcuts...
set "DESKTOP=%PUBLIC%\Desktop"
set "STARTMENU=%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ws = New-Object -ComObject WScript.Shell; " ^
    "$desk = $ws.CreateShortcut('%DESKTOP%\%SHORTCUT_NAME%.lnk'); " ^
    "$desk.TargetPath = '%INSTALL_DIR%\%APP_EXE%'; " ^
    "$desk.WorkingDirectory = '%INSTALL_DIR%'; " ^
    "$desk.IconLocation = '%INSTALL_DIR%\%APP_EXE%,0'; " ^
    "$desk.Save(); " ^
    "$menu = $ws.CreateShortcut('%STARTMENU%\%SHORTCUT_NAME%.lnk'); " ^
    "$menu.TargetPath = '%INSTALL_DIR%\%APP_EXE%'; " ^
    "$menu.WorkingDirectory = '%INSTALL_DIR%'; " ^
    "$menu.IconLocation = '%INSTALL_DIR%\%APP_EXE%,0'; " ^
    "$menu.Save();" >nul 2>&1

:: Register installation
reg add "HKLM\SOFTWARE\POS System" /v InstallPath /d "%INSTALL_DIR%" /f >nul 2>&1
reg add "HKLM\SOFTWARE\POS System" /v Version /d "%APP_VERSION%" /f >nul 2>&1

echo.
echo ══════════════════════════════════════════════════════════════════════
echo   Installation Complete!
echo ══════════════════════════════════════════════════════════════════════
echo.
echo   Location: %INSTALL_DIR%
echo.

set /p LAUNCH="Would you like to launch %APP_NAME% now? (Y/N): "
if /i "%LAUNCH%"=="" set LAUNCH=Y
if /i "%LAUNCH%"=="Y" (
    start "" "%INSTALL_DIR%\%APP_EXE%"
)

echo.
timeout /t 2 >nul
exit /b 0

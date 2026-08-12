@echo off
title POS Factory v2.3.0 Setup
chcp 65001 >nul 2>&1

echo ============================================
echo   POS Factory v2.3.0 - Setup
echo   DEVELOPED BY MO2 | 01025545211
echo ============================================
echo.

:: Check admin rights
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo [ERROR] This installer requires administrator rights.
    echo Please right-click and select "Run as administrator".
    echo.
    pause
    exit /b 1
)

:: Set paths
set "INSTALL_DIR=%ProgramFiles%\POS Factory"
set "ZIP_FILE=%~dp0pos_factory_package.zip"
set "APP_DATA=%APPDATA%\com.example\pos_offline_desktop"

echo [1/5] Checking installation package...
if not exist "%ZIP_FILE%" (
    echo [ERROR] Package not found: %ZIP_FILE%
    echo Please ensure pos_factory_package.zip is in the same folder.
    echo.
    pause
    exit /b 1
)
echo       Found: %ZIP_FILE%

echo [2/5] Closing application if running...
taskkill /f /im pos_offline_desktop.exe >nul 2>&1
timeout /t 2 /nobreak >nul
echo       Done.

echo [3/5] Clearing old license data...
if exist "%APP_DATA%" (
    del /q "%APP_DATA%\secure_license.dat" 2>nul
    del /q "%APP_DATA%\secure_license.bak" 2>nul
    echo       Old license data cleared.
) else (
    echo       No old license data found.
)

echo [4/5] Installing application...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

:: Extract using PowerShell (built into Windows)
powershell -Command "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%INSTALL_DIR%' -Force" 2>nul
if '%errorlevel%' NEQ '0' (
    echo [ERROR] Failed to extract files.
    pause
    exit /b 1
)
echo       Application installed to: %INSTALL_DIR%

echo [5/5] Creating shortcuts...
set "DESKTOP=%PUBLIC%\Desktop"
set "STARTMENU=%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs"

:: Desktop shortcut
echo Set oWS = WScript.CreateObject("WScript.Shell") > "%TEMP%\create_shortcut.vbs"
echo sLinkFile = "%DESKTOP%\POS Factory.lnk" >> "%TEMP%\create_shortcut.vbs"
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> "%TEMP%\create_shortcut.vbs"
echo oLink.TargetPath = "%INSTALL_DIR%\pos_offline_desktop.exe" >> "%TEMP%\create_shortcut.vbs"
echo oLink.WorkingDirectory = "%INSTALL_DIR%" >> "%TEMP%\create_shortcut.vbs"
echo oLink.Save >> "%TEMP%\create_shortcut.vbs"
cscript /nologo "%TEMP%\create_shortcut.vbs" >nul 2>&1

:: Start Menu shortcut
echo Set oWS = WScript.CreateObject("WScript.Shell") > "%TEMP%\create_shortcut2.vbs"
echo sLinkFile = "%STARTMENU%\POS Factory.lnk" >> "%TEMP%\create_shortcut2.vbs"
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> "%TEMP%\create_shortcut2.vbs"
echo oLink.TargetPath = "%INSTALL_DIR%\pos_offline_desktop.exe" >> "%TEMP%\create_shortcut2.vbs"
echo oLink.WorkingDirectory = "%INSTALL_DIR%" >> "%TEMP%\create_shortcut2.vbs"
echo oLink.Save >> "%TEMP%\create_shortcut2.vbs"
cscript /nologo "%TEMP%\create_shortcut2.vbs" >nul 2>&1

del "%TEMP%\create_shortcut.vbs" >nul 2>&1
del "%TEMP%\create_shortcut2.vbs" >nul 2>&1

echo       Shortcuts created.
echo.
echo ============================================
echo   Installation Complete!
echo ============================================
echo.
echo   POS Factory v2.3.0 installed successfully!
echo   Location: %INSTALL_DIR%
echo.
echo   New Features:
echo   + QR Code Support
echo   + Enhanced Customer Management
echo   + Delete Customer from Edit Page
echo.
echo   Contact: 01025545211
echo   Website: https://mo2.dev
echo.
echo ============================================

set /p LAUNCH="Launch POS Factory now? (Y/N): "
if /i "%LAUNCH%"=="Y" (
    start "" "%INSTALL_DIR%\pos_offline_desktop.exe"
)

echo.
pause

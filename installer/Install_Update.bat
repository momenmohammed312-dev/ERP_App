@echo off
title POS System v2.3.0 - Update Installer
echo ================================================================
echo   POS System v2.3.0 - Update Installer
echo   DEVELOPED BY MO2
echo ================================================================
echo.

REM Check for admin rights
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo This installer requires administrator rights.
    echo Please right-click and select "Run as administrator".
    echo.
    pause
    exit /b 1
)

REM Launch PowerShell installer
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0POS_Update_Installer.ps1"

REM If PowerShell fails, fallback to basic install
if '%errorlevel%' NEQ '0' (
    echo.
    echo PowerShell installer failed. Using basic installer...
    echo.
    call :basic_install
)

goto :eof

:basic_install
echo Installing POS System v2.3.0...
echo.

set INSTALLDIR=%ProgramFiles%\POS System

REM Close app
taskkill /f /im pos_offline_desktop.exe >nul 2>&1
timeout /t 2 /nobreak >nul

REM Create dir
if not exist "%INSTALLDIR%" mkdir "%INSTALLDIR%"

REM Extract
echo Extracting files...
powershell -Command "Expand-Archive -Path '%~dp0pos_update_package.zip' -DestinationPath '%INSTALLDIR%' -Force"

REM Shortcuts
echo Creating shortcuts...
set DESKTOP=%PUBLIC%\Desktop
set STARTMENU=%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs

echo Set oWS = WScript.CreateObject("WScript.Shell") > "%TEMP%\create_shortcut.vbs"
echo sLinkFile = "%DESKTOP%\POS System.lnk" >> "%TEMP%\create_shortcut.vbs"
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> "%TEMP%\create_shortcut.vbs"
echo oLink.TargetPath = "%INSTALLDIR%\pos_offline_desktop.exe" >> "%TEMP%\create_shortcut.vbs"
echo oLink.WorkingDirectory = "%INSTALLDIR%" >> "%TEMP%\create_shortcut.vbs"
echo oLink.Save >> "%TEMP%\create_shortcut.vbs"
cscript /nologo "%TEMP%\create_shortcut.vbs" >nul 2>&1

echo Set oWS = WScript.CreateObject("WScript.Shell") > "%TEMP%\create_shortcut2.vbs"
echo sLinkFile = "%STARTMENU%\POS System.lnk" >> "%TEMP%\create_shortcut2.vbs"
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> "%TEMP%\create_shortcut2.vbs"
echo oLink.TargetPath = "%INSTALLDIR%\pos_offline_desktop.exe" >> "%TEMP%\create_shortcut2.vbs"
echo oLink.WorkingDirectory = "%INSTALLDIR%" >> "%TEMP%\create_shortcut2.vbs"
echo oLink.Save >> "%TEMP%\create_shortcut2.vbs"
cscript /nologo "%TEMP%\create_shortcut2.vbs" >nul 2>&1

del "%TEMP%\create_shortcut.vbs" >nul 2>&1
del "%TEMP%\create_shortcut2.vbs" >nul 2>&1

echo.
echo ================================================================
echo   Installation Complete!
echo ================================================================
echo.
echo   POS System v2.3.0 installed to:
echo   %INSTALLDIR%
echo.
echo   Contact: 01025545211
echo   Website: https://mo2.dev
echo.
echo ================================================================

set /p LAUNCH="Launch POS System now? (Y/N): "
if /i "%LAUNCH%"=="Y" (
    start "" "%INSTALLDIR%\pos_offline_desktop.exe"
)

echo.
pause
goto :eof

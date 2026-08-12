@echo off
REM ════════════════════════════════════════════════════════════════════════════
REM POS System v2.3.0 - Update Installer
REM DEVELOPED BY MO2 | Contact: 01025545211
REM ════════════════════════════════════════════════════════════════════════════

title POS System v2.3.0 - Update Installer

REM Check for admin rights
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo This installer requires administrator rights.
    echo Please right-click and select "Run as administrator".
    pause
    exit /b 1
)

REM Set installation directory
set INSTALLDIR=%ProgramFiles%\POS System

echo.
echo ══════════════════════════════════════════════════════════════════════
echo   POS System v2.3.0 - Update Installer
echo   DEVELOPED BY MO2
echo ══════════════════════════════════════════════════════════════════════
echo.
echo Installing to: %INSTALLDIR%
echo.

REM Close existing application
echo Closing application if running...
taskkill /f /im pos_offline_desktop.exe >nul 2>&1
timeout /t 2 /nobreak >nul

REM Create installation directory
if not exist "%INSTALLDIR%" mkdir "%INSTALLDIR%"

REM Extract files
echo Extracting application files...
xcopy /s /e /y /q "%~dp0*" "%INSTALLDIR%\" >nul 2>&1

REM Create shortcuts
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

REM Clean up
del "%TEMP%\create_shortcut.vbs" >nul 2>&1
del "%TEMP%\create_shortcut2.vbs" >nul 2>&1

REM Register installation
reg add "HKLM\SOFTWARE\POS System" /v InstallPath /d "%INSTALLDIR%" /f >nul 2>&1
reg add "HKLM\SOFTWARE\POS System" /v Version /d "2.3.0" /f >nul 2>&1
reg add "HKLM\SOFTWARE\POS System" /v Publisher /d "DEVELOPED BY MO2" /f >nul 2>&1

echo.
echo ══════════════════════════════════════════════════════════════════════
echo   Installation Complete!
echo ══════════════════════════════════════════════════════════════════════
echo.
echo   POS System v2.3.0 has been installed to:
echo   %INSTALLDIR%
echo.
echo   New Features:
echo   + QR Code Support
echo   + Enhanced Customer Management
echo.
echo   Fixes:
echo   + Fixed unexpected security warnings
echo   + Improved system stability
echo.
echo   Contact: 01025545211
echo   Website: https://mo2.dev
echo.
echo ══════════════════════════════════════════════════════════════════════
echo.

set /p LAUNCH="Would you like to launch POS System now? (Y/N): "
if /i "%LAUNCH%"=="Y" (
    start "" "%INSTALLDIR%\pos_offline_desktop.exe"
)

echo.
echo Thank you for using POS System!
echo.
pause

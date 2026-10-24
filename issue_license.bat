@echo off
chcp 65001 >nul
title MADAR ERP - License Issuer
echo ============================================================
echo       MADAR ERP - تشغيل مُصدر التراخيص التفاعلي
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0issue_license.ps1" %*

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo حدث خطأ أثناء تشغيل أداة الترخيص.
    pause
)

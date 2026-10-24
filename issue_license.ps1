<#
.SYNOPSIS
    مُصدِّر تراخيص MADAR ERP التفاعلي عبر الباورشيل (PowerShell Interactive License Issuer)
.DESCRIPTION
    يقوم بإصدار وتوقيع ملف ترخيص (.madarlicense) للعملاء للعمل بدون إنترنت (Offline).
    يعتمد على أداة tools/license_issuer.js ومفتاح التوقيع الرقمي RSA RS256.
.EXAMPLE
    .\issue_license.ps1
.EXAMPLE
    .\issue_license.ps1 -HardwareId "0123456789abcdef..." -Customer "محل الأمل" -Months 12
#>

[CmdletBinding()]
param (
    [string]$HardwareId,
    [string]$Customer,
    [string]$Type,
    [int]$Months,
    [int]$Days,
    [switch]$Lifetime,
    [string]$Plan,
    [string]$Features,
    [string]$KeyPath,
    [string]$OutputDir,
    [switch]$NonInteractive
)

# ضبط الترميز ليدعم اللغة العربية في سطر الأوامر
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = $ScriptDir

# مسار أداة الإصدار الأساسية
$IssuerJs = Join-Path $ProjectRoot "tools\license_issuer.js"
if (-not (Test-Path -LiteralPath $IssuerJs)) {
    Write-Host "`n[خطأ] تعذّر العثور على أداة: $IssuerJs" -ForegroundColor Red
    exit 1
}

# التحقق من وجود Node.js
try {
    $nodeVer = (& node -v) 2>$null
    if (-not $nodeVer) { throw "Node not found" }
} catch {
    Write-Host "`n[خطأ] Node.js غير مثبت على جهازك أو غير متاح في الـ PATH." -ForegroundColor Red
    Write-Host "يرجى تثبيت Node.js لتشغيل الأداة.`n" -ForegroundColor Yellow
    exit 1
}

if (-not $NonInteractive) {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "       MADAR ERP - مُصدِّر تراخيص العملاء (Offline)          " -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

# ────────────────────────────────────────────────────────────────────────────
# 1) إدارة المفتاح الخاص (Private Key Management)
# ────────────────────────────────────────────────────────────────────────────
$DefaultKeyDir = Join-Path $env:USERPROFILE ".madar"
$DefaultKeyPath = Join-Path $DefaultKeyDir "madar_private_key.pem"
$DefaultPubPath = Join-Path $DefaultKeyDir "madar_public_key.pem"

if (-not $KeyPath) {
    if ($env:MADAR_ISSUER_KEY_FILE -and (Test-Path -LiteralPath $env:MADAR_ISSUER_KEY_FILE)) {
        $KeyPath = $env:MADAR_ISSUER_KEY_FILE
    } elseif (Test-Path -LiteralPath $DefaultKeyPath) {
        $KeyPath = $DefaultKeyPath
    }
}

# إذا لم يتوفر مفتاح خاص، نساعد المستخدم على إنشائه أو تحديده
if (-not $KeyPath -or -not (Test-Path -LiteralPath $KeyPath)) {
    if ($NonInteractive) {
        Write-Host "[خطأ] لم يُحدد مسار المفتاح الخاص -KeyPath" -ForegroundColor Red
        exit 1
    }

    Write-Host "تنبيه: لم يتم العثور على مفتاح التوقيع الخاص (RSA Private Key)." -ForegroundColor Yellow
    Write-Host "المسار الافتراضي المتوقع: $DefaultKeyPath" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "خيارات المفتاح:" -ForegroundColor White
    Write-Host "  (1) توليد زوج مفاتيح RSA جديد تلقائياً الآن وحفظه في مجلد .madar (موصى به)" -ForegroundColor Green
    Write-Host "  (2) إدخال مسار ملف مفتاح خاص (.pem) موجود لديك بالفعل" -ForegroundColor White
    Write-Host ""
    $keyChoice = Read-Host "اختر (1 أو 2) [الافتراضي: 1]"
    if ([string]::IsNullOrWhiteSpace($keyChoice)) { $keyChoice = "1" }

    if ($keyChoice -eq "1") {
        if (-not (Test-Path -LiteralPath $DefaultKeyDir)) {
            New-Item -ItemType Directory -Path $DefaultKeyDir -Force | Out-Null
        }

        Write-Host "جاري توليد زوج مفاتيح RSA 2048-bit جديد..." -ForegroundColor Cyan
        $keygenCmd = "const c=require('crypto'),f=require('fs');const k=c.generateKeyPairSync('rsa',{modulusLength:2048,privateKeyEncoding:{type:'pkcs8',format:'pem'},publicKeyEncoding:{type:'spki',format:'pem'}});f.writeFileSync(process.argv[1],k.privateKey);f.writeFileSync(process.argv[2],k.publicKey);"
        & node -e $keygenCmd $DefaultKeyPath $DefaultPubPath
        $KeyPath = $DefaultKeyPath

        Write-Host "✔ تم إنشاء المفتاح الخاص: $DefaultKeyPath" -ForegroundColor Green
        Write-Host "✔ تم إنشاء المفتاح العام : $DefaultPubPath" -ForegroundColor Green

        # فحص وتحديث build_secrets.local.json تلقائياً إن وُجد
        $secretsFile = Join-Path $ProjectRoot "build_secrets.local.json"
        if (Test-Path -LiteralPath $secretsFile) {
            $updateSecrets = Read-Host "`nهل تريد تحديث المفتاح العام داخل build_secrets.local.json تلقائياً؟ (Y/n)"
            if ($updateSecrets -ne 'n' -and $updateSecrets -ne 'N') {
                $pubContent = Get-Content -LiteralPath $DefaultPubPath -Raw
                $secJson = Get-Content -LiteralPath $secretsFile -Raw | ConvertFrom-Json
                $secJson.LICENSE_PUBLIC_KEY = $pubContent
                $secJson | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $secretsFile -Encoding UTF8
                Write-Host "✔ تم تحديث LICENSE_PUBLIC_KEY في build_secrets.local.json بنجاح!" -ForegroundColor Green
            }
        }
        Write-Host ""
    } else {
        $enteredKey = Read-Host "أدخل المسار الكامل لملف المفتاح الخاص (.pem)"
        if (-not (Test-Path -LiteralPath $enteredKey)) {
            Write-Host "[خطأ] الملف غير موجود: $enteredKey" -ForegroundColor Red
            exit 1
        }
        $KeyPath = $enteredKey
    }
}

Write-Host "المفتاح الخاص المستخدم: $KeyPath" -ForegroundColor DarkGray
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

# ────────────────────────────────────────────────────────────────────────────
# 2) جمع بيانات العميل والجهاز
# ────────────────────────────────────────────────────────────────────────────
if (-not $HardwareId) {
    if ($NonInteractive) {
        Write-Host "[خطأ] -HardwareId مطلوب!" -ForegroundColor Red
        exit 1
    }
    while (-not $HardwareId) {
        $HardwareId = Read-Host "`nالصق معرف الجهاز (Hardware ID) الظاهر على شاشة تفعيل البرنامج"
        if ($HardwareId) { $HardwareId = $HardwareId.Trim() }
        if (-not $HardwareId) {
            Write-Host "معرف الجهاز مطلوب لربط الرخصة بجهاز العميل!" -ForegroundColor Red
        }
    }
}

if (-not $Customer) {
    if ($NonInteractive) {
        $Customer = "عميل MADAR"
    } else {
        $Customer = Read-Host "`nاسم العميل أو المحل (مثال: سوبرماركت الأمل) [اضغط Enter لـ 'عميل']"
        if ($Customer) { $Customer = $Customer.Trim() }
        if (-not $Customer) { $Customer = "عميل MADAR" }
    }
}

# ────────────────────────────────────────────────────────────────────────────
# 3) اختيار المدة ونوع الترخيص
# ────────────────────────────────────────────────────────────────────────────
if (-not $Months -and -not $Days -and -not $Lifetime) {
    if ($NonInteractive) {
        $Type = "paid"; $Months = 12
    } else {
        Write-Host "`nاختر مدة الترخيص:" -ForegroundColor White
        Write-Host "  (1) سنة كاملة (12 شهر - 365 يوماً) [الافتراضي]" -ForegroundColor Green
        Write-Host "  (2) ترخيص مدى الحياة (Lifetime)" -ForegroundColor White
        Write-Host "  (3) شهر واحد (30 يوماً)" -ForegroundColor White
        Write-Host "  (4) تجربة مجانية (7 أيام)" -ForegroundColor White
        Write-Host "  (5) تجربة مجانية (14 يوماً)" -ForegroundColor White
        Write-Host "  (6) تجربة مجانية (30 يوماً)" -ForegroundColor White
        Write-Host "  (7) مدة مخصصة بالأيام" -ForegroundColor White

        $durationChoice = Read-Host "أدخل رقم الاختيار (1-7) [الافتراضي: 1]"
        if ([string]::IsNullOrWhiteSpace($durationChoice)) { $durationChoice = "1" }

        switch ($durationChoice) {
            "1" { $Type = "paid"; $Months = 12 }
            "2" { $Type = "paid"; $Lifetime = $true }
            "3" { $Type = "paid"; $Months = 1 }
            "4" { $Type = "trial"; $Days = 7 }
            "5" { $Type = "trial"; $Days = 14 }
            "6" { $Type = "trial"; $Days = 30 }
            "7" {
                $customDays = Read-Host "أدخل عدد الأيام"
                $Days = [int]$customDays
                $Type = "paid"
            }
            Default { $Type = "paid"; $Months = 12 }
        }
    }
}

if (-not $Type) { $Type = "paid" }

# ────────────────────────────────────────────────────────────────────────────
# 4) اختيار الميزات والموديولات (Features & Modules)
# ────────────────────────────────────────────────────────────────────────────
$AllFeaturesList = "pos,cash_sales,credit_sales,customers,suppliers,purchases,inventory,reports,advanced_reports,backup,auto_backup,staff_management,attendance,payroll,custody,damaged_goods,manufacturing"
$StandardFeaturesList = "pos,cash_sales,credit_sales,customers,suppliers,purchases,inventory,reports,advanced_reports,backup,auto_backup"
$BasicFeaturesList = "pos,cash_sales,inventory,reports,backup"

if (-not $Features) {
    if ($NonInteractive) {
        $Features = $AllFeaturesList; $Plan = "professional"
    } else {
        Write-Host "`nاختر باقة الموديولات:" -ForegroundColor White
        Write-Host "  (1) الباقة الاحترافية الشاملة (جميع الميزات: تصنيع، موظفين، عهد، توالف، تقارير أرباح...) [الافتراضي]" -ForegroundColor Green
        Write-Host "  (2) الباقة القياسية (نقاط بيع، مبيعات آجلة، موردين، عملاء، مخزون، تقارير)" -ForegroundColor White
        Write-Host "  (3) الباقة الأساسية (نقاط بيع، مبيعات نقدية، مخزون، تقارير أساسية)" -ForegroundColor White
        Write-Host "  (4) إدخال ميزات مخصصة يدوياً" -ForegroundColor White

        $featChoice = Read-Host "أدخل رقم الاختيار (1-4) [الافتراضي: 1]"
        if ([string]::IsNullOrWhiteSpace($featChoice)) { $featChoice = "1" }

        switch ($featChoice) {
            "1" { $Features = $AllFeaturesList; $Plan = "professional" }
            "2" { $Features = $StandardFeaturesList; $Plan = "standard" }
            "3" { $Features = $BasicFeaturesList; $Plan = "basic" }
            "4" {
                Write-Host "الميزات المتاحة: $AllFeaturesList" -ForegroundColor DarkGray
                $Features = Read-Host "أدخل الميزات مفصولة بفواصل"
                $Plan = "custom"
            }
            Default { $Features = $AllFeaturesList; $Plan = "professional" }
        }
    }
}

if (-not $Plan) { $Plan = "professional" }

# ────────────────────────────────────────────────────────────────────────────
# 5) تجهيز مسار مجلد الإخراج
# ────────────────────────────────────────────────────────────────────────────
$DefaultOutDir = Join-Path $env:USERPROFILE "Desktop\MadarLicenses"
if (-not $OutputDir) {
    $OutputDir = $DefaultOutDir
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# صياغة اسم ملف آمن
$safeCustomer = $Customer -replace '[\\/:*?"<>| ]', '_'
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputFile = Join-Path $OutputDir "${safeCustomer}_${timestamp}.madarlicense"

# ────────────────────────────────────────────────────────────────────────────
# 6) تشغيل أداة الإصدار (tools/license_issuer.js)
# ────────────────────────────────────────────────────────────────────────────
Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "جاري إصدار وتوقيع ملف الترخيص..." -ForegroundColor Cyan

$nodeArgs = @(
    $IssuerJs,
    "--type", $Type,
    "--bind", "hardware",
    "--hardware-id", $HardwareId,
    "--features", $Features,
    "--customer", $Customer,
    "--plan", $Plan,
    "--key", $KeyPath,
    "--out", $OutputFile
)

if ($Lifetime) {
    $nodeArgs += "--lifetime"
} elseif ($Months) {
    $nodeArgs += @("--months", $Months.ToString())
} elseif ($Days) {
    $nodeArgs += @("--days", $Days.ToString())
}

try {
    & node $nodeArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n[فشل] تعذّر إصدار الترخيص. راجع رسالة الخطأ أعلاه." -ForegroundColor Red
        exit $LASTEXITCODE
    }
} catch {
    Write-Host "`n[خطأ أثناء التنفيذ]: $_" -ForegroundColor Red
    exit 1
}

# ────────────────────────────────────────────────────────────────────────────
# 7) النتيجة والخيارات التالية
# ────────────────────────────────────────────────────────────────────────────
Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "  ✔ تم استخراج ملف الترخيص بنجاح!" -ForegroundColor Green
Write-Host "  الملف: $OutputFile" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green

# نسخ مسار الملف للحافظة
try {
    Set-Clipboard -Value $OutputFile
    Write-Host "📋 تم نسخ مسار الملف إلى الحافظة (Clipboard)." -ForegroundColor DarkGreen
} catch {}

Write-Host "`nطريقة تسليم وتفعيل الرخصة عند العميل:" -ForegroundColor Yellow
Write-Host "  1. أرسل ملف (.madarlicense) إلى العميل (واتساب أو فلاشة)." -ForegroundColor White
Write-Host "  2. في شاشة التفعيل، يضغط العميل: «استيراد رخصة من ملف (بدون إنترنت)»." -ForegroundColor White
Write-Host "  3. يختار هذا الملف، وسيتم تفعيل النظام فوراً وبدون أي إنترنت.`n" -ForegroundColor White

if (-not $NonInteractive) {
    $openFolder = Read-Host "هل تريد فتح مجلد التراخيص الآن؟ (Y/n)"
    if ($openFolder -ne 'n' -and $openFolder -ne 'N') {
        explorer.exe "/select,$OutputFile"
    }
}
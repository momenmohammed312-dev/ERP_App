# ════════════════════════════════════════════════════════════════════════════
# POS System v2.3.0 - Update Installer
# DEVELOPED BY MO2 | Contact: 01025545211
# ════════════════════════════════════════════════════════════════════════════

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ════════════════════════════════════════════════════════════════════════════
# Config
# ════════════════════════════════════════════════════════════════════════════

$script:AppName = "POS System"
$script:AppVersion = "2.3.0"
$script:AppPublisher = "DEVELOPED BY MO2"
$script:AppContact = "01025545211"
$script:AppURL = "https://mo2.dev"
$script:AppExeName = "pos_offline_desktop.exe"
$script:ZipFileName = "pos_update_package.zip"
$script:InstallDir = Join-Path $env:ProgramFiles $script:AppName

# ════════════════════════════════════════════════════════════════════════════
# Helpers
# ════════════════════════════════════════════════════════════════════════════

function Test-AdminCheck {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Msg {
    param([string]$Msg, [string]$Title = "POS System", [System.Windows.Forms.MessageBoxButtons]$Btns = [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information)
    return [System.Windows.Forms.MessageBox]::Show($Msg, $Title, $Btns, $Icon)
}

# ════════════════════════════════════════════════════════════════════════════
# Welcome Screen
# ════════════════════════════════════════════════════════════════════════════

function Show-Welcome {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "$script:AppName} v$script:AppVersion} - Update Installer"
    $f.Size = New-Object System.Drawing.Size(580, 420)
    $f.StartPosition = "CenterScreen"
    $f.FormBorderStyle = "FixedDialog"
    $f.MaximizeBox = $false
    $f.BackColor = [System.Drawing.Color]::White
    $f.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Header
    $hdr = New-Object System.Windows.Forms.Panel
    $hdr.Location = New-Object System.Drawing.Point(0, 0)
    $hdr.Size = New-Object System.Drawing.Size(580, 90)
    $hdr.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $f.Controls.Add($hdr)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "$script:AppName} v$script:AppVersion} Update"
    $lblTitle.Location = New-Object System.Drawing.Point(25, 15)
    $lblTitle.Size = New-Object System.Drawing.Size(530, 35)
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.BackColor = [System.Drawing.Color]::Transparent
    $hdr.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "$script:AppPublisher} | $script:AppContact}"
    $lblSub.Location = New-Object System.Drawing.Point(25, 55)
    $lblSub.Size = New-Object System.Drawing.Size(530, 25)
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(200, 220, 240)
    $lblSub.BackColor = [System.Drawing.Color]::Transparent
    $hdr.Controls.Add($lblSub)

    # Content
    $lblBody = New-Object System.Windows.Forms.Label
    $lblBody.Text = "This update includes new features and important fixes:`n`n" +
                    "NEW FEATURES:`n" +
                    "  + QR Code Support - Generate and print QR codes`n" +
                    "  + Enhanced Customer Management - Edit all customer data`n" +
                    "  + Delete Customers - Remove customers from edit page`n`n" +
                    "FIXES:`n" +
                    "  + Fixed unexpected security warnings`n" +
                    "  + Improved system stability`n`n" +
                    "Your existing data will be preserved."
    $lblBody.Location = New-Object System.Drawing.Point(25, 105)
    $lblBody.Size = New-Object System.Drawing.Size(530, 200)
    $lblBody.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $f.Controls.Add($lblBody)

    # Buttons
    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = "Install Update"
    $btnInstall.Location = New-Object System.Drawing.Point(400, 320)
    $btnInstall.Size = New-Object System.Drawing.Size(150, 40)
    $btnInstall.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnInstall.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnInstall.ForeColor = [System.Drawing.Color]::White
    $btnInstall.FlatStyle = "Flat"
    $btnInstall.FlatAppearance.BorderSize = 0
    $btnInstall.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnInstall.Add_Click({ $f.Tag = "go"; $f.Close() })
    $f.Controls.Add($btnInstall)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(240, 320)
    $btnCancel.Size = New-Object System.Drawing.Size(150, 40)
    $btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCancel.Add_Click({ $f.Tag = "cancel"; $f.Close() })
    $f.Controls.Add($btnCancel)

    $f.ShowDialog() | Out-Null
    return $f.Tag
}

# ════════════════════════════════════════════════════════════════════════════
# Install Progress
# ════════════════════════════════════════════════════════════════════════════

function Show-Progress {
    param([string]$ZipPath, [string]$DestPath)

    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Installing $script:AppName} v$script:AppVersion}..."
    $f.Size = New-Object System.Drawing.Size(480, 280)
    $f.StartPosition = "CenterScreen"
    $f.FormBorderStyle = "FixedDialog"
    $f.MaximizeBox = $false
    $f.BackColor = [System.Drawing.Color]::White
    $f.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Installing update..."
    $lbl.Location = New-Object System.Drawing.Point(25, 20)
    $lbl.Size = New-Object System.Drawing.Size(430, 30)
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $f.Controls.Add($lbl)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Preparing..."
    $lblStatus.Location = New-Object System.Drawing.Point(25, 65)
    $lblStatus.Size = New-Object System.Drawing.Size(430, 25)
    $f.Controls.Add($lblStatus)

    $pb = New-Object System.Windows.Forms.ProgressBar
    $pb.Location = New-Object System.Drawing.Point(25, 105)
    $pb.Size = New-Object System.Drawing.Size(430, 25)
    $pb.Style = "Marquee"
    $pb.MarqueeAnimationSpeed = 30
    $f.Controls.Add($pb)

    $lblDetail = New-Object System.Windows.Forms.Label
    $lblDetail.Text = ""
    $lblDetail.Location = New-Object System.Drawing.Point(25, 145)
    $lblDetail.Size = New-Object System.Drawing.Size(430, 40)
    $lblDetail.ForeColor = [System.Drawing.Color]::Gray
    $f.Controls.Add($lblDetail)

    $btnFinish = New-Object System.Windows.Forms.Button
    $btnFinish.Text = "Finish"
    $btnFinish.Location = New-Object System.Drawing.Point(330, 200)
    $btnFinish.Size = New-Object System.Drawing.Size(120, 35)
    $btnFinish.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnFinish.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnFinish.ForeColor = [System.Drawing.Color]::White
    $btnFinish.FlatStyle = "Flat"
    $btnFinish.FlatAppearance.BorderSize = 0
    $btnFinish.Enabled = $false
    $btnFinish.Add_Click({ $f.Tag = "done"; $f.Close() })
    $f.Controls.Add($btnFinish)

    $f.Add_Shown({
        # Close running app
        $lblStatus.Text = "Closing application if running..."
        $f.Refresh()
        Get-Process -Name "pos_offline_desktop" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Create dir
        $lblStatus.Text = "Creating directory..."
        $f.Refresh()
        if (-not (Test-Path $DestPath)) {
            New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
        }
        Start-Sleep -Milliseconds 500

        # Extract
        $lblStatus.Text = "Extracting files..."
        $lblDetail.Text = "This may take a moment..."
        $f.Refresh()
        try {
            Expand-Archive -Path $ZipPath -DestinationPath $DestPath -Force
            Start-Sleep -Seconds 1
        } catch {
            Show-Msg -Msg "Extraction failed: $_" -Icon "Error"
            $f.Tag = "err"
            $f.Close()
            return
        }

        # Shortcuts
        $lblStatus.Text = "Creating shortcuts..."
        $f.Refresh()
        try {
            $ws = New-Object -ComObject WScript.Shell
            $sc1 = $ws.CreateShortcut("$env:Public\Desktop\$script:AppName}.lnk")
            $sc1.TargetPath = Join-Path $DestPath $script:AppExeName
            $sc1.WorkingDirectory = $DestPath
            $sc1.Save()
            $sc2 = $ws.CreateShortcut("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\$script:AppName}.lnk")
            $sc2.TargetPath = Join-Path $DestPath $script:AppExeName
            $sc2.WorkingDirectory = $DestPath
            $sc2.Save()
        } catch { }

        # Done
        $lblStatus.Text = "Installation completed!"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 128, 0)
        $lblDetail.Text = "Installed to: $DestPath"
        $pb.Style = "Continuous"
        $pb.Value = 100
        $btnFinish.Enabled = $true
        $f.Refresh()
    })

    $f.ShowDialog() | Out-Null
    return $f.Tag
}

# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

function Start-Install {
    if (-not (Test-AdminCheck)) {
        Show-Msg -Msg "Please run as administrator." -Icon "Warning"
        return
    }

    $zipPath = Join-Path $PSScriptRoot $script:ZipFileName
    if (-not (Test-Path $zipPath)) {
        $zipPath = Join-Path $PWD $script:ZipFileName
        if (-not (Test-Path $zipPath)) {
            Show-Msg -Msg "Cannot find $script:ZipFileName`nPlease ensure it is in the same folder as this installer." -Icon "Error"
            return
        }
    }

    $result = Show-Welcome
    if ($result -ne "go") { return }

    # Check running
    $running = Get-Process -Name "pos_offline_desktop" -ErrorAction SilentlyContinue
    if ($running) {
        $r = Show-Msg -Msg "Application is running. It will be closed to continue.`n`nContinue?" -Buttons "YesNo" -Icon "Warning"
        if ($r -ne "Yes") { return }
    }

    $installResult = Show-Progress -ZipPath $zipPath -DestPath $script:InstallDir

    if ($installResult -eq "done") {
        $lr = Show-Msg -Msg "$script:AppName} v$script:AppVersion} installed successfully!`n`nLaunch now?" -Buttons "YesNo" -Icon "Information"
        if ($lr -eq "Yes") {
            $exe = Join-Path $script:InstallDir $script:AppExeName
            if (Test-Path $exe) { Start-Process -FilePath $exe }
        }
    }
}

Start-Install

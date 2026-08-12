# ════════════════════════════════════════════════════════════════════════════
# POS System v2.3.0 - Update Installer
# DEVELOPED BY MO2 | Contact: 01025545211
# PowerShell-based installer with Windows Forms UI
# ════════════════════════════════════════════════════════════════════════════

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ════════════════════════════════════════════════════════════════════════════
# Configuration
# ════════════════════════════════════════════════════════════════════════════

$script:AppName = "POS System"
$script:AppVersion = "2.3.0"
$script:AppPublisher = "DEVELOPED BY MO2"
$script:AppContact = "01025545211"
$script:AppURL = "https://mo2.dev"
$script:AppExeName = "pos_offline_desktop.exe"
$script:InstallDir = Join-Path $env:ProgramFiles $script:AppName
$script:ZipFilePath = Join-Path $PSScriptRoot "pos_update_package.zip"
$script:LogoPath = Join-Path $PSScriptRoot "..\windows\runner\resources\app_icon.ico"

# ════════════════════════════════════════════════════════════════════════════
# Colors & Styling
# ════════════════════════════════════════════════════════════════════════════

$script:PrimaryColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$script:AccentColor = [System.Drawing.Color]::FromArgb(0, 90, 158)
$script:TextColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
$script:LightGray = [System.Drawing.Color]::FromArgb(245, 245, 245)
$script:White = [System.Drawing.Color]::White
$script:BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)

# ════════════════════════════════════════════════════════════════════════════
# Helper Functions
# ════════════════════════════════════════════════════════════════════════════

function Show-MessageBox {
    param([string]$Message, [string]$Title = "POS System", [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information)
    return [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

function Test-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FileSizeMB {
    param([string]$Path)
    if (Test-Path $Path) {
        return [math]::Round((Get-Item $Path).Length / 1MB, 2)
    }
    return 0
}

function Install-VisualCRedist {
    param([string]$DownloadUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe")
    $tempFile = Join-Path $env:TEMP "vc_redist.x64.exe"
    try {
        $progressForm = New-Object System.Windows.Forms.Form
        $progressForm.Text = "Installing Prerequisites..."
        $progressForm.Size = New-Object System.Drawing.Size(400, 120)
        $progressForm.StartPosition = "CenterScreen"
        $progressForm.FormBorderStyle = "FixedDialog"
        $progressLabel = New-Object System.Windows.Forms.Label
        $progressLabel.Text = "Downloading Visual C++ Runtime..."
        $progressLabel.Location = New-Object System.Drawing.Point(20, 20)
        $progressLabel.Size = New-Object System.Drawing.Size(360, 30)
        $progressLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $progressForm.Controls.Add($progressLabel)
        $progressForm.Show()
        $progressForm.Refresh()
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        (New-Object System.Net.WebClient).DownloadFile($DownloadUrl, $tempFile)
        $progressLabel.Text = "Installing Visual C++ Runtime..."
        $progressForm.Refresh()
        $process = Start-Process -FilePath $tempFile -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
        $progressForm.Close()
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            return $true
        }
        return $false
    } catch {
        if ($progressForm) { $progressForm.Close() }
        return $false
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

# ════════════════════════════════════════════════════════════════════════════
# Welcome Page
# ════════════════════════════════════════════════════════════════════════════

function Show-WelcomePage {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$script:AppName v$script:AppVersion} - Update Installer"
    $form.Size = New-Object System.Drawing.Size(600, 450)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = $script:White
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon = if (Test-Path $script:LogoPath) { New-Object System.Drawing.Icon($script:LogoPath) } else { [System.Drawing.SystemIcons]::Application }

    # Header panel
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Location = New-Object System.Drawing.Point(0, 0)
    $headerPanel.Size = New-Object System.Drawing.Size(600, 100)
    $headerPanel.BackColor = $script:PrimaryColor
    $form.Controls.Add($headerPanel)

    # Title
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "$script:AppName} v$script:AppVersion} Update"
    $titleLabel.Location = New-Object System.Drawing.Point(30, 20)
    $titleLabel.Size = New-Object System.Drawing.Size(540, 40)
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $script:White
    $titleLabel.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($titleLabel)

    # Subtitle
    $subtitleLabel = New-Object System.Windows.Forms.Label
    $subtitleLabel.Text = "DEVELOPED BY MO2 | $script:AppContact}"
    $subtitleLabel.Location = New-Object System.Drawing.Point(30, 60)
    $subtitleLabel.Size = New-Object System.Drawing.Size(540, 25)
    $subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $subtitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $subtitleLabel.BackColor = [System.Drawing.Color]::Transparent
    $headerPanel.Controls.Add($subtitleLabel)

    # Content
    $contentLabel = New-Object System.Windows.Forms.Label
    $contentLabel.Text = "This update includes new features and important fixes:`n`n" +
                         "NEW FEATURES:`n" +
                         "  + QR Code Support - Generate and print QR codes for products`n" +
                         "  + Enhanced Customer Management - Improved customer tracking`n`n" +
                         "FIXES:`n" +
                         "  + Fixed unexpected security warnings issue`n" +
                         "  + Improved system stability and performance`n`n" +
                         "This update will replace your existing installation. Your data will be preserved."
    $contentLabel.Location = New-Object System.Drawing.Point(30, 120)
    $contentLabel.Size = New-Object System.Drawing.Size(540, 220)
    $contentLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $contentLabel.ForeColor = $script:TextColor
    $form.Controls.Add($contentLabel)

    # Buttons
    $nextButton = New-Object System.Windows.Forms.Button
    $nextButton.Text = "Install Update"
    $nextButton.Location = New-Object System.Drawing.Point(420, 360)
    $nextButton.Size = New-Object System.Drawing.Size(150, 40)
    $nextButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $nextButton.BackColor = $script:PrimaryColor
    $nextButton.ForeColor = $script:White
    $nextButton.FlatStyle = "Flat"
    $nextButton.FlatAppearance.BorderSize = 0
    $nextButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $nextButton.Add_Click({ $form.Tag = "install"; $form.Close() })
    $form.Controls.Add($nextButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(260, 360)
    $cancelButton.Size = New-Object System.Drawing.Size(150, 40)
    $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $cancelButton.BackColor = $script:LightGray
    $cancelButton.ForeColor = $script:TextColor
    $cancelButton.FlatStyle = "Flat"
    $cancelButton.FlatAppearance.BorderColor = $script:BorderColor
    $cancelButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $cancelButton.Add_Click({ $form.Tag = "cancel"; $form.Close() })
    $form.Controls.Add($cancelButton)

    # Version info
    $versionLabel = New-Object System.Windows.Forms.Label
    $versionLabel.Text = "Version $script:AppVersion} | $script:AppPublisher}"
    $versionLabel.Location = New-Object System.Drawing.Point(30, 370)
    $versionLabel.Size = New-Object System.Drawing.Size(200, 25)
    $versionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $versionLabel.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($versionLabel)

    $form.ShowDialog() | Out-Null
    return $form.Tag
}

# ════════════════════════════════════════════════════════════════════════════
# Installation Progress Page
# ════════════════════════════════════════════════════════════════════════════

function Show-InstallProgress {
    param([string]$InstallPath)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Installing $script:AppName v$script:AppVersion}..."
    $form.Size = New-Object System.Drawing.Size(500, 300)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.BackColor = $script:White
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Icon = if (Test-Path $script:LogoPath) { New-Object System.Drawing.Icon($script:LogoPath) } else { [System.Drawing.SystemIcons]::Application }

    # Header
    $headerLabel = New-Object System.Windows.Forms.Label
    $headerLabel.Text = "Installing Update..."
    $headerLabel.Location = New-Object System.Drawing.Point(30, 20)
    $headerLabel.Size = New-Object System.Drawing.Size(440, 35)
    $headerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $headerLabel.ForeColor = $script:PrimaryColor
    $form.Controls.Add($headerLabel)

    # Status label
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Preparing installation..."
    $statusLabel.Location = New-Object System.Drawing.Point(30, 70)
    $statusLabel.Size = New-Object System.Drawing.Size(440, 25)
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.Controls.Add($statusLabel)

    # Progress bar
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(30, 110)
    $progressBar.Size = New-Object System.Drawing.Size(440, 30)
    $progressBar.Style = "Marquee"
    $progressBar.MarqueeAnimationSpeed = 30
    $form.Controls.Add($progressBar)

    # Detail label
    $detailLabel = New-Object System.Windows.Forms.Label
    $detailLabel.Text = ""
    $detailLabel.Location = New-Object System.Drawing.Point(30, 160)
    $detailLabel.Size = New-Object System.Drawing.Size(440, 60)
    $detailLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $detailLabel.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($detailLabel)

    # Finish button (hidden initially)
    $finishButton = New-Object System.Windows.Forms.Button
    $finishButton.Text = "Finish"
    $finishButton.Location = New-Object System.Drawing.Point(350, 220)
    $finishButton.Size = New-Object System.Drawing.Size(120, 35)
    $finishButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $finishButton.BackColor = $script:PrimaryColor
    $finishButton.ForeColor = $script:White
    $finishButton.FlatStyle = "Flat"
    $finishButton.FlatAppearance.BorderSize = 0
    $finishButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $finishButton.Enabled = $false
    $finishButton.Add_Click({ $form.Tag = "finished"; $form.Close() })
    $form.Controls.Add($finishButton)

    # Start installation in background
    $installJob = {
        param($FormHandle, $ExePath, $DestPath)
        # This runs in background
    }

    $form.Add_Shown({
        # Close existing app
        $statusLabel.Text = "Closing application if running..."
        $form.Refresh()
        Get-Process -Name "pos_offline_desktop" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Create directory
        $statusLabel.Text = "Creating installation directory..."
        $form.Refresh()
        if (-not (Test-Path $InstallPath)) {
            New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        }
        Start-Sleep -Seconds 1

        # Extract files
        $statusLabel.Text = "Extracting application files..."
        $detailLabel.Text = "This may take a few moments..."
        $form.Refresh()
        try {
            Expand-Archive -Path $script:ZipFilePath -DestinationPath $InstallPath -Force
            Start-Sleep -Seconds 2
        } catch {
            Show-MessageBox -Message "Failed to extract files: $_" -Title "Installation Error" -Icon "Error"
            $form.Tag = "error"
            $form.Close()
            return
        }

        # Create shortcuts
        $statusLabel.Text = "Creating shortcuts..."
        $form.Refresh()
        try {
            $WshShell = New-Object -ComObject WScript.Shell
            $shortcut = $WshShell.CreateShortcut("$env:Public\Desktop\$script:AppName}.lnk")
            $shortcut.TargetPath = Join-Path $InstallPath $script:AppExeName
            $shortcut.WorkingDirectory = $InstallPath
            $shortcut.Save()
            $shortcut2 = $WshShell.CreateShortcut("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\$script:AppName}.lnk")
            $shortcut2.TargetPath = Join-Path $InstallPath $script:AppExeName
            $shortcut2.WorkingDirectory = $InstallPath
            $shortcut2.Save()
        } catch {
            # Shortcut creation failed, continue anyway
        }

        # Finish
        $statusLabel.Text = "Installation completed successfully!"
        $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 128, 0)
        $detailLabel.Text = "$script:AppName} v$script:AppVersion} has been installed to:`n$InstallPath"
        $progressBar.Style = "Continuous"
        $progressBar.Value = 100
        $finishButton.Enabled = $true
        $form.AcceptButton = $finishButton
        $form.Refresh()
    })

    $form.ShowDialog() | Out-Null
    return $form.Tag
}

# ════════════════════════════════════════════════════════════════════════════
# Main Installation Flow
# ════════════════════════════════════════════════════════════════════════════

function Start-Installation {
    # Check admin rights
    if (-not (Test-Admin)) {
        Show-MessageBox -Message "This installer requires administrator rights. Please run as administrator." -Title "Administrator Required" -Icon "Warning"
        return
    }

    # Check if zip file exists
    if (-not (Test-Path $script:ZipFilePath)) {
        Show-MessageBox -Message "Installation package not found: $script:ZipFilePath`nPlease ensure the zip file is in the same directory as this installer." -Title "File Not Found" -Icon "Error"
        return
    }

    # Show welcome page
    $result = Show-WelcomePage
    if ($result -ne "install") {
        return
    }

    # Check if app is running
    $running = Get-Process -Name "pos_offline_desktop" -ErrorAction SilentlyContinue
    if ($running) {
        $closeResult = Show-MessageBox -Message "The application is currently running. It must be closed to continue installation.`n`nClose the application and continue?" -Title "Application Running" -Buttons "YesNo" -Icon "Warning"
        if ($closeResult -ne "Yes") {
            return
        }
    }

    # Show installation progress
    $installResult = Show-InstallProgress -InstallPath $script:InstallDir

    if ($installResult -eq "finished") {
        $launchResult = Show-MessageBox -Message "$script:AppName} v$script:AppVersion} has been installed successfully!`n`nWould you like to launch the application now?" -Title "Installation Complete" -Buttons "YesNo" -Icon "Information"
        if ($launchResult -eq "Yes") {
            $exePath = Join-Path $script:InstallDir $script:AppExeName
            if (Test-Path $exePath) {
                Start-Process -FilePath $exePath
            }
        }
    }
}

# ════════════════════════════════════════════════════════════════════════════
# Entry Point
# ════════════════════════════════════════════════════════════════════════════

Start-Installation
